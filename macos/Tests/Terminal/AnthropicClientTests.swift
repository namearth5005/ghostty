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

    @Test
    func anthropicPromptIncludesStructuredOverviewAndSuggestions() async throws {
        let transport = RecordingAnthropicTransport(
            payload: """
            {"thought":"Answering from structured context.","action":{"type":"respond","message":"The terminal failed because `hfind` is not installed."}}
            """
        )
        let client = AnthropicClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        let overview = TerminalOverview(
            summary: "term-1 failed because `hfind` is not installed.",
            changedTerminalIDs: ["term-1"],
            primaryTerminalID: "term-1"
        )
        let understandings = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .failed,
                shortExplanation: "The command failed because `hfind` is not installed.",
                lastMeaningfulEvent: "zsh: command not found: hfind",
                importantDetails: ["The typed command was `hfind . -print`."],
                suggestedNextActions: [
                    TerminalSuggestedAction(
                        title: "Retry with find",
                        command: "find . -print",
                        reason: "This is the likely intended command.",
                        isRecommended: true
                    ),
                    TerminalSuggestedAction(
                        title: "Use fd instead",
                        command: "fd .",
                        reason: "Use `fd` if that tool is installed and preferred.",
                        isRecommended: false
                    ),
                ]
            ),
        ]

        await MainActor.run {
            conversation.start(goal: "list files", mode: .interactive)
        }

        _ = try await client.agentStep(
            conversation: conversation,
            terminals: sampleSnapshots(),
            understandings: understandings,
            overview: overview,
            lastOutcome: Optional<TerminalOutcomeReport>.none
        )

        let request = try #require(await transport.lastRequest)
        #expect(request.system.contains("Use structured terminal understanding as your primary context"))
        let prompt = request.messages[0].content
        #expect(prompt.contains("Structured terminal overview:"))
        #expect(prompt.contains("term-1 failed because `hfind` is not installed."))
        #expect(prompt.contains("\"terminalID\":\"term-1\""))
        #expect(prompt.contains("\"command\":\"find . -print\""))
        #expect(prompt.contains("\"isRecommended\":true"))
    }
}

@MainActor
private func sampleSnapshots() -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
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
    ]
}

private actor RecordingAnthropicTransport: AnthropicMessagesTransport {
    let payload: String
    private(set) var lastRequest: AnthropicClient.Request?

    init(payload: String) {
        self.payload = payload
    }

    func send(_ request: AnthropicClient.Request, apiKey: String) async throws -> String {
        lastRequest = request
        return payload
    }
}
