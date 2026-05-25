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

        return try await draftAgentReply(
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
        fallbackReplyDraftResponse(for: event)
    }

    private func authoritativeReplyDraftResponse(
        event: AgentNeedsAttentionEvent,
        workerSnapshots: [String: TerminalWorkerSnapshot]
    ) -> AgentReplyDraftResponse? {
        guard let snapshot = workerSnapshots[event.terminalID],
              let request = snapshot.request else {
            return nil
        }

        let requestSuggestions = snapshot.requestSuggestions

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

    private func fallbackReplyDraftResponse(
        for event: AgentNeedsAttentionEvent
    ) -> AgentReplyDraftResponse {
        let message = event.deltaText.nilIfEmpty ?? fallbackReplyPrompt(for: event.interactionState)
        return .init(
            thought: "No authoritative worker reply draft is available.",
            suggestion: .askHuman(
                terminalID: event.terminalID,
                message: message,
                reason: "This client does not provide a dedicated reply-draft response, so Foreman cannot invent a worker-local reply.",
                confidence: 1.0
            )
        )
    }

    private func fallbackReplyPrompt(
        for interactionState: AgentInteractionState
    ) -> String {
        switch interactionState {
        case .waitingApproval:
            return "The worker needs your approval."
        case .waitingChoice:
            return "The worker needs your choice."
        case .waitingText:
            return "The worker needs your direction."
        case .error:
            return "The worker encountered an error and needs your direction."
        case .unknown, .running, .completed:
            return "The worker needs your direction."
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
        let response = try await client.agentStep(
            narrationContext: narrationContext,
            terminals: terminals,
            understandings: understandings,
            workerSnapshots: workerSnapshots,
            overview: overview,
            lastOutcome: lastOutcome
        )

        return sanitize(response, for: narrationContext.stepPolicy)
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

    private func sanitize(
        _ response: AgentStepResponse,
        for stepPolicy: ForemanStepPolicy
    ) -> AgentStepResponse {
        guard stepPolicy == .guidanceOnly else {
            return response
        }

        guard case .sendCommand(_, let command, let reason) = response.action else {
            return response
        }

        let message = reason.nilIfEmpty ?? command.nilIfEmpty ?? "Give project-level guidance before sending a terminal reply."
        return AgentStepResponse(
            thought: response.thought,
            action: .respond(message: message)
        )
    }
}
