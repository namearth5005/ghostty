import Testing
@testable import Ghostty

struct AnthropicClientTests {
    @Test
    func plannerBuildsDraftsFromAnthropicMessagesResponse() async throws {
        let transport = MockAnthropicTransport(
            payload: """
            {"plan_summary":"One terminal needs input.","drafts":[{"terminal_id":"term-1","reason":"Blocked test run.","message":"Rerun the failing auth test and report the result."}]}
            """
        )
        let client = AnthropicClient(apiKey: "test-key", transport: transport)

        let result = try await client.planDispatch(
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
        #expect(result.planSummary == "One terminal needs input.")
    }

    @Test
    func anthropicClientAgentStepAcceptsReasonStuckAlias() async throws {
        let transport = MockAnthropicTransport(
            payload: """
            {"thought":"I cannot continue without a valid shell command.","action":{"type":"declare_stuck","reason_stuck":"The previous command is invalid and there is no safe fallback."}}
            """
        )
        let client = AnthropicClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        await MainActor.run {
            conversation.start(goal: "list all files", mode: .interactive)
        }

        let response = try await client.agentStep(
            conversation: conversation,
            terminals: [],
            lastOutcome: nil
        )

        #expect(response.action == .declareStuck(reason: "The previous command is invalid and there is no safe fallback."))
    }
}
