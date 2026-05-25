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
}

@MainActor
private final class SidebarSessionSpy: ForemanSidebarSessionControlling {
    private(set) var recordedMessages: [String] = []
    private(set) var startedGoals: [String] = []
    private(set) var stopCallCount = 0
    private(set) var approvedCount = 0
    private(set) var skippedCount = 0
    private(set) var receivedOutcomes: [TerminalOutcomeReport] = []

    func start(goal: String, mode: AgentMode) {
        startedGoals.append(goal)
    }

    func receiveUserMessage(_ text: String) {
        recordedMessages.append(text)
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
        conversation: ForemanConversation,
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
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        AgentStepResponse(
            thought: "done",
            action: .declareComplete(summary: "done")
        )
    }

    func draftAgentReply(
        conversation: ForemanConversation,
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
