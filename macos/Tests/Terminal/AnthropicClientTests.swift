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
        let narrationContext = await MainActor.run { conversation.narrationContext }

        let response = try await client.agentStep(
            narrationContext: narrationContext,
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
            conversation.addHiddenContext("Kimi in terminal term-1 is waiting for text input.")
        }
        let narrationContext = await MainActor.run { conversation.narrationContext }

        _ = try await client.agentStep(
            narrationContext: narrationContext,
            terminals: sampleSnapshots(),
            understandings: understandings,
            workerSnapshots: [:],
            overview: overview,
            lastOutcome: Optional<TerminalOutcomeReport>.none
        )

        let request = try #require(await transport.lastRequest)
        #expect(request.system.contains("Use structured terminal understanding as your primary context"))
        let prompt = request.messages[0].content
        #expect(prompt.contains("Structured terminal overview:"))
        #expect(prompt.contains("Hidden reactive context:"))
        #expect(prompt.contains("Kimi in terminal term-1 is waiting for text input."))
        #expect(prompt.contains("term-1 failed because `hfind` is not installed."))
        #expect(prompt.contains("\"terminalID\":\"term-1\""))
        #expect(prompt.contains("\"command\":\"find . -print\""))
        #expect(prompt.contains("\"isRecommended\":true"))
    }

    @Test
    func anthropicPromptPromotesReactiveContextWhenNoUserGoalExists() async throws {
        let transport = RecordingAnthropicTransport(
            payload: """
            {"thought":"Drafting a reply for Kimi.","action":{"type":"send_command","terminal_id":"term-1","command":"Read the README and summarize the project.","reason":"Kimi asked what to do next."}}
            """
        )
        let client = AnthropicClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        await MainActor.run {
            conversation.addHiddenContext(
                "Kimi in terminal term-1 is waiting for text input.\n\nRecent output:\nWhat would you like me to do here?"
            )
        }
        let narrationContext = await MainActor.run { conversation.narrationContext }

        _ = try await client.agentStep(
            narrationContext: narrationContext,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: [:],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        let request = try #require(await transport.lastRequest)
        let prompt = request.messages[0].content
        #expect(prompt.contains("Active turn:"))
        #expect(prompt.contains("Kimi in terminal term-1 is waiting for text input."))
        #expect(prompt.contains("If Active turn is a reactive terminal event, handle that event as the current task."))
    }

    @Test
    func anthropicDraftAgentReplyUsesDedicatedSchema() async throws {
        let transport = RecordingAnthropicTransport(
            payload: """
            {"thought":"Send a concrete reply.","suggestion":{"type":"reply_to_agent","terminal_id":"term-1","message":"Read README.md and summarize the project.","reason":"Kimi asked what to do next.","confidence":0.9}}
            """
        )
        let client = AnthropicClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            deltaText: "What would you like me to do here?",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let narrationContext = await MainActor.run { conversation.narrationContext }

        let response = try await client.draftAgentReply(
            narrationContext: narrationContext,
            event: event,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: [:],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        let request = try #require(await transport.lastRequest)
        #expect(request.system.contains("reply_to_agent, ask_human, or no_action"))
        let prompt = request.messages[0].content
        #expect(prompt.contains("Current waiting-text event:"))
        #expect(prompt.contains("What would you like me to do here?"))
        #expect(response.suggestion == .replyToAgent(
            terminalID: "term-1",
            message: "Read README.md and summarize the project.",
            reason: "Kimi asked what to do next.",
            confidence: 0.9
        ))
    }

    @Test
    func anthropicPromptIncludesWorkerSnapshotsAndNarratorConstraint() async throws {
        let transport = RecordingAnthropicTransport(
            payload: """
            {"thought":"Use the worker suggestion.","action":{"type":"respond","message":"Codex already recommended preserving the API."}}
            """
        )
        let client = AnthropicClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        let workerSnapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-1",
            revision: 7,
            observedAt: Date(timeIntervalSince1970: 1_748_444_444),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for a reply.",
                details: ["Asked whether the API should stay stable."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-7",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "preserve-api",
                    kind: .reply,
                    title: "Preserve the API",
                    payload: .text("Preserve the current API and adapt the internals."),
                    rationale: "Lowest migration risk.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-7"
                ),
            ]
        )
        let narrationContext = await MainActor.run { conversation.narrationContext }

        _ = try await client.agentStep(
            narrationContext: narrationContext,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: ["term-1": workerSnapshot],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        let request = try #require(await transport.lastRequest)
        #expect(request.system.contains("do not invent a competing suggestion"))
        let prompt = request.messages[0].content
        #expect(prompt.contains("Structured worker snapshots:"))
        #expect(prompt.contains("\"preserve-api\""))
        #expect(prompt.contains("\"worker_goal\":\"stabilize the API\""))
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
