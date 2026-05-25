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
