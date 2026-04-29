import Foundation

actor ForemanAgent {
    private enum PauseState {
        case none
        case awaitingApproval(AgentAction)
        case awaitingUserReply(question: String)
    }

    private let conversation: ForemanConversation
    private let foremanService: ForemanService
    private let onSendCommand: @MainActor (String, String) async -> Bool
    private let onStatusChange: @MainActor (AgentStatus) -> Void
    private let onAction: @MainActor (AgentAction, String) -> Void

    private var currentTask: Task<Void, Never>?
    private var lastOutcome: TerminalOutcomeReport?
    private var pauseState: PauseState = .none
    private var captureSnapshots: (@MainActor () -> [TerminalSnapshot])?

    init(
        conversation: ForemanConversation,
        foremanService: ForemanService,
        onSendCommand: @escaping @MainActor (String, String) async -> Bool,
        onStatusChange: @escaping @MainActor (AgentStatus) -> Void,
        onAction: @escaping @MainActor (AgentAction, String) -> Void
    ) {
        self.conversation = conversation
        self.foremanService = foremanService
        self.onSendCommand = onSendCommand
        self.onStatusChange = onStatusChange
        self.onAction = onAction
    }

    func start(
        goal: String,
        mode: AgentMode,
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot]
    ) {
        self.captureSnapshots = captureSnapshots
        lastOutcome = nil
        pauseState = .none
        cancelCurrentTask()

        currentTask = Task {
            await MainActor.run {
                conversation.start(goal: goal, mode: mode)
            }

            do {
                try await runLoop(captureSnapshots: captureSnapshots)
            } catch {
                await MainActor.run {
                    conversation.errorMessage = error.localizedDescription
                    conversation.stop()
                }
            }
        }
    }

    func receiveUserMessage(_ text: String) async {
        await MainActor.run {
            conversation.addMessage(role: .user, content: text)
        }

        switch pauseState {
        case .awaitingUserReply:
            pauseState = .none
            await resumeLoop()
        case .awaitingApproval:
            pauseState = .none
            await resumeLoop()
        case .none:
            if await shouldResumeAfterUserMessage() {
                await resumeLoop()
            }
        }
    }

    func approvePendingAction(
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot]
    ) async {
        self.captureSnapshots = captureSnapshots
        guard case .awaitingApproval(let action) = pauseState else { return }
        pauseState = .none
        await resumeLoop(executingApprovedAction: action)
    }

    func skipPendingAction() {
        pauseState = .none
        cancelCurrentTask()
        Task {
            await MainActor.run {
                conversation.addMessage(role: .agent, content: "⏭️ Skipped.")
                conversation.setStatus(.idle)
                conversation.isRunning = false
            }
        }
    }

    private func executeApprovedAction(_ action: AgentAction) async {
        switch action {
        case .sendCommand(let terminalID, let command, _):
            await setStatus(.executing)
            let sent = await onSendCommand(terminalID, command)
            await MainActor.run {
                if sent {
                    conversation.addMessage(role: .agent, content: "▶️ Sent: \(command)")
                } else {
                    conversation.addMessage(role: .agent, content: "❌ Failed to send: \(command)")
                }
            }
            // Give terminal time to process command and display output
            // before next snapshot captures stale state
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        default:
            break
        }
    }

    func receiveOutcome(_ report: TerminalOutcomeReport) {
        lastOutcome = report
    }

    func stop() {
        cancelCurrentTask()
        pauseState = .none
        captureSnapshots = nil
        Task {
            await MainActor.run {
                conversation.stop()
            }
        }
    }

    private func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func shouldResumeAfterUserMessage() async -> Bool {
        await MainActor.run {
            guard conversation.goal != nil else { return false }
            guard !conversation.isRunning else { return false }
            switch conversation.status {
            case .idle, .complete, .stuck:
                return true
            default:
                return false
            }
        }
    }

    private func resumeLoop(executingApprovedAction action: AgentAction? = nil) async {
        guard let captureSnapshots else {
            await MainActor.run {
                conversation.errorMessage = "Agent session can't resume because terminal snapshots are unavailable."
                conversation.isRunning = false
            }
            return
        }

        cancelCurrentTask()
        currentTask = Task {
            do {
                await MainActor.run {
                    conversation.isRunning = true
                    conversation.status = .observing
                    conversation.errorMessage = nil
                }

                if let action {
                    await executeApprovedAction(action)
                }

                try await runLoop(captureSnapshots: captureSnapshots)
            } catch {
                await MainActor.run {
                    conversation.errorMessage = error.localizedDescription
                    conversation.stop()
                }
            }
        }
    }

    private func runLoop(
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot]
    ) async throws {
        while await !shouldStop() {
            // 1. Observe
            await setStatus(.observing)
            let terminals = await captureSnapshots()

            // 2. Plan
            await setStatus(.planning)
            let response = try await foremanService.agentStep(
                conversation: conversation,
                terminals: terminals,
                lastOutcome: lastOutcome
            )

            lastOutcome = nil

            await MainActor.run {
                conversation.incrementIteration()
            }

            // 3. Execute
            let shouldContinue = try await executeAction(response)
            guard shouldContinue else { break }
        }

        await MainActor.run {
            if conversation.status != .complete && conversation.status != .stuck && conversation.status != .waitingForUser {
                conversation.status = .idle
            }
            if conversation.status != .waitingForUser {
                conversation.isRunning = false
            }
        }
    }

    private func shouldStop() async -> Bool {
        await MainActor.run {
            !conversation.isRunning || conversation.hasReachedMaxIterations
        }
    }

    private func setStatus(_ status: AgentStatus) async {
        await MainActor.run {
            conversation.setStatus(status)
            onStatusChange(status)
        }
    }

    private func executeAction(_ response: AgentStepResponse) async throws -> Bool {
        await MainActor.run {
            onAction(response.action, response.thought)
        }

        switch response.action {
        case .respond(let message):
            await MainActor.run {
                conversation.addMessage(role: .agent, content: message)
            }
            return false

        case .sendCommand(let terminalID, let command, let reason):
            return try await handleSendCommand(terminalID: terminalID, command: command, reason: reason)

        case .askUser(let question):
            return try await handleAskUser(question: question)

        case .declareComplete(let summary):
            await MainActor.run {
                conversation.addMessage(role: .agent, content: "✅ \(summary)")
                conversation.setStatus(.complete)
            }
            return false

        case .declareStuck(let reason):
            await MainActor.run {
                conversation.addMessage(role: .agent, content: "⚠️ I'm stuck: \(reason)")
                conversation.setStatus(.stuck)
            }
            return false
        }
    }

    private func handleSendCommand(terminalID: String, command: String, reason: String) async throws -> Bool {
        // In interactive mode, ask user before executing
        let mode = await MainActor.run { conversation.mode }

        if mode == .interactive {
            let action = AgentAction.sendCommand(terminalID: terminalID, command: command, reason: reason)
            let message = reason.isEmpty ? "I'd like to run a command in the terminal." : reason
            await MainActor.run {
                conversation.addMessage(
                    role: .agent,
                    content: message,
                    action: action
                )
                conversation.setStatus(.waitingForUser)
            }
            pauseState = .awaitingApproval(action)
            return false
        }

        // Autonomous mode: execute directly
        await setStatus(.executing)
        let sent = await onSendCommand(terminalID, command)

        if sent {
            await MainActor.run {
                conversation.addMessage(role: .agent, content: "▶️ Sent: \(command)")
            }
        } else {
            await MainActor.run {
                conversation.addMessage(role: .agent, content: "❌ Failed to send: \(command)")
            }
        }

        // Give terminal time to process command and display output
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        return true
    }

    private func handleAskUser(question: String) async throws -> Bool {
        await MainActor.run {
            conversation.addMessage(
                role: .agent,
                content: question,
                action: .askUser(question: question)
            )
            conversation.setStatus(.waitingForUser)
        }
        pauseState = .awaitingUserReply(question: question)
        return false
    }
}
