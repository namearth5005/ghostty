import Foundation

protocol ForemanLLMClient: Sendable {
    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary
    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan
    func agentStep(conversation: ForemanConversation, terminals: [TerminalSnapshot], lastOutcome: TerminalOutcomeReport?) async throws -> AgentStepResponse
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

    func agentStep(conversation: ForemanConversation, terminals: [TerminalSnapshot], lastOutcome: TerminalOutcomeReport?) async throws -> AgentStepResponse {
        try await client.agentStep(conversation: conversation, terminals: terminals, lastOutcome: lastOutcome)
    }
}
