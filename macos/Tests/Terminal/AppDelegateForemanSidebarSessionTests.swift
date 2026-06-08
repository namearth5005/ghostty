import AppKit
import Testing
@testable import Ghostty

@Suite(.serialized)
struct AppDelegateForemanSidebarSessionTests {
    @MainActor
    @Test
    func sendChatMessageUsesTheStoreOwnedSession() {
        let appDelegate = try! #require(NSApp.delegate as? AppDelegate)
        let firstStore = ForemanSidebarStore(conversation: ForemanConversation())
        let secondStore = ForemanSidebarStore(conversation: ForemanConversation())
        let firstSpy = SidebarSessionSpy()
        let secondSpy = SidebarSessionSpy()

        firstStore.attachSidebarSession(firstSpy)
        secondStore.attachSidebarSession(secondSpy)

        appDelegate.sendChatMessage("first sidebar", store: firstStore)
        appDelegate.sendChatMessage("second sidebar", store: secondStore)

        #expect(firstSpy.recordedMessages == ["first sidebar"])
        #expect(secondSpy.recordedMessages == ["second sidebar"])
    }

    @MainActor
    @Test
    func startingSecondSidebarDoesNotStopFirstSidebarSession() {
        let appDelegate = try! #require(NSApp.delegate as? AppDelegate)
        let firstStore = ForemanSidebarStore(conversation: ForemanConversation())
        let secondStore = ForemanSidebarStore(conversation: ForemanConversation())
        let firstSpy = SidebarSessionSpy()
        let secondSpy = SidebarSessionSpy()

        firstStore.attachSidebarSession(firstSpy)
        secondStore.attachSidebarSession(secondSpy)

        appDelegate.startForemanAgent(goal: "first goal", mode: .interactive, store: firstStore)
        appDelegate.startForemanAgent(goal: "second goal", mode: .interactive, store: secondStore)

        #expect(firstSpy.stopCallCount == 0)
        #expect(firstSpy.startedGoals == ["first goal"])
        #expect(secondSpy.startedGoals == ["second goal"])
    }

    @MainActor
    @Test
    func dispatchingGuideForemanIntentUsesTheStoreOwnedSession() {
        let appDelegate = try! #require(NSApp.delegate as? AppDelegate)
        let store = ForemanSidebarStore(conversation: ForemanConversation())
        let spy = SidebarSessionSpy()

        store.attachSidebarSession(spy)

        appDelegate.dispatchForemanSidebarIntent(.guideForeman("Summarize the active options."), store: store)

        #expect(spy.recordedMessages == ["Summarize the active options."])
    }

    @MainActor
    @Test
    func dispatchingTargetedGuideForemanIntentPreservesTerminalPreference() {
        let appDelegate = try! #require(NSApp.delegate as? AppDelegate)
        let store = ForemanSidebarStore(conversation: ForemanConversation())
        let spy = SidebarSessionSpy()

        store.attachSidebarSession(spy)
        store.applySnapshots([
            TerminalSnapshot.makePreview(
                terminalID: "term-2",
                windowID: "win-1",
                tabID: "tab-2",
                title: "Codex",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "What should I do here?",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex"
            ),
        ], understandingsByTerminalID: [
            "term-2": makeWorkerUnderstanding(
                terminalID: "term-2",
                shortExplanation: "Codex needs direction.",
                lastMeaningfulEvent: "What should I do here?",
                agentIdentity: .codex,
                interactionState: .waitingText,
                workerSnapshot: makeWorkerSnapshot(
                    terminalID: "term-2",
                    workerSessionID: "codex-session-52",
                    revision: 52,
                    workerGoal: "choose a migration path",
                    identity: .codex,
                    attention: .replyRequired,
                    summary: "Codex needs direction.",
                    details: [],
                    request: .init(
                        id: "req-52",
                        kind: .reply,
                        prompt: "What should I do here?",
                        options: []
                    ),
                    suggestions: []
                ),
                suggestedNextActions: []
            ),
        ])

        appDelegate.dispatchForemanSidebarIntent(
            .guideForemanForTerminal(
                terminalID: "term-2",
                fingerprint: "codex-session-52|52|req-52",
                message: "What should I do here?"
            ),
            store: store
        )

        #expect(spy.recordedMessages == ["What should I do here?"])
        #expect(spy.recordedPreferredTerminalIDs == ["term-2"])
        #expect(spy.recordedBypassAuthoritativeWorker == [true])
    }

    @MainActor
    @Test
    func reactiveAutoDispatchInitialDecisionUsesUnifiedSidebarIntent() {
        let appDelegate = try! #require(NSApp.delegate as? AppDelegate)
        let store = ForemanSidebarStore(conversation: ForemanConversation())
        let attention = PendingAgentAttention(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            fingerprint: "fp-1",
            title: "Suggested reply",
            description: "Should I preserve the API?",
            detail: nil,
            actions: [
                .init(
                    id: "preserve-api",
                    title: "Preserve the API",
                    payload: "Preserve the current API and adapt the internals.",
                    style: .primary
                ),
            ]
        )
        let action = try! #require(attention.actions.first)

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        let handled = appDelegate.handleReactiveInitialDecision(
            .autoDispatchPendingAttention(attention, action),
            store: store
        )

        #expect(handled)
        #expect(
            dispatchedIntent ==
            .sendPendingAttentionAction(
                terminalID: "term-1",
                fingerprint: "fp-1",
                payload: "Preserve the current API and adapt the internals."
            )
        )
        #expect(store.pendingAttentionByTerminalID["term-1"] == attention)
    }

    @MainActor
    @Test
    func reactiveShowPendingAttentionDecisionOnlyStoresAttention() {
        let appDelegate = try! #require(NSApp.delegate as? AppDelegate)
        let store = ForemanSidebarStore(conversation: ForemanConversation())
        let attention = PendingAgentAttention(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            fingerprint: "fp-1",
            title: "Suggested reply",
            description: "Should I preserve the API?",
            detail: nil,
            actions: [
                .init(
                    id: "preserve-api",
                    title: "Preserve the API",
                    payload: "Preserve the current API and adapt the internals.",
                    style: .primary
                ),
            ]
        )

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        let handled = appDelegate.handleReactiveInitialDecision(
            .showPendingAttention(attention),
            store: store
        )

        #expect(handled)
        #expect(dispatchedIntent == nil)
        #expect(store.pendingAttentionByTerminalID["term-1"] == attention)
    }

    @MainActor
    @Test
    func sidebarSessionPreservesModeAcrossImplicitRestart() async throws {
        let conversation = ForemanConversation()
        let client = SessionTestClient()
        let service = ForemanService(client: client)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")
        let session = ForemanSidebarSession(
            conversation: conversation,
            foremanService: service,
            goalRuntime: ForemanProjectGoalRuntime(memoryStore: ForemanMemoryStore(dbPath: dbURL)),
            preferredTerminalID: { "term-1" },
            captureSnapshots: { [] },
            captureObservedContext: { nil },
            onSendCommand: { _, _ in true }
        )
        defer { try? fileManager.removeItem(at: root) }

        session.start(goal: "first goal", mode: AgentMode.autonomous)
        try await waitForSessionMode(conversation: conversation, expectedMode: AgentMode.autonomous)

        session.stop()
        try await waitForSessionStopped(conversation: conversation)

        session.receiveUserMessage("continue")
        try await waitForSessionMode(conversation: conversation, expectedMode: AgentMode.autonomous)
    }

    @MainActor
    @Test
    func sidebarSessionAppliesExplicitPreferredTerminalOnUserMessage() async throws {
        let conversation = ForemanConversation()
        let client = SessionTestClient()
        let service = ForemanService(client: client)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")
        var selectedTerminalID = "term-1"
        let observedContext = makeAuthoritativeNeedsDirectionContext([
            "term-1": "What should I do in terminal one?",
            "term-2": "What should I do in terminal two?",
        ])
        let session = ForemanSidebarSession(
            conversation: conversation,
            foremanService: service,
            goalRuntime: ForemanProjectGoalRuntime(memoryStore: ForemanMemoryStore(dbPath: dbURL)),
            preferredTerminalID: { selectedTerminalID },
            captureSnapshots: { observedContext.terminals },
            captureObservedContext: { observedContext },
            onSendCommand: { _, _ in true }
        )
        defer { try? fileManager.removeItem(at: root) }

        session.receiveUserMessage("start")
        try await waitForAgentMessage(
            conversation: conversation,
            content: "Needs direction\n\nWhat should I do in terminal one?",
            terminalID: "term-1"
        )

        selectedTerminalID = "term-2"
        session.receiveUserMessage("continue", preferredTerminalID: "term-2")
        try await waitForAgentMessage(
            conversation: conversation,
            content: "Needs direction\n\nWhat should I do in terminal two?",
            terminalID: "term-2"
        )
    }

    @MainActor
    @Test
    func sidebarSessionTargetedGuidanceBypassesAuthoritativePause() async throws {
        let conversation = ForemanConversation()
        let client = GuidanceSessionClient()
        let service = ForemanService(client: client)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")
        let observedContext = makeAuthoritativeNeedsDirectionContext([
            "term-1": "What should I do here?",
        ])
        let session = ForemanSidebarSession(
            conversation: conversation,
            foremanService: service,
            goalRuntime: ForemanProjectGoalRuntime(memoryStore: ForemanMemoryStore(dbPath: dbURL)),
            preferredTerminalID: { "term-1" },
            captureSnapshots: { observedContext.terminals },
            captureObservedContext: { observedContext },
            onSendCommand: { _, _ in true }
        )
        defer { try? fileManager.removeItem(at: root) }

        session.receiveUserMessage("start")
        try await waitForAgentMessage(
            conversation: conversation,
            content: "Needs direction\n\nWhat should I do here?",
            terminalID: "term-1"
        )

        session.receiveUserMessage(
            "Give me project-level guidance for this worker.",
            preferredTerminalID: "term-1",
            bypassAuthoritativeWorker: true
        )

        try await waitForAgentMessage(
            conversation: conversation,
            content: "Guide the worker to inspect the auth flow first."
        )

        let messages = conversation.messages
        #expect(messages.filter { $0.content == "Needs direction\n\nWhat should I do here?" }.count == 1)
        #expect(await client.agentStepCallCount() == 1)
    }

    @MainActor
    @Test
    func sidebarSessionTargetedGuidanceSanitizesCommandResponses() async throws {
        let conversation = ForemanConversation()
        let client = GuidanceCommandSessionClient()
        let service = ForemanService(client: client)
        let commandRecorder = SentCommandRecorder()
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")
        let observedContext = makeAuthoritativeNeedsDirectionContext([
            "term-1": "What should I do here?",
        ])
        let session = ForemanSidebarSession(
            conversation: conversation,
            foremanService: service,
            goalRuntime: ForemanProjectGoalRuntime(memoryStore: ForemanMemoryStore(dbPath: dbURL)),
            preferredTerminalID: { "term-1" },
            captureSnapshots: { observedContext.terminals },
            captureObservedContext: { observedContext },
            onSendCommand: { terminalID, command in
                commandRecorder.record(terminalID: terminalID, command: command)
                return true
            }
        )
        defer { try? fileManager.removeItem(at: root) }

        session.receiveUserMessage("start")
        try await waitForAgentMessage(
            conversation: conversation,
            content: "Needs direction\n\nWhat should I do here?",
            terminalID: "term-1"
        )

        session.receiveUserMessage(
            "Give me project-level guidance for this worker.",
            preferredTerminalID: "term-1",
            bypassAuthoritativeWorker: true
        )

        try await waitForAgentMessage(
            conversation: conversation,
            content: "Guide the worker to inspect the auth flow first."
        )

        let messages = conversation.messages
        #expect(messages.contains { $0.content == "Guide the worker to inspect the auth flow first." })
        #expect(messages.contains { $0.content.hasPrefix("▶️ Sent:") } == false)
        #expect(commandRecorder.commandCount() == 0)
        #expect(await client.agentStepCallCount() == 1)
    }
}

@MainActor
private final class SidebarSessionSpy: ForemanSidebarSessionControlling {
    private(set) var recordedMessages: [String] = []
    private(set) var recordedPreferredTerminalIDs: [String?] = []
    private(set) var recordedBypassAuthoritativeWorker: [Bool] = []
    private(set) var startedGoals: [String] = []
    private(set) var stopCallCount = 0
    private(set) var approvedCount = 0
    private(set) var skippedCount = 0
    private(set) var receivedOutcomes: [TerminalOutcomeReport] = []

    func start(goal: String, mode: AgentMode) {
        startedGoals.append(goal)
    }

    func receiveUserMessage(
        _ text: String,
        preferredTerminalID: String?,
        bypassAuthoritativeWorker: Bool
    ) {
        recordedMessages.append(text)
        recordedPreferredTerminalIDs.append(preferredTerminalID)
        recordedBypassAuthoritativeWorker.append(bypassAuthoritativeWorker)
    }

    func stop() {
        stopCallCount += 1
    }

    func approvePendingAction() {
        approvedCount += 1
    }

    func skipPendingAction() {
        skippedCount += 1
    }

    func receiveOutcome(_ report: TerminalOutcomeReport) {
        receivedOutcomes.append(report)
    }

    func draftPendingAttention(
        for event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext?
    ) async throws -> PendingAgentAttention? {
        nil
    }

    func react(
        to event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext?
    ) async {}
}

private actor SessionTestClient: ForemanLLMClient {
    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        .init(
            terminalID: snapshot.terminalID,
            summary: "idle",
            state: "idle",
            confidence: 1.0,
            needsUserAttention: false,
            suggestedNextStep: ""
        )
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        .init(planSummary: "", drafts: [])
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        AgentStepResponse(
            thought: "done",
            action: .declareComplete(summary: "done")
        )
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        AgentStepResponse(
            thought: "done",
            action: .declareComplete(summary: "done")
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
        .init(
            thought: "unused",
            suggestion: .noAction(reason: "unused", confidence: 1.0)
        )
    }
}

private actor GuidanceSessionClient: ForemanLLMClient {
    private var stepCalls = 0

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        .init(
            terminalID: snapshot.terminalID,
            summary: "idle",
            state: "idle",
            confidence: 1.0,
            needsUserAttention: false,
            suggestedNextStep: ""
        )
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        .init(planSummary: "", drafts: [])
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        stepCalls += 1
        return AgentStepResponse(
            thought: "Use project-level guidance.",
            action: .respond(message: "Guide the worker to inspect the auth flow first.")
        )
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        stepCalls += 1
        return AgentStepResponse(
            thought: "Use project-level guidance.",
            action: .respond(message: "Guide the worker to inspect the auth flow first.")
        )
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        stepCalls += 1
        return AgentStepResponse(
            thought: "Use project-level guidance.",
            action: .respond(message: "Guide the worker to inspect the auth flow first.")
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
        .init(
            thought: "No reply draft.",
            suggestion: .noAction(reason: "unused", confidence: 1.0)
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
        .init(
            thought: "No reply draft.",
            suggestion: .noAction(reason: "unused", confidence: 1.0)
        )
    }

    func agentStepCallCount() -> Int {
        stepCalls
    }
}

private actor GuidanceCommandSessionClient: ForemanLLMClient {
    private var stepCalls = 0

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        .init(
            terminalID: snapshot.terminalID,
            summary: "idle",
            state: "idle",
            confidence: 1.0,
            needsUserAttention: false,
            suggestedNextStep: ""
        )
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        .init(planSummary: "", drafts: [])
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        stepCalls += 1
        return AgentStepResponse(
            thought: "Use project-level guidance.",
            action: .sendCommand(
                terminalID: "term-1",
                command: "Inspect the auth flow first.",
                reason: "Guide the worker to inspect the auth flow first."
            )
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
            understandings: understandings,
            workerSnapshots: [:],
            overview: overview,
            lastOutcome: lastOutcome
        )
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        try await agentStep(
            narrationContext: narrationContext,
            terminals: terminals,
            understandings: [],
            workerSnapshots: [:],
            overview: .init(summary: "", changedTerminalIDs: [], primaryTerminalID: nil),
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
        .init(
            thought: "No reply draft.",
            suggestion: .noAction(reason: "unused", confidence: 1.0)
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
        .init(
            thought: "No reply draft.",
            suggestion: .noAction(reason: "unused", confidence: 1.0)
        )
    }

    func agentStepCallCount() -> Int {
        stepCalls
    }
}

private final class SentCommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [(terminalID: String, command: String)] = []

    func record(terminalID: String, command: String) {
        lock.lock()
        commands.append((terminalID, command))
        lock.unlock()
    }

    func commandCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return commands.count
    }
}

private func waitForSessionMode(
    conversation: ForemanConversation,
    expectedMode: AgentMode,
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        let mode = await MainActor.run { conversation.mode }
        if mode == expectedMode {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    Issue.record("Timed out waiting for session mode \(expectedMode).")
    throw CancellationError()
}

private func waitForSessionStopped(
    conversation: ForemanConversation,
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        let isRunning = await MainActor.run { conversation.isRunning }
        if !isRunning {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    Issue.record("Timed out waiting for session to stop.")
    throw CancellationError()
}

private func waitForAgentMessage(
    conversation: ForemanConversation,
    content: String,
    terminalID: String? = nil,
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        let messages = await MainActor.run { conversation.messages }
        if messages.contains(where: {
            $0.role == .agent &&
            $0.content == content &&
            (terminalID == nil || $0.terminalID == terminalID)
        }) {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    Issue.record("Timed out waiting for agent message '\(content)' on \(terminalID ?? "any terminal").")
    throw CancellationError()
}

private func makeAuthoritativeNeedsDirectionContext(
    _ promptsByTerminalID: [String: String]
) -> ForemanObservedTerminalContext {
    let orderedTerminalIDs = promptsByTerminalID.keys.sorted()
    let terminals = orderedTerminalIDs.map { terminalID in
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-\(terminalID)",
            tabID: "tab-\(terminalID)",
            title: terminalID,
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: promptsByTerminalID[terminalID] ?? "",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex"
        )
    }
    let workerSnapshots = Dictionary(uniqueKeysWithValues: orderedTerminalIDs.map { terminalID in
        let prompt = promptsByTerminalID[terminalID] ?? ""
        let workerSnapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: terminalID,
            workerSessionID: "codex-\(terminalID)",
            revision: 1,
            observedAt: Date(timeIntervalSince1970: 1_748_000_000),
            ttlMilliseconds: 15_000,
            workerGoal: "investigate",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .blocked,
                attention: .replyRequired,
                summary: prompt,
                details: [],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-\(terminalID)",
                kind: .reply,
                prompt: prompt,
                options: []
            ),
            suggestions: []
        )
        return (terminalID, workerSnapshot)
    })
    let understandings = orderedTerminalIDs.map { terminalID in
        let prompt = promptsByTerminalID[terminalID] ?? ""
        return TerminalUnderstanding.preview(
            terminalID: terminalID,
            state: .waiting,
            shortExplanation: prompt,
            lastMeaningfulEvent: prompt,
            importantDetails: [],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            supportLevel: .firstClass,
            evidence: [.init(source: .runtime, detail: "authoritative_worker_snapshot", confidence: 1.0)],
            agentInteractionContext: .waitingText(question: prompt),
            workerSnapshot: workerSnapshots[terminalID]
        )
    }

    return ForemanObservedTerminalContext(
        terminals: terminals,
        understandings: understandings,
        workerSnapshots: workerSnapshots
    )
}

private func makeWorkerSnapshot(
    terminalID: String,
    workerSessionID: String,
    revision: Int,
    workerGoal: String,
    identity: AgentIdentity,
    attention: TerminalWorkerAttention,
    summary: String,
    details: [String],
    request: TerminalWorkerSnapshot.Request?,
    suggestions: [TerminalWorkerSnapshot.Suggestion]
) -> TerminalWorkerSnapshot {
    TerminalWorkerSnapshot(
        schemaVersion: 1,
        terminalID: terminalID,
        workerSessionID: workerSessionID,
        revision: revision,
        observedAt: Date(timeIntervalSince1970: 1_748_000_000),
        ttlMilliseconds: 15_000,
        workerGoal: workerGoal,
        agent: .init(identity: identity),
        state: .init(
            lifecycle: .blocked,
            attention: attention,
            summary: summary,
            details: details,
            runtimeFlags: []
        ),
        request: request,
        suggestions: suggestions
    )
}

private func makeWorkerUnderstanding(
    terminalID: String,
    shortExplanation: String,
    lastMeaningfulEvent: String,
    agentIdentity: AgentIdentity,
    interactionState: AgentInteractionState,
    workerSnapshot: TerminalWorkerSnapshot,
    suggestedNextActions: [TerminalSuggestedAction] = []
) -> TerminalUnderstanding {
    TerminalUnderstanding.preview(
        terminalID: terminalID,
        state: .waiting,
        shortExplanation: shortExplanation,
        lastMeaningfulEvent: lastMeaningfulEvent,
        importantDetails: workerSnapshot.state.details,
        suggestedNextActions: suggestedNextActions,
        agentIdentity: agentIdentity,
        agentInteractionState: interactionState,
        supportLevel: .firstClass,
        workerSnapshot: workerSnapshot
    )
}
