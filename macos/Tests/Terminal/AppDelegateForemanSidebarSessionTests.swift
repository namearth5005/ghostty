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
