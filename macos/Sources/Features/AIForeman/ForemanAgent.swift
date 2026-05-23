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
    private var captureObservedContext: (@MainActor () -> ForemanObservedTerminalContext?)?
    private let understandingEngine = TerminalUnderstandingEngine()
    private var previousSnapshotsByTerminalID: [String: TerminalSnapshot] = [:]
    private var previousUnderstandings: [TerminalUnderstanding] = []

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
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot],
        captureObservedContext: (@MainActor () -> ForemanObservedTerminalContext?)? = nil
    ) {
        self.captureSnapshots = captureSnapshots
        self.captureObservedContext = captureObservedContext
        lastOutcome = nil
        pauseState = .none
        previousSnapshotsByTerminalID = [:]
        previousUnderstandings = []
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
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot],
        captureObservedContext: (@MainActor () -> ForemanObservedTerminalContext?)? = nil
    ) async {
        self.captureObservedContext = captureObservedContext ?? self.captureObservedContext
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
                    conversation.addMessage(
                        role: .agent,
                        content: "▶️ Sent: \(command)",
                        terminalID: terminalID
                    )
                } else {
                    conversation.addMessage(
                        role: .agent,
                        content: "❌ Failed to send: \(command)",
                        terminalID: terminalID
                    )
                }
            }
            // Give terminal time to process command and display output
            // before next snapshot captures stale state
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        default:
            break
        }
    }

    func react(
        to event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext? = nil,
        captureSnapshots: (@MainActor () -> [TerminalSnapshot])? = nil
    ) async {
        let snapshotProvider = captureSnapshots ?? self.captureSnapshots
        guard let snapshotProvider else { return }

        cancelCurrentTask()

        let task = Task {
            let contextMessage = makeContextMessage(for: event)
            await MainActor.run {
                conversation.addHiddenContext(contextMessage)
            }

            do {
                try Task.checkCancellation()
                try await runSingleIteration(
                    event: event,
                    observedContext: observedContext,
                    captureSnapshots: snapshotProvider
                )
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    conversation.addMessage(
                        role: .agent,
                        content: "⚠️ Error reacting to event: \(error.localizedDescription)"
                    )
                }
            }
        }

        currentTask = task
        await task.value
    }

    func draftPendingAttention(
        for event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext? = nil,
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot]
    ) async throws -> PendingAgentAttention? {
        let contextMessage = makeContextMessage(for: event)
        DebugLogger.log("[ForemanAgent] draftPendingAttention start terminal=\(event.terminalID.prefix(8)) state=\(event.interactionState) delta='\(event.deltaText.prefix(160))'")
        await MainActor.run {
            conversation.addHiddenContext(contextMessage)
        }

        let observedTerminals = await observeTerminals(
            captureSnapshots: captureSnapshots,
            observedContext: observedContext
        )
        let terminals = observedTerminals.terminals
        let understandings = observedTerminals.understandings
        let overview = understandingEngine.makeOverview(
            current: understandings,
            previous: previousUnderstandings
        )
        let deltaTerminals = makeDeltaTerminals(from: terminals)

        storeObservedTerminals(observedTerminals)

        await MainActor.run {
            conversation.updateTerminalContext(
                overview: overview,
                understandings: understandings
            )
        }

        let response = try await foremanService.draftAgentReply(
            conversation: conversation,
            event: event,
            terminals: deltaTerminals,
            understandings: understandings,
            overview: overview,
            lastOutcome: lastOutcome
        )
        DebugLogger.log("[ForemanAgent] draftPendingAttention LLM suggestion terminal=\(event.terminalID.prefix(8)) suggestion=\(Self.describe(response.suggestion))")

        lastOutcome = nil
        await MainActor.run {
            conversation.incrementIteration()
        }

        switch response.suggestion {
        case .replyToAgent(let terminalID, let message, let reason, _):
            guard terminalID == event.terminalID else {
                DebugLogger.log("[ForemanAgent] draftPendingAttention ignored suggestion terminal=\(event.terminalID.prefix(8)) expected=\(event.terminalID) suggestion=\(Self.describe(response.suggestion))")
                return nil
            }
            DebugLogger.log("[ForemanAgent] draftPendingAttention produced suggestion terminal=\(event.terminalID.prefix(8)) message='\(message.prefix(160))' reason='\(reason.prefix(160))'")
            return PendingAgentAttention(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                fingerprint: event.fingerprint,
                title: "Suggested reply",
                description: reason.isEmpty ? event.deltaText : reason,
                detail: event.deltaText.isEmpty ? nil : event.deltaText,
                actions: [
                    .init(
                        id: "suggested_reply",
                        title: message,
                        payload: message,
                        style: .primary
                    )
                ]
            )

        case .askHuman(let terminalID, let message, let reason, _):
            guard terminalID == event.terminalID else {
                DebugLogger.log("[ForemanAgent] draftPendingAttention ignored ask-human terminal=\(event.terminalID.prefix(8)) expected=\(event.terminalID) suggestion=\(Self.describe(response.suggestion))")
                return nil
            }
            DebugLogger.log("[ForemanAgent] draftPendingAttention produced ask-human terminal=\(event.terminalID.prefix(8)) message='\(message.prefix(160))' reason='\(reason.prefix(160))'")
            return PendingAgentAttention(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                fingerprint: event.fingerprint,
                title: "Needs direction",
                description: message.isEmpty ? "The agent is waiting for your direction." : message,
                detail: reason.isEmpty ? event.deltaText : reason,
                actions: [
                    .init(
                        id: "recommend_next_step",
                        title: "Ask Kimi to recommend next step",
                        payload: Self.recommendNextStepPrompt,
                        style: .primary
                    ),
                ]
            )

        case .noAction:
            DebugLogger.log("[ForemanAgent] draftPendingAttention no-action terminal=\(event.terminalID.prefix(8)) suggestion=\(Self.describe(response.suggestion))")
            return nil
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

    private static let recommendNextStepPrompt = "Please inspect README.md and the current project structure, then suggest the most useful next task and explain why before making changes."

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
            let observedTerminals = await observeTerminals(captureSnapshots: captureSnapshots)
            let terminals = observedTerminals.terminals
            let understandings = observedTerminals.understandings
            let overview = understandingEngine.makeOverview(
                current: understandings,
                previous: previousUnderstandings
            )

            // Compute delta terminals BEFORE updating previous snapshots
            let deltaTerminals = makeDeltaTerminals(from: terminals)

            storeObservedTerminals(observedTerminals)

            await MainActor.run {
                conversation.updateTerminalContext(
                    overview: overview,
                    understandings: understandings
                )
            }

            if let runningAgent = runningAgentWithoutAttention(in: understandings) {
                await pauseUntilAgentNeedsAttention(runningAgent)
                break
            }

            // 2. Plan (with delta-truncated terminal text to keep LLM context small)
            await setStatus(.planning)
            let response = try await foremanService.agentStep(
                conversation: conversation,
                terminals: deltaTerminals,
                understandings: understandings,
                overview: overview,
                lastOutcome: lastOutcome
            )

            lastOutcome = nil
            try Task.checkCancellation()

            await MainActor.run {
                conversation.incrementIteration()
            }

            // 3. Execute
            let shouldContinue = try await executeAction(response)
            try Task.checkCancellation()
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

    private func executeAction(
        _ response: AgentStepResponse,
        terminalID messageTerminalID: String? = nil
    ) async throws -> Bool {
        await MainActor.run {
            onAction(response.action, response.thought)
        }

        switch response.action {
        case .respond(let message):
            await MainActor.run {
                conversation.addMessage(
                    role: .agent,
                    content: message,
                    terminalID: messageTerminalID
                )
            }
            return false

        case .sendCommand(let terminalID, let command, let reason):
            return try await handleSendCommand(
                terminalID: terminalID,
                command: command,
                reason: reason,
                messageTerminalID: messageTerminalID
            )

        case .askUser(let question):
            return try await handleAskUser(
                question: question,
                terminalID: messageTerminalID
            )

        case .declareComplete(let summary):
            await MainActor.run {
                conversation.addMessage(
                    role: .agent,
                    content: "✅ \(summary)",
                    terminalID: messageTerminalID
                )
                conversation.setStatus(.complete)
            }
            return false

        case .declareStuck(let reason):
            await MainActor.run {
                conversation.addMessage(
                    role: .agent,
                    content: "⚠️ I'm stuck: \(reason)",
                    terminalID: messageTerminalID
                )
                conversation.setStatus(.stuck)
            }
            return false
        }
    }

    private func handleSendCommand(
        terminalID: String,
        command: String,
        reason: String,
        messageTerminalID: String? = nil
    ) async throws -> Bool {
        // In interactive mode, ask user before executing
        let mode = await MainActor.run { conversation.mode }

        if mode == .interactive {
            let action = AgentAction.sendCommand(terminalID: terminalID, command: command, reason: reason)
            let message = reason.isEmpty ? "I'd like to run a command in the terminal." : reason
            await MainActor.run {
                conversation.addMessage(
                    role: .agent,
                    content: message,
                    action: action,
                    terminalID: messageTerminalID
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
                conversation.addMessage(
                    role: .agent,
                    content: "▶️ Sent: \(command)",
                    terminalID: messageTerminalID ?? terminalID
                )
            }
        } else {
            await MainActor.run {
                conversation.addMessage(
                    role: .agent,
                    content: "❌ Failed to send: \(command)",
                    terminalID: messageTerminalID ?? terminalID
                )
            }
        }

        // Give terminal time to process command and display output
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        return true
    }

    private func handleAskUser(question: String, terminalID: String? = nil) async throws -> Bool {
        await MainActor.run {
            conversation.addMessage(
                role: .agent,
                content: question,
                action: .askUser(question: question),
                terminalID: terminalID
            )
            conversation.setStatus(.waitingForUser)
        }
        pauseState = .awaitingUserReply(question: question)
        return false
    }

    // MARK: - One-Shot Reactive Helpers

    private func makeContextMessage(for event: AgentNeedsAttentionEvent) -> String {
        let agentName = event.agentIdentity.displayName ?? "AI agent"
        switch event.interactionState {
        case .waitingApproval:
            return "\(agentName) in terminal \(event.terminalID.prefix(8)) is waiting for approval.\n\nRecent output:\n\(event.deltaText)"
        case .waitingChoice:
            return "\(agentName) in terminal \(event.terminalID.prefix(8)) is waiting for a choice.\n\nRecent output:\n\(event.deltaText)"
        case .waitingText:
            return "\(agentName) in terminal \(event.terminalID.prefix(8)) is waiting for text input.\n\nRecent output:\n\(event.deltaText)"
        case .error:
            return "\(agentName) in terminal \(event.terminalID.prefix(8)) encountered an error.\n\nRecent output:\n\(event.deltaText)"
        default:
            return "\(agentName) in terminal \(event.terminalID.prefix(8)) needs attention.\n\nRecent output:\n\(event.deltaText)"
        }
    }

    private static func describe(_ action: AgentAction) -> String {
        switch action {
        case .respond(let message):
            return "respond message='\(message.prefix(160))'"
        case .sendCommand(let terminalID, let command, let reason):
            return "send_command terminal=\(terminalID) command='\(command.prefix(160))' reason='\(reason.prefix(160))'"
        case .askUser(let question):
            return "ask_user question='\(question.prefix(160))'"
        case .declareComplete(let summary):
            return "declare_complete summary='\(summary.prefix(160))'"
        case .declareStuck(let reason):
            return "declare_stuck reason='\(reason.prefix(160))'"
        }
    }

    private static func describe(_ suggestion: AgentReplyDraftSuggestion) -> String {
        switch suggestion {
        case .replyToAgent(let terminalID, let message, let reason, let confidence):
            return "reply_to_agent terminal=\(terminalID) message='\(message.prefix(160))' reason='\(reason.prefix(160))' confidence=\(confidence)"
        case .askHuman(let terminalID, let message, let reason, let confidence):
            return "ask_human terminal=\(terminalID) message='\(message.prefix(160))' reason='\(reason.prefix(160))' confidence=\(confidence)"
        case .noAction(let reason, let confidence):
            return "no_action reason='\(reason.prefix(160))' confidence=\(confidence)"
        }
    }

    private func runSingleIteration(
        event: AgentNeedsAttentionEvent,
        observedContext: ForemanObservedTerminalContext? = nil,
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot]
    ) async throws {
        await setStatus(.observing)
        let observedTerminals = await observeTerminals(
            captureSnapshots: captureSnapshots,
            observedContext: observedContext
        )
        let terminals = observedTerminals.terminals
        let understandings = observedTerminals.understandings
        let overview = understandingEngine.makeOverview(
            current: understandings,
            previous: previousUnderstandings
        )

        // Delta truncation for LLM context efficiency
        let deltaTerminals = makeDeltaTerminals(from: terminals)

        storeObservedTerminals(observedTerminals)

        await MainActor.run {
            conversation.updateTerminalContext(
                overview: overview,
                understandings: understandings
            )
        }

        if let runningAgent = runningAgentWithoutAttention(in: understandings) {
            await pauseUntilAgentNeedsAttention(runningAgent)
            return
        }

        // Plan
        await setStatus(.planning)
        let response = try await foremanService.agentStep(
            conversation: conversation,
            terminals: deltaTerminals,
            understandings: understandings,
            overview: overview,
            lastOutcome: lastOutcome
        )

        lastOutcome = nil
        try Task.checkCancellation()

        await MainActor.run {
            conversation.incrementIteration()
        }

        // Execute (one action, then stop)
        _ = try await executeAction(response, terminalID: event.terminalID)
        try Task.checkCancellation()

        await MainActor.run {
            if conversation.status != .waitingForUser {
                conversation.status = .idle
                conversation.isRunning = false
            }
        }
    }

    private func makeDeltaTerminals(from terminals: [TerminalSnapshot]) -> [TerminalSnapshot] {
        terminals.map { terminal in
            let previous = previousSnapshotsByTerminalID[terminal.terminalID]
            let deltaText = TerminalSnapshot.computeTextDelta(
                previous: previous?.visibleText,
                current: terminal.visibleText
            )
            return TerminalSnapshot(
                terminalID: terminal.terminalID,
                windowID: terminal.windowID,
                tabID: terminal.tabID,
                title: terminal.title,
                cwd: terminal.cwd,
                isFocused: terminal.isFocused,
                captureMode: terminal.captureMode,
                visibleText: deltaText,
                recentScrollback: terminal.recentScrollback,
                lastInputPreview: terminal.lastInputPreview,
                runtime: terminal.runtime,
                signals: terminal.signals
            )
        }
    }

    private func observeTerminals(
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot],
        observedContext: ForemanObservedTerminalContext? = nil
    ) async -> ForemanObservedTerminalContext {
        if let observedContext {
            return observedContext
        }

        if let captureObservedContext, let observedContext = await captureObservedContext() {
            return observedContext
        }

        let terminals = await captureSnapshots()
        let understandings = terminals.map { snapshot in
            understandingEngine.understand(
                current: snapshot,
                previous: previousSnapshotsByTerminalID[snapshot.terminalID],
                lastOutcome: lastOutcome
            )
        }
        return ForemanObservedTerminalContext(
            terminals: terminals,
            understandings: understandings
        )
    }

    private func storeObservedTerminals(_ observedTerminals: ForemanObservedTerminalContext) {
        previousSnapshotsByTerminalID = Dictionary(
            uniqueKeysWithValues: observedTerminals.terminals.map { ($0.terminalID, $0) }
        )
        previousUnderstandings = observedTerminals.understandings
    }

    private func runningAgentWithoutAttention(in understandings: [TerminalUnderstanding]) -> TerminalUnderstanding? {
        let agentUnderstandings = understandings.filter { $0.agentIdentity != .none }
        guard !agentUnderstandings.contains(where: Self.needsHumanAttention) else {
            return nil
        }
        return agentUnderstandings.first { $0.agentInteractionState == .running }
    }

    private static func needsHumanAttention(_ understanding: TerminalUnderstanding) -> Bool {
        switch understanding.agentInteractionState {
        case .waitingApproval, .waitingChoice, .waitingText, .error:
            return true
        case .unknown, .running, .completed:
            return false
        }
    }

    private func pauseUntilAgentNeedsAttention(_ understanding: TerminalUnderstanding) async {
        DebugLogger.log("[ForemanAgent] deferring plan while \(understanding.agentIdentity) terminal=\(understanding.terminalID.prefix(8)) is running")
        await MainActor.run {
            conversation.setStatus(.idle)
            conversation.isRunning = false
        }
    }
}
