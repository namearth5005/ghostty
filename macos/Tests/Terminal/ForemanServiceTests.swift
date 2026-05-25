import Foundation
import Testing
@testable import Ghostty

@MainActor
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
        let narrationContext = await MainActor.run { conversation.narrationContext }

        let response = try await client.agentStep(
            narrationContext: narrationContext,
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

    @Test
    func openAIClientAgentStepUsesExplicitNarrationAndObservedContext() async throws {
        let transport = RecordingResponsesTransport(
            payload: """
            {"thought":"Using runtime state.","action":{"type":"respond","message":"term-1 failed because `hfind` is not installed."}}
            """
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
        let runtimeState = await MainActor.run { ForemanRuntimeState() }
        let conversation = await MainActor.run { ForemanConversation(runtimeState: runtimeState) }
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .failed,
            shortExplanation: "The command failed because `hfind` is not installed.",
            lastMeaningfulEvent: "zsh: command not found: hfind",
            importantDetails: ["The typed command was `hfind . -print`."],
            suggestedNextActions: []
        )

        await MainActor.run {
            runtimeState.updateTerminalContext(
                overview: .init(
                    summary: "term-1 failed because `hfind` is not installed.",
                    changedTerminalIDs: ["term-1"],
                    primaryTerminalID: "term-1"
                ),
                understandings: [understanding]
            )
        }
        let narrationContext = await MainActor.run { conversation.narrationContext }
        let observedState = await MainActor.run {
            (
                runtimeState.lastUnderstandings,
                runtimeState.lastWorkerSnapshots,
                runtimeState.lastOverview
            )
        }

        _ = try await client.agentStep(
            narrationContext: narrationContext,
            terminals: sampleSnapshots(),
            understandings: observedState.0,
            workerSnapshots: observedState.1,
            overview: try #require(observedState.2),
            lastOutcome: nil
        )

        let request = try #require(await transport.lastRequest)
        #expect(request.instructions.contains("Do not infer or replace the user's broader goal from terminal history alone."))
        #expect(request.instructions.contains("If a structured worker snapshot does not include a sendable payload, ask the user or give project-level guidance instead of drafting a worker-local reply."))
        #expect(request.instructions.contains("infer the user's goal") == false)
        let prompt = request.input[0].content[0].text
        #expect(prompt.contains("Structured terminal overview:"))
        #expect(prompt.contains("term-1 failed because `hfind` is not installed."))
        #expect(prompt.contains("\"terminalID\":\"term-1\""))
    }

    @Test
    func openAIPromptIncludesHiddenReactiveContext() async throws {
        let transport = RecordingResponsesTransport(
            payload: """
            {"thought":"Using hidden context.","action":{"type":"respond","message":"Kimi is waiting for input."}}
            """
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        await MainActor.run {
            conversation.start(goal: "watch Kimi", mode: .interactive)
            conversation.addHiddenContext("Kimi in terminal term-1 is waiting for text input.")
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
        let prompt = request.input[0].content[0].text
        #expect(prompt.contains("Hidden reactive context:"))
        #expect(prompt.contains("Kimi in terminal term-1 is waiting for text input."))
    }

    @Test
    func openAIPromptPromotesReactiveContextWhenNoUserGoalExists() async throws {
        let transport = RecordingResponsesTransport(
            payload: """
            {"thought":"Drafting a reply for Kimi.","action":{"type":"send_command","terminal_id":"term-1","command":"Read the README and summarize the project.","reason":"Kimi asked what to do next."}}
            """
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
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
        let prompt = request.input[0].content[0].text
        #expect(prompt.contains("Active turn:"))
        #expect(prompt.contains("Kimi in terminal term-1 is waiting for text input."))
        #expect(prompt.contains("If Active turn is a reactive terminal event, handle that event as the current task."))
    }

    @Test
    func openAIClientDraftAgentReplyUsesDedicatedSchema() async throws {
        let transport = RecordingResponsesTransport(
            payload: try makeReplyDraftResponse(
                thought: "Need human direction.",
                suggestion: .askHuman(
                    terminalID: "term-1",
                    message: "What should Kimi do next?",
                    reason: "No active Foreman goal exists.",
                    confidence: 0.8
                )
            )
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
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
        let prompt = request.input[0].content[0].text
        #expect(prompt.contains("reply_to_agent|ask_human|no_action"))
        #expect(request.instructions.contains("provides no suggested payload, use ask_human instead of inventing one"))
        #expect(prompt.contains("Current waiting-text event:"))
        #expect(prompt.contains("What would you like me to do here?"))
        #expect(response.suggestion == .askHuman(
            terminalID: "term-1",
            message: "What should Kimi do next?",
            reason: "No active Foreman goal exists.",
            confidence: 0.8
        ))
    }

    @Test
    func serviceForwardsStructuredUnderstandingsToClient() async throws {
        let client = RecordingForemanClient()
        let service = ForemanService(client: client)
        let conversation = await MainActor.run { ForemanConversation() }
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .failed,
            shortExplanation: "The terminal failed.",
            lastMeaningfulEvent: "error: module not found",
            importantDetails: ["module not found"],
            suggestedNextActions: []
        )
        let overview = TerminalOverview(
            summary: "term-1 failed",
            changedTerminalIDs: ["term-1"],
            primaryTerminalID: "term-1"
        )
        let narrationContext = await MainActor.run { conversation.narrationContext }

        _ = try await service.agentStep(
            narrationContext: narrationContext,
            terminals: sampleSnapshots(),
            understandings: [understanding],
            workerSnapshots: [:],
            overview: overview,
            lastOutcome: nil
        )

        let recorded = await client.lastUnderstandings
        #expect(recorded == [understanding])
    }

    @Test
    func serviceForwardsAuthoritativeWorkerSnapshotsToClient() async throws {
        let client = RecordingForemanClient()
        let service = ForemanService(client: client)
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

        _ = try await service.agentStep(
            narrationContext: narrationContext,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: ["term-1": workerSnapshot],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        let recorded = await client.lastWorkerSnapshots
        #expect(recorded == ["term-1": workerSnapshot])
    }

    @Test
    func serviceUsesProtocolFallbackForLegacyClients() async throws {
        let client = LegacyRecordingForemanClient()
        let service = ForemanService(client: client)
        let conversation = await MainActor.run { ForemanConversation() }
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .failed,
            shortExplanation: "The terminal failed.",
            lastMeaningfulEvent: "error: module not found",
            importantDetails: ["module not found"],
            suggestedNextActions: []
        )
        let overview = TerminalOverview(
            summary: "term-1 failed",
            changedTerminalIDs: ["term-1"],
            primaryTerminalID: "term-1"
        )
        let narrationContext = await MainActor.run { conversation.narrationContext }

        _ = try await service.agentStep(
            narrationContext: narrationContext,
            terminals: sampleSnapshots(),
            understandings: [understanding],
            workerSnapshots: [:],
            overview: overview,
            lastOutcome: nil
        )

        let forwarded = await client.didUseLegacyPath()
        #expect(forwarded == true)
    }

    @Test
    func serviceUsesReplyDraftProtocolFallbackForLegacyClients() async throws {
        let client = LegacyReplyDraftClient()
        let service = ForemanService(client: client)
        let conversation = await MainActor.run { ForemanConversation() }
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            deltaText: "What should I work on next?",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let narrationContext = await MainActor.run { conversation.narrationContext }

        let response = try await service.draftAgentReply(
            narrationContext: narrationContext,
            event: event,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: [:],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        let forwarded = await client.didUseLegacyDraftPath()
        #expect(forwarded == true)
        #expect(
            response == AgentReplyDraftResponse(
                thought: "Use the dedicated reply-draft path.",
                suggestion: .askHuman(
                    terminalID: "term-1",
                    message: "What should the worker do next?",
                    reason: "The legacy reply-draft path handled this request.",
                    confidence: 0.7
                )
            )
        )
    }

    @Test
    func serviceGenericReplyDraftFallbackUsesAuthoritativeWorkerSnapshotBeforeLegacyPlannerStep() async throws {
        let client = LegacyAgentStepOnlyClient()
        let service = ForemanService(client: client)
        let conversation = await MainActor.run { ForemanConversation() }
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            deltaText: "Should I preserve the API?",
            timestamp: Date(timeIntervalSince1970: 1)
        )
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
            suggestions: []
        )
        let narrationContext = await MainActor.run { conversation.narrationContext }

        let response = try await service.draftAgentReply(
            narrationContext: narrationContext,
            event: event,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: ["term-1": workerSnapshot],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        #expect(await client.genericStepCallCount() == 0)
        #expect(response.thought == "Codex is waiting for a reply.")
        #expect(
            response.suggestion == .askHuman(
                terminalID: "term-1",
                message: "Should I preserve the API?",
                reason: "The structured worker snapshot needs direction and did not provide a suggested reply.",
                confidence: 1.0
            )
        )
    }

    @Test
    func serviceGenericReplyDraftFallbackEscalatesWithoutWorkerSnapshot() async throws {
        let client = LegacyAgentStepOnlyClient()
        let service = ForemanService(client: client)
        let conversation = await MainActor.run { ForemanConversation() }
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            deltaText: "What should I work on next?",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let narrationContext = await MainActor.run { conversation.narrationContext }

        let response = try await service.draftAgentReply(
            narrationContext: narrationContext,
            event: event,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: [:],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        #expect(await client.genericStepCallCount() == 0)
        #expect(response.thought == "No authoritative worker reply draft is available.")
        #expect(
            response.suggestion == .askHuman(
                terminalID: "term-1",
                message: "What should I work on next?",
                reason: "This client does not provide a dedicated reply-draft response, so Foreman cannot invent a worker-local reply.",
                confidence: 1.0
            )
        )
    }

    @Test
    func serviceGenericReplyDraftFallbackIgnoresSuggestionsFromOlderRequests() async throws {
        let client = LegacyAgentStepOnlyClient()
        let service = ForemanService(client: client)
        let conversation = await MainActor.run { ForemanConversation() }
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            deltaText: "Should I preserve the API?",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let workerSnapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-7",
            revision: 8,
            observedAt: Date(timeIntervalSince1970: 1_748_444_445),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for a reply.",
                details: ["The old recommendation should not be used."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-current",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "stale",
                    kind: .reply,
                    title: "Follow the old plan",
                    payload: .text("Use the previous migration path."),
                    rationale: "This suggestion belongs to the old request.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-old"
                ),
            ]
        )
        let narrationContext = await MainActor.run { conversation.narrationContext }

        let response = try await service.draftAgentReply(
            narrationContext: narrationContext,
            event: event,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: ["term-1": workerSnapshot],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        #expect(await client.genericStepCallCount() == 0)
        #expect(response.thought == "Codex is waiting for a reply.")
        #expect(
            response.suggestion == .askHuman(
                terminalID: "term-1",
                message: "Should I preserve the API?",
                reason: "The structured worker snapshot needs direction and did not provide a suggested reply.",
                confidence: 1.0
            )
        )
    }

    @Test
    func openAIPromptIncludesWorkerSnapshotsAndNarratorConstraint() async throws {
        let transport = RecordingResponsesTransport(
            payload: """
            {"thought":"Use the worker suggestion.","action":{"type":"respond","message":"Codex already recommended preserving the API."}}
            """
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
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
        let prompt = request.input[0].content[0].text
        #expect(request.instructions.contains("do not invent a competing suggestion"))
        #expect(request.instructions.contains("If a structured worker snapshot is waiting for direction but provides no suggested payload, do not invent one"))
        #expect(prompt.contains("Structured worker snapshots:"))
        #expect(prompt.contains("\"preserve-api\""))
        #expect(prompt.contains("\"worker_goal\":\"stabilize the API\""))
    }

    @Test
    func serviceForwardsNarrationContextToClient() async throws {
        let client = RecordingForemanClient()
        let service = ForemanService(client: client)
        let narrationContext = ForemanNarrationContext(
            goal: "watch term-1",
            mode: .interactive,
            iterationCount: 2,
            messages: [
                ConversationMessage(role: .user, content: "watch term-1"),
                ConversationMessage(role: .agent, content: "Kimi is waiting.")
            ],
            hiddenContext: ["Kimi in terminal term-1 is waiting for text input."]
        )

        _ = try await service.agentStep(
            narrationContext: narrationContext,
            terminals: sampleSnapshots(),
            understandings: [],
            workerSnapshots: [:],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        let recorded = await client.lastNarrationContext
        #expect(recorded == narrationContext)
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

private actor RecordingForemanClient: ForemanLLMClient {
    private(set) var lastNarrationContext: ForemanNarrationContext?
    private(set) var lastUnderstandings: [TerminalUnderstanding] = []
    private(set) var lastWorkerSnapshots: [String: TerminalWorkerSnapshot] = [:]

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw RecordingForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw RecordingForemanClientError.unexpectedCall
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        lastNarrationContext = narrationContext
        lastUnderstandings = understandings
        lastWorkerSnapshots = workerSnapshots
        return try makeStepResponse(
            thought: "Answering from structured context.",
            action: .respond(message: overview.summary)
        )
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        throw RecordingForemanClientError.unexpectedCall
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
        lastNarrationContext = narrationContext
        lastUnderstandings = understandings
        lastWorkerSnapshots = workerSnapshots
        return AgentReplyDraftResponse(
            thought: "Asking for human direction.",
            suggestion: .askHuman(
                terminalID: event.terminalID,
                message: "What should the agent do next?",
                reason: overview.summary,
                confidence: 1.0
            )
        )
    }
}

private actor LegacyRecordingForemanClient: ForemanLLMClient {
    private var legacyCallCount = 0

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw RecordingForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw RecordingForemanClientError.unexpectedCall
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        legacyCallCount += 1
        return try makeStepResponse(
            thought: "Falling back to the legacy path.",
            action: .respond(message: "legacy")
        )
    }

    func didUseLegacyPath() -> Bool {
        legacyCallCount == 1
    }
}

private actor LegacyReplyDraftClient: ForemanLLMClient {
    private var legacyDraftCallCount = 0

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw RecordingForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw RecordingForemanClientError.unexpectedCall
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        throw RecordingForemanClientError.unexpectedCall
    }

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse {
        legacyDraftCallCount += 1
        return AgentReplyDraftResponse(
            thought: "Use the dedicated reply-draft path.",
            suggestion: .askHuman(
                terminalID: event.terminalID,
                message: "What should the worker do next?",
                reason: "The legacy reply-draft path handled this request.",
                confidence: 0.7
            )
        )
    }

    func didUseLegacyDraftPath() -> Bool {
        legacyDraftCallCount == 1
    }
}

private actor LegacyAgentStepOnlyClient: ForemanLLMClient {
    private var genericStepCalls = 0

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw RecordingForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw RecordingForemanClientError.unexpectedCall
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        genericStepCalls += 1
        return try makeStepResponse(
            thought: "Legacy planner should not be used here.",
            action: .sendCommand(
                terminalID: "term-1",
                command: "legacy fallback",
                reason: "This should not be used for authoritative worker snapshots."
            )
        )
    }

    func genericStepCallCount() -> Int {
        genericStepCalls
    }
}

private actor RecordingResponsesTransport: OpenAIResponsesTransport {
    let payload: String
    private(set) var lastRequest: OpenAIClient.Request?

    init(payload: String) {
        self.payload = payload
    }

    func send(_ request: OpenAIClient.Request, apiKey: String) async throws -> String {
        lastRequest = request
        return payload
    }
}

private enum RecordingForemanClientError: Error {
    case unexpectedCall
}

private func makeStepResponse(thought: String, action: AgentAction) throws -> AgentStepResponse {
    struct StepEnvelope: Encodable {
        let thought: String
        let action: AgentAction
    }

    let data = try JSONEncoder().encode(StepEnvelope(thought: thought, action: action))
    return try JSONDecoder().decode(AgentStepResponse.self, from: data)
}

private func makeReplyDraftResponse(
    thought: String,
    suggestion: AgentReplyDraftSuggestion
) throws -> String {
    struct DraftEnvelope: Encodable {
        let thought: String
        let suggestion: AgentReplyDraftSuggestion
    }

    let data = try JSONEncoder().encode(DraftEnvelope(thought: thought, suggestion: suggestion))
    guard let string = String(data: data, encoding: .utf8) else {
        fatalError("Unable to encode AgentReplyDraftResponse fixture.")
    }
    return string
}
