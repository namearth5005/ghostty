import Foundation

struct TerminalWorkerSnapshotProjector {
    func project(
        snapshot: TerminalSnapshot,
        workerGoal: String?,
        identity: AgentIdentity,
        context: AgentInteractionContext,
        fallbackState: TerminalUnderstandingState
    ) -> TerminalWorkerSnapshot? {
        guard identity != .none else {
            return nil
        }

        let request = makeRequest(from: context)
        return TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: snapshot.terminalID,
            workerSessionID: context.sessionID ?? "\(identity.rawValue)-\(snapshot.terminalID)",
            revision: context.revision ?? 0,
            observedAt: .now,
            ttlMilliseconds: 15_000,
            workerGoal: workerGoal,
            agent: .init(identity: identity),
            state: .init(
                lifecycle: lifecycle(for: context, fallbackState: fallbackState),
                attention: attention(for: context),
                summary: summary(for: snapshot, identity: identity, context: context),
                details: details(for: context),
                runtimeFlags: context.isPlanning ? [.planning] : []
            ),
            request: request,
            suggestions: suggestions(for: context, request: request)
        )
    }

    private func lifecycle(
        for context: AgentInteractionContext,
        fallbackState: TerminalUnderstandingState
    ) -> TerminalWorkerLifecycle {
        switch context {
        case .running:
            return .running
        case .waitingApproval, .waitingChoice, .waitingText:
            return .blocked
        case .completed:
            return .completed
        case .error:
            return .failed
        case .none:
            switch fallbackState {
            case .idle:
                return .idle
            case .running, .noisyHealthy:
                return .running
            case .succeeded:
                return .completed
            case .failed:
                return .failed
            case .waiting:
                return .blocked
            }
        }
    }

    private func attention(for context: AgentInteractionContext) -> TerminalWorkerAttention {
        switch context {
        case .waitingApproval:
            return .approvalRequired
        case .waitingChoice:
            return .choiceRequired
        case .waitingText:
            return .replyRequired
        case .error:
            return .error
        case .running, .completed, .none:
            return .none
        }
    }

    private func summary(
        for snapshot: TerminalSnapshot,
        identity: AgentIdentity,
        context: AgentInteractionContext
    ) -> String {
        let name = identity.displayName ?? snapshot.title
        switch context {
        case .running(let stepDescription, _, _):
            return stepDescription ?? "\(name) is actively working."
        case .waitingApproval(let description, _, _, _, _, _):
            return description.isEmpty ? "\(name) is waiting for approval." : description
        case .waitingChoice(let question, _, _, _, _, _):
            return "\(name) is waiting for a choice: \(question)"
        case .waitingText(let question, _, _, _, _):
            if let question, !question.isEmpty {
                return "\(name) is waiting for your reply: \(question)"
            }
            return "\(name) is waiting for your reply."
        case .completed(let summary, _, _):
            return summary ?? "\(name) completed its turn."
        case .error(let description, _, _):
            return description
        case .none:
            return "\(name) has no active worker request."
        }
    }

    private func details(for context: AgentInteractionContext) -> [String] {
        switch context {
        case .waitingApproval(_, let tool, _, _, _, let isPlanning):
            return compactDetails(tool, isPlanning ? "Plan mode is active." : nil)
        case .waitingChoice(_, let options, _, _, _, let isPlanning):
            return compactDetails(
                options.isEmpty ? nil : "\(options.count) options are available.",
                isPlanning ? "Plan mode is active." : nil
            )
        case .waitingText(let question, _, _, _, let isPlanning):
            return compactDetails(
                question.flatMap { $0.isEmpty ? nil : $0 },
                isPlanning ? "Plan mode is active." : nil
            )
        case .running(let stepDescription, _, _):
            return compactDetails(stepDescription)
        case .completed(let summary, _, _):
            return compactDetails(summary)
        case .error(let description, _, _):
            return compactDetails(description)
        case .none:
            return []
        }
    }

    private func makeRequest(from context: AgentInteractionContext) -> TerminalWorkerSnapshot.Request? {
        switch context {
        case .waitingApproval(let description, let tool, let requestID, _, _, _):
            return .init(
                id: requestID ?? fallbackRequestID(for: TerminalWorkerSnapshot.Kind.approval, prompt: description),
                kind: .approval,
                prompt: description.isEmpty ? "Approval requested." : description,
                options: compactRequestOptions(tool)
            )
        case .waitingChoice(let question, let options, let requestID, _, _, _):
            return .init(
                id: requestID ?? fallbackRequestID(for: TerminalWorkerSnapshot.Kind.choice, prompt: question),
                kind: .choice,
                prompt: question,
                options: options.map { option in
                    .init(id: optionID(for: option), label: option, recommended: false)
                }
            )
        case .waitingText(let question, let requestID, _, _, _):
            guard let question, !question.isEmpty else {
                return nil
            }
            return .init(
                id: requestID ?? fallbackRequestID(for: TerminalWorkerSnapshot.Kind.reply, prompt: question),
                kind: .reply,
                prompt: question,
                options: []
            )
        case .running, .completed, .error, .none:
            return nil
        }
    }

    private func suggestions(
        for context: AgentInteractionContext,
        request: TerminalWorkerSnapshot.Request?
    ) -> [TerminalWorkerSnapshot.Suggestion] {
        switch context {
        case .waitingChoice(_, let options, _, _, _, _):
            guard let request else { return [] }
            return options.map { option in
                .init(
                    id: "choice-\(optionID(for: option))",
                    kind: .choice,
                    title: option,
                    payload: .option(optionID(for: option)),
                    rationale: "Worker-provided option.",
                    recommended: false,
                    execution: .manualOnly,
                    requestID: request.id
                )
            }
        default:
            return []
        }
    }

    private func optionID(for option: String) -> String {
        let pieces = option.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return pieces.isEmpty ? "option" : pieces.joined(separator: "_")
    }

    private func fallbackRequestID(
        for kind: TerminalWorkerSnapshot.Kind,
        prompt: String
    ) -> String {
        "\(kind.rawValue)-\(abs(prompt.hashValue))"
    }

    private func compactDetails(_ values: String?...) -> [String] {
        values.compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func compactRequestOptions(_ tool: String?) -> [TerminalWorkerSnapshot.Option] {
        guard let tool, !tool.isEmpty else {
            return []
        }
        return [.init(id: tool.lowercased(), label: tool, recommended: false)]
    }
}
