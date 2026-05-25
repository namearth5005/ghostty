import Foundation

struct TerminalUnderstandingProjector {
    func project(
        current: TerminalSnapshot,
        classification: AgentMeaningDetector.Detection?,
        lastOutcome: TerminalOutcomeReport?,
        lastEvent: String,
        workerSnapshot: TerminalWorkerSnapshot? = nil
    ) -> TerminalUnderstanding {
        if let workerSnapshot {
            return projectAuthoritatively(
                current: current,
                lastEvent: lastEvent,
                workerSnapshot: workerSnapshot
            )
        }

        let effectiveLastEvent = resolvedLastMeaningfulEvent(
            lastEvent: lastEvent,
            classification: classification
        )
        let state = classifyState(
            current: current,
            lastOutcome: lastOutcome,
            classification: classification
        )
        let suggestedActions = makeSuggestions(
            for: current,
            state: state,
            classification: classification,
            lastEvent: effectiveLastEvent
        )

        return TerminalUnderstanding(
            terminalID: current.terminalID,
            title: current.title,
            cwd: current.cwd,
            state: state,
            agentIdentity: classification?.identity ?? .none,
            agentInteractionState: classification?.interactionState ?? .unknown,
            supportLevel: classification?.supportLevel ?? .genericFallback,
            lastMeaningfulEvent: effectiveLastEvent,
            shortExplanation: explain(
                state: state,
                snapshot: current,
                classification: classification,
                lastEvent: effectiveLastEvent
            ),
            importantDetails: importantDetails(from: current.visibleText, state: state),
            evidence: classification?.evidence ?? [],
            suggestedNextActions: suggestedActions,
            agentInteractionContext: classification?.context ?? .none
        )
    }

    private func projectAuthoritatively(
        current: TerminalSnapshot,
        lastEvent: String,
        workerSnapshot: TerminalWorkerSnapshot
    ) -> TerminalUnderstanding {
        let authoritativeLastEvent = workerSnapshot.request?.prompt ?? lastEvent
        let state = understandingState(for: workerSnapshot.state.lifecycle)

        return TerminalUnderstanding(
            terminalID: current.terminalID,
            title: current.title,
            cwd: current.cwd,
            state: state,
            agentIdentity: workerSnapshot.agent.identity,
            agentInteractionState: interactionState(for: workerSnapshot),
            supportLevel: .firstClass,
            lastMeaningfulEvent: authoritativeLastEvent,
            shortExplanation: workerSnapshot.state.summary,
            importantDetails: workerSnapshot.state.details,
            evidence: [.init(source: .runtime, detail: "authoritative_worker_snapshot", confidence: 1.0)],
            suggestedNextActions: authoritativeSuggestedActions(
                for: workerSnapshot,
                state: state,
                lastEvent: authoritativeLastEvent
            ),
            agentInteractionContext: interactionContext(from: workerSnapshot),
            workerSnapshot: workerSnapshot
        )
    }

    private func resolvedLastMeaningfulEvent(
        lastEvent: String,
        classification: AgentMeaningDetector.Detection?
    ) -> String {
        let trimmed = lastEvent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || trimmed == "No meaningful terminal event detected." else {
            return lastEvent
        }

        guard let classification else {
            return lastEvent
        }

        switch classification.context {
        case .waitingText(let question, _, _, _, _):
            return question ?? lastEvent
        case .waitingChoice(let question, _, _, _, _, _):
            return question
        case .waitingApproval(let description, _, _, _, _, _):
            return description.isEmpty ? lastEvent : description
        case .running(let stepDescription, _, _):
            return stepDescription ?? lastEvent
        case .completed(let summary, _, _):
            return summary ?? lastEvent
        case .error(let description, _, _):
            return description
        case .none:
            return lastEvent
        }
    }

    private func classifyState(
        current: TerminalSnapshot,
        lastOutcome: TerminalOutcomeReport?,
        classification: AgentMeaningDetector.Detection?
    ) -> TerminalUnderstandingState {
        if let classification {
            switch classification.interactionState {
            case .waitingApproval, .waitingChoice, .waitingText:
                return .waiting
            case .running:
                return .running
            case .completed:
                return .succeeded
            case .error:
                return .failed
            case .unknown:
                switch classification.runtimeState {
                case .blocked:
                    return .waiting
                case .working:
                    return .running
                case .idle:
                    return .idle
                case .unknown:
                    break
                }
            }
        }

        if let lastOutcome, lastOutcome.terminalID == current.terminalID {
            switch lastOutcome.outcome {
            case .success:
                return .succeeded
            case .failure:
                return .failed
            case .needsInput:
                return .waiting
            case .hung:
                return .failed
            case .stillRunning, .unknown:
                break
            }
        }
        if current.visibleText.lowercased().contains("command not found") || current.signals.likelyErrorState {
            return .failed
        }
        if current.signals.likelyWaitingForInput {
            return .waiting
        }
        if current.signals.likelyLongRunning {
            return .running
        }
        if current.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .idle
        }
        return .noisyHealthy
    }

    private func explain(
        state: TerminalUnderstandingState,
        snapshot: TerminalSnapshot,
        classification: AgentMeaningDetector.Detection?,
        lastEvent: String
    ) -> String {
        if let classification {
            let name = classification.identity.displayName ?? snapshot.title
            switch classification.interactionState {
            case .waitingApproval:
                return "\(name) is waiting for approval to continue."
            case .waitingChoice:
                return "\(name) is waiting for your selection."
            case .waitingText:
                if TerminalScreenText.looksLikeQuestion(lastEvent) {
                    return "\(name) is waiting for your response: \(lastEvent)"
                }
                return "\(name) is waiting for your response."
            case .running:
                return "\(name) is actively working in this terminal."
            case .completed:
                return "\(name) completed its turn: \(lastEvent)"
            case .error:
                return "\(name) hit an error: \(lastEvent)"
            case .unknown:
                break
            }
        }

        switch state {
        case .failed:
            return "The terminal failed: \(lastEvent)"
        case .succeeded:
            return "The terminal completed successfully: \(lastEvent)"
        case .running:
            return "The \(snapshot.title) terminal is still running a long-lived command."
        case .waiting:
            return "The terminal is waiting for input."
        case .idle:
            return "The terminal is idle."
        case .noisyHealthy:
            return "The terminal is producing output without signs of failure."
        }
    }

    private func understandingState(
        for lifecycle: TerminalWorkerLifecycle
    ) -> TerminalUnderstandingState {
        switch lifecycle {
        case .idle:
            return .idle
        case .running:
            return .running
        case .blocked:
            return .waiting
        case .completed:
            return .succeeded
        case .failed:
            return .failed
        }
    }

    private func interactionState(
        for workerSnapshot: TerminalWorkerSnapshot
    ) -> AgentInteractionState {
        switch workerSnapshot.state.attention {
        case .none:
            switch workerSnapshot.state.lifecycle {
            case .running:
                return .running
            case .completed:
                return .completed
            case .failed:
                return .error
            case .idle, .blocked:
                return .unknown
            }
        case .replyRequired:
            return .waitingText
        case .choiceRequired:
            return .waitingChoice
        case .approvalRequired:
            return .waitingApproval
        case .error:
            return .error
        }
    }

    private func interactionContext(
        from workerSnapshot: TerminalWorkerSnapshot
    ) -> AgentInteractionContext {
        let isPlanning = workerSnapshot.state.runtimeFlags.contains(.planning)
        let request = workerSnapshot.request

        switch workerSnapshot.state.attention {
        case .replyRequired:
            return .waitingText(
                question: request?.prompt,
                requestID: request?.id,
                sessionID: workerSnapshot.workerSessionID,
                revision: workerSnapshot.revision,
                isPlanning: isPlanning
            )

        case .choiceRequired:
            return .waitingChoice(
                question: request?.prompt ?? workerSnapshot.state.summary,
                options: request?.options.map(\.label) ?? [],
                requestID: request?.id,
                sessionID: workerSnapshot.workerSessionID,
                revision: workerSnapshot.revision,
                isPlanning: isPlanning
            )

        case .approvalRequired:
            return .waitingApproval(
                description: request?.prompt ?? workerSnapshot.state.summary,
                tool: request?.options.first?.label,
                requestID: request?.id,
                sessionID: workerSnapshot.workerSessionID,
                revision: workerSnapshot.revision,
                isPlanning: isPlanning
            )

        case .error:
            return .error(
                description: workerSnapshot.state.summary,
                sessionID: workerSnapshot.workerSessionID,
                revision: workerSnapshot.revision
            )

        case .none:
            switch workerSnapshot.state.lifecycle {
            case .running:
                return .running(
                    stepDescription: workerSnapshot.state.summary,
                    sessionID: workerSnapshot.workerSessionID,
                    revision: workerSnapshot.revision
                )
            case .completed:
                return .completed(
                    summary: workerSnapshot.state.summary,
                    sessionID: workerSnapshot.workerSessionID,
                    revision: workerSnapshot.revision
                )
            case .failed:
                return .error(
                    description: workerSnapshot.state.summary,
                    sessionID: workerSnapshot.workerSessionID,
                    revision: workerSnapshot.revision
                )
            case .idle, .blocked:
                return .none
            }
        }
    }

    private func makeSuggestedAction(
        from suggestion: TerminalWorkerSnapshot.Suggestion,
        fingerprint: String
    ) -> TerminalSuggestedAction {
        let payload = workerPayload(for: suggestion.payload)
        let guidancePrompt = guidancePrompt(for: suggestion.payload)
        return TerminalSuggestedAction(
            title: suggestion.title,
            command: command(for: suggestion.payload),
            reason: suggestion.rationale,
            isRecommended: suggestion.recommended,
            authoritativeFingerprint: payload == nil && guidancePrompt == nil ? nil : fingerprint,
            authoritativePayload: payload,
            guidancePrompt: guidancePrompt
        )
    }

    private func command(
        for payload: TerminalWorkerSnapshot.Payload
    ) -> String? {
        switch payload {
        case .command(let command):
            return command
        case .text, .option, .approval, .foremanPrompt:
            return nil
        }
    }

    private func workerPayload(
        for payload: TerminalWorkerSnapshot.Payload
    ) -> String? {
        switch payload {
        case .text(let value), .option(let value), .approval(let value):
            return value
        case .command, .foremanPrompt:
            return nil
        }
    }

    private func guidancePrompt(
        for payload: TerminalWorkerSnapshot.Payload
    ) -> String? {
        switch payload {
        case .foremanPrompt(let value):
            return value
        case .text, .command, .option, .approval:
            return nil
        }
    }

    private func authoritativeSuggestedActions(
        for workerSnapshot: TerminalWorkerSnapshot,
        state: TerminalUnderstandingState,
        lastEvent: String
    ) -> [TerminalSuggestedAction] {
        let guidancePrompt = workerSnapshot.request?.prompt ?? workerSnapshot.state.summary

        if !workerSnapshot.suggestions.isEmpty {
            return workerSnapshot.suggestions.map {
                makeSuggestedAction(from: $0, fingerprint: workerSnapshot.attentionFingerprint)
            }
        }

        switch workerSnapshot.state.attention {
        case .approvalRequired:
            return [
                .init(
                    title: "Review the approval request",
                    command: nil,
                    reason: lastEvent,
                    isRecommended: true,
                    authoritativeFingerprint: workerSnapshot.attentionFingerprint,
                    guidancePrompt: guidancePrompt
                ),
                .init(
                    title: "Let Foreman explain the requested action",
                    command: nil,
                    reason: "Use this when the approval UI is dense.",
                    isRecommended: false,
                    authoritativeFingerprint: workerSnapshot.attentionFingerprint,
                    guidancePrompt: guidancePrompt
                ),
            ]

        case .choiceRequired:
            if let request = workerSnapshot.request, !request.options.isEmpty {
                return request.options.prefix(4).enumerated().map { index, option in
                    TerminalSuggestedAction(
                        title: option.label,
                        command: nil,
                        reason: request.prompt,
                        isRecommended: option.recommended || index == 0,
                        authoritativeFingerprint: workerSnapshot.attentionFingerprint,
                        authoritativePayload: option.id
                    )
                }
            }

            return [
                .init(
                    title: "Inspect the available choices",
                    command: nil,
                    reason: lastEvent,
                    isRecommended: true,
                    authoritativeFingerprint: workerSnapshot.attentionFingerprint,
                    guidancePrompt: guidancePrompt
                ),
                .init(
                    title: "Ask Foreman to summarize the options",
                    command: nil,
                    reason: "Useful when the menu is noisy.",
                    isRecommended: false,
                    authoritativeFingerprint: workerSnapshot.attentionFingerprint,
                    guidancePrompt: guidancePrompt
                ),
            ]

        case .replyRequired:
            return [
                .init(
                    title: "Reply to the agent",
                    command: nil,
                    reason: lastEvent,
                    isRecommended: true,
                    authoritativeFingerprint: workerSnapshot.attentionFingerprint,
                    guidancePrompt: guidancePrompt
                ),
            ]

        case .error:
            return [
                .init(
                    title: "Inspect the failure details",
                    command: nil,
                    reason: lastEvent,
                    isRecommended: true,
                    authoritativeFingerprint: workerSnapshot.attentionFingerprint,
                    guidancePrompt: guidancePrompt
                ),
            ]

        case .none:
            switch state {
            case .failed:
                return [
                    .init(title: "Inspect the failure details", command: nil, reason: lastEvent, isRecommended: true),
                ]
            case .idle, .running, .succeeded, .waiting, .noisyHealthy:
                return []
            }
        }
    }

    private func importantDetails(from visibleText: String, state: TerminalUnderstandingState) -> [String] {
        let lines: [String]
        switch state {
        case .waiting:
            lines = TerminalScreenText.meaningfulLines(from: visibleText)
        default:
            lines = visibleText.split(separator: "\n").map(String.init)
        }

        switch state {
        case .failed:
            return Array(lines.suffix(3))
        default:
            return Array(lines.suffix(2))
        }
    }

    private func makeSuggestions(
        for snapshot: TerminalSnapshot,
        state: TerminalUnderstandingState,
        classification: AgentMeaningDetector.Detection?,
        lastEvent: String
    ) -> [TerminalSuggestedAction] {
        let input = snapshot.lastInputPreview ?? ""

        if let classification {
            switch classification.interactionState {
            case .waitingApproval:
                return [
                    .init(title: "Review the approval request", command: nil, reason: lastEvent, isRecommended: true),
                    .init(title: "Let Foreman explain the requested action", command: nil, reason: "Use this when the approval UI is dense.", isRecommended: false),
                ]
            case .waitingChoice:
                return [
                    .init(title: "Inspect the available choices", command: nil, reason: lastEvent, isRecommended: true),
                    .init(title: "Ask Foreman to summarize the options", command: nil, reason: "Useful when the menu is noisy.", isRecommended: false),
                ]
            case .waitingText:
                return [
                    .init(title: "Reply to the agent", command: nil, reason: lastEvent, isRecommended: true),
                ]
            case .error:
                return [
                    .init(title: "Inspect the failure details", command: nil, reason: lastEvent, isRecommended: true),
                ]
            case .running, .completed, .unknown:
                break
            }
        }

        if state == .failed && lastEvent.lowercased().contains("command not found") && input.contains("hfind") {
            return [
                .init(
                    title: "Run the likely intended find command",
                    command: "find . -print",
                    reason: "This looks like a typo of a standard shell command.",
                    isRecommended: true
                ),
                .init(
                    title: "Try fd if a faster file search was intended",
                    command: "fd .",
                    reason: "The intended tool may have been `fd` rather than `find`.",
                    isRecommended: false
                ),
                .init(
                    title: "Confirm whether hfind was intentional",
                    command: nil,
                    reason: "Use this when the missing command may be project-specific.",
                    isRecommended: false
                ),
            ]
        }

        if state == .failed {
            return [
                .init(title: "Inspect the failure details", command: nil, reason: lastEvent, isRecommended: true),
                .init(
                    title: "Rerun the command after fixing the obvious issue",
                    command: input.isEmpty ? nil : input,
                    reason: "Useful when the failure was transient or typo-driven.",
                    isRecommended: false
                ),
                .init(
                    title: "Ask Foreman for a focused explanation",
                    command: nil,
                    reason: "Useful if the output is noisy and needs compression.",
                    isRecommended: false
                ),
            ]
        }

        return []
    }
}
