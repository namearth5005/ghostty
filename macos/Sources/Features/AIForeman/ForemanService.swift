import Foundation

protocol ForemanLLMClient: Sendable {
    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary
    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan
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
}
