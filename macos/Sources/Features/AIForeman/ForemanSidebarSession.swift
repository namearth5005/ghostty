import Foundation

@MainActor
protocol ForemanSidebarSessionControlling: AnyObject {
    func start(goal: String, mode: AgentMode)
    func receiveUserMessage(_ text: String)
    func stop()
    func approvePendingAction()
    func skipPendingAction()
    func receiveOutcome(_ report: TerminalOutcomeReport)
    func draftPendingAttention(
        for event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext?
    ) async throws -> PendingAgentAttention?
    func react(
        to event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext?
    ) async
}

@MainActor
final class ForemanSidebarSession: ForemanSidebarSessionControlling {
    private let conversation: ForemanConversation
    private let foremanService: ForemanService
    private let goalRuntime: ForemanProjectGoalRuntime
    private let preferredTerminalID: () -> String?
    private let captureSnapshots: @MainActor () -> [TerminalSnapshot]
    private let captureObservedContext: @MainActor () -> ForemanObservedTerminalContext?
    private let onSendCommand: @MainActor (String, String) -> Bool

    private var agent: ForemanAgent?
    private var preservedMode: AgentMode

    init(
        conversation: ForemanConversation,
        foremanService: ForemanService,
        goalRuntime: ForemanProjectGoalRuntime,
        preferredTerminalID: @escaping () -> String?,
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot],
        captureObservedContext: @escaping @MainActor () -> ForemanObservedTerminalContext?,
        onSendCommand: @escaping @MainActor (String, String) -> Bool
    ) {
        self.conversation = conversation
        self.foremanService = foremanService
        self.goalRuntime = goalRuntime
        self.preferredTerminalID = preferredTerminalID
        self.captureSnapshots = captureSnapshots
        self.captureObservedContext = captureObservedContext
        self.onSendCommand = onSendCommand
        self.preservedMode = conversation.mode
    }

    func start(goal: String, mode: AgentMode) {
        preservedMode = mode
        let agent = ensureAgent(preferredTerminalID: preferredTerminalID())
        Task {
            await agent.start(
                goal: goal,
                mode: mode,
                captureSnapshots: captureSnapshots,
                captureObservedContext: captureObservedContext
            )
        }
    }

    func receiveUserMessage(_ text: String) {
        guard let agent else {
            let agent = ensureAgent(preferredTerminalID: preferredTerminalID())
            let initialGoal = conversation.effectiveGoal ?? text
            Task {
                await agent.start(
                    goal: initialGoal,
                    mode: preservedMode,
                    captureSnapshots: captureSnapshots,
                    captureObservedContext: captureObservedContext
                )
                if initialGoal != text {
                    await agent.receiveUserMessage(text)
                }
            }
            return
        }

        Task {
            await agent.receiveUserMessage(text)
        }
    }

    func stop() {
        guard let agent else { return }
        self.agent = nil
        Task {
            await agent.stop()
        }
    }

    func approvePendingAction() {
        guard let agent else { return }
        Task {
            await agent.approvePendingAction(
                captureSnapshots: captureSnapshots,
                captureObservedContext: captureObservedContext
            )
        }
    }

    func skipPendingAction() {
        guard let agent else { return }
        Task {
            await agent.skipPendingAction()
        }
    }

    func receiveOutcome(_ report: TerminalOutcomeReport) {
        guard let agent else { return }
        Task {
            await agent.receiveOutcome(report)
        }
    }

    func draftPendingAttention(
        for event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext?
    ) async throws -> PendingAgentAttention? {
        let agent = ensureAgent(preferredTerminalID: event.terminalID)
        return try await agent.draftPendingAttention(
            for: event,
            observedContext: observedContext,
            captureSnapshots: captureSnapshots
        )
    }

    func react(
        to event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext?
    ) async {
        let agent = ensureAgent(preferredTerminalID: event.terminalID)
        await agent.react(
            to: event,
            observedContext: observedContext,
            captureSnapshots: captureSnapshots
        )
    }

    private func ensureAgent(preferredTerminalID: String?) -> ForemanAgent {
        if let agent {
            return agent
        }

        let agent = ForemanAgent(
            conversation: conversation,
            foremanService: foremanService,
            goalRuntime: goalRuntime,
            preferredTerminalID: preferredTerminalID,
            onSendCommand: { [onSendCommand] terminalID, command in
                onSendCommand(terminalID, command)
            },
            onStatusChange: { _ in },
            onAction: { _, _ in }
        )
        self.agent = agent
        return agent
    }
}
