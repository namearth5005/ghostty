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

    @Test
    func openAIClientAgentStepExtractsWrappedJSON() async throws {
        let transport = MockResponsesTransport(
            payload: """
            Here is the next action.
            {"thought":"The previous command was mistyped.","action":{"type":"send_command","terminal_id":"term-1","command":"find . -print","reason":"Retry with the correct command."}}
            """
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        await MainActor.run {
            conversation.start(goal: "list all files", mode: .interactive)
        }

        let response = try await client.agentStep(
            conversation: conversation,
            terminals: [
                .makePreview(
                    terminalID: "term-1",
                    windowID: "win-1",
                    tabID: "tab-1",
                    title: "shell",
                    cwd: "/tmp/project",
                    isFocused: true,
                    visibleText: "$ ",
                    recentScrollbackLines: [],
                    lastInputPreview: "hfind . -print"
                ),
            ],
            lastOutcome: nil
        )

        #expect(response.thought == "The previous command was mistyped.")
        #expect(response.action == .sendCommand(
            terminalID: "term-1",
            command: "find . -print",
            reason: "Retry with the correct command."
        ))
    }
}
