import Foundation
import Testing
@testable import Ghostty

struct ForemanServiceTests {
    @Test
    func plannerBuildsDraftsFromSummaries() async throws {
        let transport = MockResponsesTransport(
            payload: """
            {"plan_summary":"Two terminals need input.","drafts":[{"terminal_id":"term-1","reason":"Blocked test run.","message":"Rerun the failing auth test and explain the failure briefly."}]}
            """
        )
        let service = ForemanService(client: OpenAIClient(apiKey: "test-key", transport: transport))

        let result = try await service.planDispatch(
            instruction: "Ask blocked terminals to rerun the failing tests.",
            summaries: [
                .init(
                    terminalID: "term-1",
                    summary: "Blocked on auth test",
                    state: "blocked",
                    confidence: 0.9,
                    needsUserAttention: true,
                    suggestedNextStep: "rerun auth test"
                )
            ]
        )

        #expect(result.drafts.count == 1)
        #expect(result.drafts[0].terminalID == "term-1")
        #expect(result.planSummary == "Two terminals need input.")
    }
}
