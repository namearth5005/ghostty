import Foundation
import Testing
@testable import Ghostty

struct ForemanAgentTests {
    @Test
    func plainReplyEndsTurnWithoutEnteringWaitingState() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let responses: [AgentStepResponse] = [
            try makeStepResponse(
                thought: "This is just a greeting.",
                action: AgentAction.respond(message: "Hey there.")
            ),
        ]
        let client = ScriptedForemanClient(responses: responses)
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        await agent.start(goal: "hey", mode: AgentMode.interactive, captureSnapshots: sampleSnapshots)

        try await waitFor {
            await MainActor.run {
                conversation.iterationCount >= 1 &&
                conversation.status == .idle &&
                conversation.isRunning == false
            }
        }

        let messages = await MainActor.run { conversation.messages }
        let commands = await commandRecorder.recordedCommands()
        let isRunning = await MainActor.run { conversation.isRunning }
        #expect(messages.contains { $0.role == .agent && $0.content == "Hey there." })
        #expect(commands.isEmpty)
        #expect(isRunning == false)
    }

    @Test
    func userReplyAfterAskUserResumesLoopAndCompletes() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let responses: [AgentStepResponse] = [
            try makeStepResponse(
                thought: "Need clarification before proceeding.",
                action: AgentAction.askUser(question: "Which files should I inspect?")
            ),
            try makeStepResponse(
                thought: "User clarified the scope.",
                action: AgentAction.declareComplete(summary: "I have the answer I needed.")
            ),
        ]
        let client = ScriptedForemanClient(responses: responses)
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        await agent.start(goal: "Inspect the files", mode: AgentMode.interactive, captureSnapshots: sampleSnapshots)

        try await waitForStatus(.waitingForUser, in: conversation)

        await agent.receiveUserMessage("Focus on the Swift files.")

        try await waitForStatus(.complete, in: conversation)

        let messages = await MainActor.run { conversation.messages }
        let commands = await commandRecorder.recordedCommands()
        #expect(messages.contains { $0.role == .user && $0.content == "Focus on the Swift files." })
        #expect(messages.contains { $0.role == .agent && $0.content == "✅ I have the answer I needed." })
        #expect(commands.isEmpty)
    }

    @Test
    func approvedInteractiveCommandResumesLoopAndThenCompletes() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let responses: [AgentStepResponse] = [
            try makeStepResponse(
                thought: "Need to inspect the directory contents.",
                action: AgentAction.sendCommand(terminalID: "term-1", command: "ls -la", reason: "List the files in the current directory.")
            ),
            try makeStepResponse(
                thought: "The command finished.",
                action: AgentAction.declareComplete(summary: "The files are listed.")
            ),
        ]
        let client = ScriptedForemanClient(responses: responses)
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        await agent.start(goal: "List the files", mode: AgentMode.interactive, captureSnapshots: sampleSnapshots)

        try await waitForStatus(.waitingForUser, in: conversation)

        await agent.approvePendingAction(captureSnapshots: sampleSnapshots)

        try await waitFor {
            let commands = await commandRecorder.recordedCommands()
            return commands.count == 1 && commands[0].terminalID == "term-1" && commands[0].command == "ls -la"
        }
        try await waitForStatus(.complete, in: conversation, timeoutNanoseconds: 6_000_000_000)

        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.role == .agent && $0.content == "▶️ Sent: ls -la" })
        #expect(messages.contains { $0.role == .agent && $0.content == "✅ The files are listed." })
    }

    @Test
    func followUpMessageAfterCompleteStartsANewLoop() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let responses: [AgentStepResponse] = [
            try makeStepResponse(
                thought: "Goal is already done.",
                action: AgentAction.declareComplete(summary: "The files are listed.")
            ),
            try makeStepResponse(
                thought: "Responding to the new follow-up message.",
                action: AgentAction.declareComplete(summary: "Hello back.")
            ),
        ]
        let client = ScriptedForemanClient(responses: responses)
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        await agent.start(goal: "List the files", mode: AgentMode.interactive, captureSnapshots: sampleSnapshots)

        try await waitForStatus(.complete, in: conversation)

        await agent.receiveUserMessage("hey how are you")

        try await waitForIterationCount(2, in: conversation)
        try await waitForStatus(.complete, in: conversation)

        let messages = await MainActor.run { conversation.messages }
        let commands = await commandRecorder.recordedCommands()
        #expect(messages.contains { $0.role == .user && $0.content == "hey how are you" })
        #expect(messages.contains { $0.role == .agent && $0.content == "✅ Hello back." })
        #expect(commands.isEmpty)
    }

    @Test
    func followUpQuestionUsesStructuredTerminalOverview() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(
            responses: [
                try makeStepResponse(
                    thought: "I can answer from structured context.",
                    action: .respond(message: "This terminal failed because `hfind` is not installed. The likely fix is `find . -print`.")
                ),
            ]
        )

        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        await agent.start(goal: "what happened here?", mode: .interactive, captureSnapshots: failedFindSnapshots)

        try await waitFor {
            await MainActor.run { conversation.iterationCount >= 1 && conversation.status == .idle }
        }

        let payloads = await client.recordedUnderstandings()
        let overviews = await client.recordedOverviews()
        #expect(payloads.count == 1)
        #expect(payloads.first?.first?.state == .failed)
        #expect(payloads.first?.first?.lastMeaningfulEvent == "zsh: command not found: hfind")
        #expect(overviews.count == 1)
        #expect(overviews.first?.summary.contains("term-1") == true)
        #expect(overviews.first?.summary.contains("hfind") == true)
        let lastOverview = await MainActor.run { conversation.lastOverview }
        let lastUnderstandings = await MainActor.run { conversation.lastUnderstandings }
        #expect(lastOverview?.summary.contains("term-1") == true)
        #expect(lastUnderstandings.first?.state == .failed)
        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.content.contains("likely fix is `find . -print`") })
    }

    @Test
    func startingAndStoppingConversationClearsStructuredTerminalContext() async {
        let conversation = await MainActor.run { ForemanConversation() }
        let overview = TerminalOverview(
            summary: "term-1 failed",
            changedTerminalIDs: ["term-1"],
            primaryTerminalID: "term-1"
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .failed,
            shortExplanation: "The terminal failed.",
            lastMeaningfulEvent: "zsh: command not found: hfind",
            importantDetails: ["The typed command was `hfind . -print`."],
            suggestedNextActions: []
        )

        await MainActor.run {
            conversation.updateTerminalContext(overview: overview, understandings: [understanding])
            conversation.start(goal: "new session", mode: .interactive)
        }

        let clearedOnStart = await MainActor.run {
            conversation.lastOverview == nil && conversation.lastUnderstandings.isEmpty
        }
        #expect(clearedOnStart)

        await MainActor.run {
            conversation.updateTerminalContext(overview: overview, understandings: [understanding])
            conversation.stop()
        }

        let clearedOnStop = await MainActor.run {
            conversation.lastOverview == nil && conversation.lastUnderstandings.isEmpty
        }
        #expect(clearedOnStop)
    }

    @Test
    func independentTerminalsProduceOverviewWithoutInventedSharedStory() {
        let engine = TerminalUnderstandingEngine()
        let overview = engine.makeOverview(
            current: [
                .preview(
                    terminalID: "term-1",
                    state: .failed,
                    shortExplanation: "Build failed because a module is missing.",
                    lastMeaningfulEvent: "error: module not found",
                    importantDetails: ["module A missing"],
                    suggestedNextActions: []
                ),
                .preview(
                    terminalID: "term-2",
                    state: .running,
                    shortExplanation: "Dev server is healthy and still running.",
                    lastMeaningfulEvent: "Listening on localhost:3000",
                    importantDetails: ["GET /health 200"],
                    suggestedNextActions: []
                ),
            ],
            previous: []
        )

        #expect(overview.summary.contains("term-1"))
        #expect(!overview.summary.contains("both terminals are working on the same task"))
    }

    @Test
    func uiPhaseTreatsAskUserAsAwaitingReply() {
        let phase = ConversationUIPhase.resolve(
            goal: "Investigate",
            isRunning: true,
            status: .waitingForUser,
            lastAction: .askUser(question: "What should I inspect?")
        )

        #expect(phase == .awaitingReply)
    }

    @Test
    func uiPhaseTreatsInteractiveCommandAsAwaitingApproval() {
        let phase = ConversationUIPhase.resolve(
            goal: "List the files",
            isRunning: true,
            status: .waitingForUser,
            lastAction: .sendCommand(terminalID: "term-1", command: "ls -la", reason: "Inspect files")
        )

        #expect(phase == .awaitingApproval(command: "ls -la"))
    }

    @Test
    func statusDisplayTreatsPendingCommandAsApprovalNeeded() {
        let display = ConversationStatusDisplay.resolve(
            status: .waitingForUser,
            phase: .awaitingApproval(command: "ls -la")
        )

        #expect(display == .awaitingApproval)
    }

    @Test
    func statusDisplayTreatsIdleConversationAsChattingWhenSessionExists() {
        let display = ConversationStatusDisplay.resolve(
            status: .idle,
            phase: .chatting
        )

        #expect(display == .chatting)
    }
}

private func makeStepResponse(thought: String, action: AgentAction) throws -> AgentStepResponse {
    struct StepEnvelope: Encodable {
        let thought: String
        let action: AgentAction
    }

    let data = try JSONEncoder().encode(StepEnvelope(thought: thought, action: action))
    return try JSONDecoder().decode(AgentStepResponse.self, from: data)
}

private func makeAgent(
    conversation: ForemanConversation,
    client: ScriptedForemanClient,
    commandRecorder: CommandRecorder
) -> ForemanAgent {
    let service = ForemanService(client: client)
    return ForemanAgent(
        conversation: conversation,
        foremanService: service,
        onSendCommand: { terminalID, command in
            await commandRecorder.record(terminalID: terminalID, command: command)
            return true
        },
        onStatusChange: { _ in },
        onAction: { _, _ in }
    )
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
            recentScrollbackLines: ["$ pwd", "/tmp/project"],
            lastInputPreview: "ls -la"
        ),
    ]
}

@MainActor
private func failedFindSnapshots() -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "hfind . -print\nzsh: command not found: hfind\nuser@host %",
            recentScrollbackLines: [
                "$ pwd",
                "/tmp/project",
                "hfind . -print",
                "zsh: command not found: hfind",
            ],
            lastInputPreview: "hfind . -print"
        ),
    ]
}

private func waitForStatus(
    _ expectedStatus: AgentStatus,
    in conversation: ForemanConversation,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async throws {
    try await waitFor(timeoutNanoseconds: timeoutNanoseconds) {
        await MainActor.run { conversation.status == expectedStatus }
    }
}

private func waitForIterationCount(
    _ expectedCount: Int,
    in conversation: ForemanConversation,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async throws {
    try await waitFor(timeoutNanoseconds: timeoutNanoseconds) {
        await MainActor.run { conversation.iterationCount >= expectedCount }
    }
}

private func waitFor(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 20_000_000,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    throw WaitTimeoutError()
}

private struct WaitTimeoutError: Error {}

private actor CommandRecorder {
    struct RecordedCommand: Equatable, Sendable {
        let terminalID: String
        let command: String
    }

    private var commands: [RecordedCommand] = []

    func record(terminalID: String, command: String) {
        commands.append(.init(terminalID: terminalID, command: command))
    }

    func recordedCommands() -> [RecordedCommand] {
        commands
    }
}

private actor ScriptedForemanClient: ForemanLLMClient {
    private var responses: [AgentStepResponse]
    private var understandingsLog: [[TerminalUnderstanding]] = []
    private var overviewsLog: [TerminalOverview] = []

    init(responses: [AgentStepResponse]) {
        self.responses = responses
    }

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw ScriptedForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw ScriptedForemanClientError.unexpectedCall
    }

    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        understandingsLog.append(understandings)
        overviewsLog.append(overview)
        guard !responses.isEmpty else {
            throw ScriptedForemanClientError.missingResponse
        }
        return responses.removeFirst()
    }

    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        guard !responses.isEmpty else {
            throw ScriptedForemanClientError.missingResponse
        }
        return responses.removeFirst()
    }

    func recordedUnderstandings() -> [[TerminalUnderstanding]] {
        understandingsLog
    }

    func recordedOverviews() -> [TerminalOverview] {
        overviewsLog
    }
}

private enum ScriptedForemanClientError: Error {
    case unexpectedCall
    case missingResponse
}
