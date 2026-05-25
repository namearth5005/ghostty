import Foundation

protocol ForemanLLMClient: Sendable {
    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary
    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan
    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse
}

extension ForemanLLMClient {
    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        try await agentStep(
            narrationContext: narrationContext,
            terminals: terminals,
            understandings: understandings,
            overview: overview,
            lastOutcome: lastOutcome
        )
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        try await agentStep(
            narrationContext: narrationContext,
            terminals: terminals,
            lastOutcome: lastOutcome
        )
    }

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse {
        if let authoritative = authoritativeReplyDraftResponse(
            event: event,
            workerSnapshots: workerSnapshots
        ) {
            return authoritative
        }

        try await draftAgentReply(
            narrationContext: narrationContext,
            event: event,
            terminals: terminals,
            understandings: understandings,
            overview: overview,
            lastOutcome: lastOutcome
        )
    }

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse {
        let step = try await agentStep(
            narrationContext: narrationContext,
            terminals: terminals,
            understandings: understandings,
            overview: overview,
            lastOutcome: lastOutcome
        )
        return makeReplyDraftResponse(from: step, event: event)
    }

    private func makeReplyDraftResponse(
        from step: AgentStepResponse,
        event: AgentNeedsAttentionEvent
    ) -> AgentReplyDraftResponse {
        let suggestion: AgentReplyDraftSuggestion
        switch step.action {
        case .sendCommand(let terminalID, let command, let reason):
            suggestion = .replyToAgent(
                terminalID: terminalID,
                message: command,
                reason: reason,
                confidence: 0.6
            )
        case .askUser(let question):
            suggestion = .askHuman(
                terminalID: event.terminalID,
                message: question,
                reason: "The generic agent step requested human input.",
                confidence: 0.6
            )
        default:
            suggestion = .noAction(
                reason: "The generic agent step did not produce a waiting-text reply.",
                confidence: 0.4
            )
        }

        return .init(thought: step.thought, suggestion: suggestion)
    }

    private func authoritativeReplyDraftResponse(
        event: AgentNeedsAttentionEvent,
        workerSnapshots: [String: TerminalWorkerSnapshot]
    ) -> AgentReplyDraftResponse? {
        guard let snapshot = workerSnapshots[event.terminalID],
              let request = snapshot.request else {
            return nil
        }

        let requestSuggestions = snapshot.suggestions.filter { suggestion in
            suggestion.requestID == nil || suggestion.requestID == request.id
        }

        if let suggestion = requestSuggestions.first(where: \.recommended) ?? requestSuggestions.first {
            let payload = payloadString(for: suggestion.payload)
            let replySuggestion: AgentReplyDraftSuggestion

            switch suggestion.payload {
            case .foremanPrompt:
                replySuggestion = .askHuman(
                    terminalID: event.terminalID,
                    message: payload,
                    reason: suggestion.rationale.nilIfEmpty ?? "The structured worker snapshot requested project-level guidance.",
                    confidence: suggestion.recommended ? 1.0 : 0.8
                )
            case .text, .command, .option, .approval:
                replySuggestion = .replyToAgent(
                    terminalID: event.terminalID,
                    message: payload,
                    reason: suggestion.rationale,
                    confidence: suggestion.recommended ? 1.0 : 0.8
                )
            }

            return .init(
                thought: snapshot.state.summary,
                suggestion: replySuggestion
            )
        }

        return .init(
            thought: snapshot.state.summary,
            suggestion: .askHuman(
                terminalID: event.terminalID,
                message: request.prompt,
                reason: "The structured worker snapshot needs direction and did not provide a suggested reply.",
                confidence: 1.0
            )
        )
    }

    private func payloadString(for payload: TerminalWorkerSnapshot.Payload) -> String {
        switch payload {
        case .text(let value), .command(let value), .option(let value), .approval(let value), .foremanPrompt(let value):
            return value
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

actor ForemanService {
    private let client: any ForemanLLMClient

    init(client: any ForemanLLMClient) {
        self.client = client
    }

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        try await client.summarize(snapshot: snapshot)
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        try await client.planDispatch(instruction: instruction, summaries: summaries)
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        try await client.agentStep(
            narrationContext: narrationContext,
            terminals: terminals,
            understandings: understandings,
            workerSnapshots: workerSnapshots,
            overview: overview,
            lastOutcome: lastOutcome
        )
    }

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse {
        try await client.draftAgentReply(
            narrationContext: narrationContext,
            event: event,
            terminals: terminals,
            understandings: understandings,
            workerSnapshots: workerSnapshots,
            overview: overview,
            lastOutcome: lastOutcome
        )
    }
}
