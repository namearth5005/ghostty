import Foundation
import Testing
@testable import Ghostty

struct ForemanAgentTests {
    struct PendingAttentionSignature: Equatable {
        let agentIdentity: AgentIdentity
        let interactionState: AgentInteractionState
        let title: String
        let description: String
        let detail: String?
        let actions: [PendingAgentAction]
        let status: PendingAgentAttentionStatus
        let errorMessage: String?
    }

    struct UnderstandingSignature: Equatable {
        let state: TerminalUnderstandingState
        let agentIdentity: AgentIdentity
        let interactionState: AgentInteractionState
        let supportLevel: AgentSupportLevel
        let lastMeaningfulEvent: String
        let shortExplanation: String
        let importantDetails: [String]
        let suggestedNextActions: [TerminalSuggestedAction]
        let interactionContext: AgentInteractionContext
    }

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
    func approvedInteractiveCommandWaitsWhenTargetAgentIsStillRunning() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let responses: [AgentStepResponse] = [
            try makeStepResponse(
                thought: "Need to ask Kimi to work.",
                action: AgentAction.sendCommand(terminalID: "term-1", command: "finish the analysis", reason: "Ask Kimi to finish the analysis.")
            ),
            try makeStepResponse(
                thought: "Should not be called while Kimi is still running.",
                action: AgentAction.sendCommand(terminalID: "term-1", command: "do another thing", reason: "This would interrupt Kimi.")
            ),
        ]
        let client = ScriptedForemanClient(responses: responses)
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        await agent.start(goal: "Finish the analysis", mode: AgentMode.interactive, captureSnapshots: sampleSnapshots)

        try await waitForStatus(.waitingForUser, in: conversation)

        await agent.approvePendingAction(captureSnapshots: runningKimiSnapshots)

        try await waitFor {
            let commands = await commandRecorder.recordedCommands()
            return commands.count == 1 && commands[0].command == "finish the analysis"
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)

        let status = await MainActor.run { conversation.status }
        let messages = await MainActor.run { conversation.messages }
        let stepCalls = await client.agentStepCallCount()

        #expect(stepCalls == 1)
        #expect(status != .waitingForUser)
        #expect(!messages.contains { $0.content.contains("This would interrupt Kimi.") })
    }

    @Test
    func explicitGoalReopenAfterCompleteStartsANewLoop() async throws {
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

        await agent.receiveUserMessage("/goal reopen")

        try await waitForIterationCount(2, in: conversation)
        try await waitForStatus(.complete, in: conversation)

        let messages = await MainActor.run { conversation.messages }
        let commands = await commandRecorder.recordedCommands()
        #expect(messages.contains { $0.role == .user && $0.content == "/goal reopen" })
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
        let runtimeState = await MainActor.run { conversation.runtimeState }
        let lastOverview = await MainActor.run { runtimeState.lastOverview }
        let lastUnderstandings = await MainActor.run { runtimeState.lastUnderstandings }
        #expect(lastOverview?.summary.contains("term-1") == true)
        #expect(lastUnderstandings.first?.state == .failed)
        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.content.contains("likely fix is `find . -print`") })
    }

    @Test
    func fallbackObservationPreservesFreshOutcomeSummary() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(
            responses: [
                try makeStepResponse(
                    thought: "The outcome is already clear.",
                    action: .respond(message: "The tests finished successfully.")
                ),
            ]
        )
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let snapshots = await successfulTestSnapshots()
        let outcome = TerminalOutcomeReport(
            terminalID: "term-1",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: .now,
            summary: "Tests finished successfully."
        )

        await agent.receiveOutcome(outcome)
        await agent.start(goal: "what happened?", mode: .interactive, captureSnapshots: { snapshots })

        try await waitFor {
            let payloads = await client.recordedUnderstandings()
            return !payloads.isEmpty
        }

        let payloads = await client.recordedUnderstandings()
        let forwarded = try #require(payloads.first?.first)
        #expect(forwarded.state == .succeeded)
        #expect(forwarded.lastMeaningfulEvent == "Tests finished successfully.")
        #expect(forwarded.shortExplanation.contains("Tests finished successfully."))
    }

    @Test
    func loopUsesSuppliedObservedContextDuringStart() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(
            responses: [
                try makeStepResponse(
                    thought: "The structured waiting question is already clear.",
                    action: .respond(message: "Use the structured waiting question.")
                ),
            ]
        )
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let snapshots = kimiInputChromeSnapshots(
            terminalID: "term-1",
            title: "Kimi Code",
            isFocused: true
        )
        let observedContext = kimiObservedWaitingTextContext(
            terminalID: "term-1",
            snapshots: snapshots
        )

        await agent.start(
            goal: "help kimi",
            mode: .interactive,
            captureSnapshots: { snapshots },
            captureObservedContext: { observedContext }
        )

        try await waitFor {
            await MainActor.run { conversation.messages.contains { $0.content == "Use the structured waiting question." } }
        }

        let payloads = await client.recordedUnderstandings()
        let forwarded = try #require(payloads.first?.first)
        #expect(forwarded.agentInteractionContext == .waitingText(question: "What should I do here?"))
        #expect(forwarded.lastMeaningfulEvent == "What should I do here?")
        let runtimeState = await MainActor.run { conversation.runtimeState }
        let lastUnderstandings = await MainActor.run { runtimeState.lastUnderstandings }
        #expect(lastUnderstandings.first?.agentInteractionContext == .waitingText(question: "What should I do here?"))
    }

    @Test
    func approvalResumeUsesSuppliedObservedContextProvider() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(
            responses: [
                try makeStepResponse(
                    thought: "Need to send the scoped reply.",
                    action: .sendCommand(
                        terminalID: "term-1",
                        command: "echo structured",
                        reason: "Reply based on the structured waiting question."
                    )
                ),
                try makeStepResponse(
                    thought: "The context stayed structured after approval.",
                    action: .respond(message: "Structured context persisted after approval.")
                ),
            ]
        )
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let snapshots = kimiInputChromeSnapshots(
            terminalID: "term-1",
            title: "Kimi Code",
            isFocused: true
        )
        let observedContext = kimiObservedWaitingTextContext(
            terminalID: "term-1",
            snapshots: snapshots
        )

        await agent.start(
            goal: "reply to kimi",
            mode: .interactive,
            captureSnapshots: { snapshots },
            captureObservedContext: { observedContext }
        )

        try await waitForStatus(.waitingForUser, in: conversation)

        await agent.approvePendingAction(
            captureSnapshots: { snapshots },
            captureObservedContext: { observedContext }
        )

        try await waitFor {
            await MainActor.run { conversation.messages.contains { $0.content == "Structured context persisted after approval." } }
        }

        let payloads = await client.recordedUnderstandings()
        #expect(payloads.count == 2)
        for payload in payloads {
            let forwarded = try #require(payload.first)
            #expect(forwarded.agentInteractionContext == .waitingText(question: "What should I do here?"))
            #expect(forwarded.lastMeaningfulEvent == "What should I do here?")
        }
    }

    @Test
    func genericCodexWireObservedContextKeepsStartParityAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("codex-wire-existing", "shell", true),
            ("codex-wire-new-tab", "nambouchara@Nams-MacBook-Pro:~", false),
            ("codex-wire-managed", "Codex", false),
        ]

        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let result = try await startWithObservedContextCase(
                snapshots: genericCodexWireSnapshots(
                    terminalID: entry.terminalID,
                    title: entry.title,
                    isFocused: entry.isFocused
                ),
                observedContext: genericCodexWireObservedContext(
                    terminalID: entry.terminalID,
                    title: entry.title,
                    isFocused: entry.isFocused
                ),
                response: try makeStepResponse(
                    thought: "The structured Codex context is already available.",
                    action: .respond(message: "Use the structured Codex context.")
                )
            )

            forwardedUnderstandings.append(try #require(result.understanding))
            #expect(result.messages.contains { $0.content == "Use the structured Codex context." })
        }

        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == forwardedUnderstandings.first })
        #expect(forwardedUnderstandings.first?.agentIdentity == .codex)
        #expect(forwardedUnderstandings.first?.interactionState == .waitingText)
        #expect(forwardedUnderstandings.first?.interactionContext == .waitingText(question: nil))
    }

    @Test
    func genericClaudeWireObservedContextKeepsStartParityAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("claude-wire-existing", "shell", true),
            ("claude-wire-new-tab", "nambouchara@Nams-MacBook-Pro:~", false),
            ("claude-wire-managed", "Claude", false),
        ]

        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let result = try await startWithObservedContextCase(
                snapshots: genericClaudeWireSnapshots(
                    terminalID: entry.terminalID,
                    title: entry.title,
                    isFocused: entry.isFocused
                ),
                observedContext: genericClaudeWireObservedContext(
                    terminalID: entry.terminalID,
                    title: entry.title,
                    isFocused: entry.isFocused
                ),
                response: try makeStepResponse(
                    thought: "The structured Claude context is already available.",
                    action: .respond(message: "Use the structured Claude context.")
                )
            )

            forwardedUnderstandings.append(try #require(result.understanding))
            #expect(result.messages.contains { $0.content == "Use the structured Claude context." })
        }

        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == forwardedUnderstandings.first })
        #expect(forwardedUnderstandings.first?.agentIdentity == .claudeCode)
        #expect(forwardedUnderstandings.first?.interactionState == .waitingText)
        #expect(forwardedUnderstandings.first?.interactionContext == .waitingText(question: nil))
    }

    @Test
    func codexTransitionObservedContextKeepsStartParityAcrossLaunchPaths() async throws {
        let builder = ForemanObservedContextBuilder()
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("codex-transition-existing", "shell", true),
            ("codex-transition-new-tab", "nambouchara@Nams-MacBook-Pro:~", false),
            ("codex-transition-managed", "OpenAI Codex", false),
        ]

        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: """
                • Hey. What do you need help with?

                ›
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: 1001,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: "• Working (0s • esc to interrupt)",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: 1001,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )
            let observedContext = builder.build(
                snapshots: [current],
                previousSnapshotsByTerminalID: [entry.terminalID: previous]
            ).context

            let result = try await startWithObservedContextCase(
                snapshots: [current],
                observedContext: observedContext,
                response: try makeStepResponse(
                    thought: "The Codex question is already clear.",
                    action: .respond(message: "Use the structured Codex question.")
                )
            )

            forwardedUnderstandings.append(try #require(result.understanding))
            #expect(result.messages.contains { $0.content == "Use the structured Codex question." })
        }

        let first = try #require(forwardedUnderstandings.first)
        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == first })
        #expect(first.agentIdentity == .codex)
        #expect(first.interactionState == .waitingText)
        #expect(first.interactionContext == .waitingText(question: "• Hey. What do you need help with?"))
    }

    @Test
    func kimiTransitionObservedContextKeepsStartParityAcrossLaunchPaths() async throws {
        let builder = ForemanObservedContextBuilder()
        let question = "What should I do here?"
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("kimi-transition-existing", "shell", true),
            ("kimi-transition-new-tab", "nambouchara@Nams-MacBook-Pro:~", false),
            ("kimi-transition-managed", "Kimi Code", false),
        ]

        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let current = kimiInputChromeSnapshots(
                terminalID: entry.terminalID,
                title: entry.title,
                isFocused: entry.isFocused
            ).first!
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: current.windowID,
                tabID: current.tabID,
                title: entry.title,
                cwd: current.cwd,
                isFocused: entry.isFocused,
                visibleText: """
                Welcome to Kimi Code CLI!
                Send /help for help information.

                Directory: /Users/nambouchara/speed2
                Session: abc123
                Model: Kimi-k2.6

                ── input ──────────────────────────────────────────────
                agent (Kimi-k2.6 ●)  /Users/nambouchara/speed2
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: current.runtime.foregroundProcessID,
                foregroundProcessName: "kimi",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let observedContext = builder.build(
                snapshots: [current],
                previousSnapshotsByTerminalID: [entry.terminalID: previous],
                kimiWireRecordsByTerminalID: [entry.terminalID: [kimiQuestionRecord(question: question)]]
            ).context

            let result = try await startWithObservedContextCase(
                snapshots: [current],
                observedContext: observedContext,
                response: try makeStepResponse(
                    thought: "The Kimi question is already clear.",
                    action: .respond(message: "Use the structured Kimi question.")
                )
            )

            forwardedUnderstandings.append(try #require(result.understanding))
            #expect(result.messages.contains { $0.content == "Use the structured Kimi question." })
        }

        let first = try #require(forwardedUnderstandings.first)
        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == first })
        #expect(first.agentIdentity == .kimi)
        #expect(first.interactionState == .waitingText)
        #expect(first.interactionContext == .waitingText(question: question))
    }

    @Test
    func claudeTransitionObservedContextKeepsStartParityAcrossLaunchPaths() async throws {
        let builder = ForemanObservedContextBuilder()
        let expectedContext: AgentInteractionContext = .waitingChoice(
            question: "Quick safety check: Is this a project you created or one you trust?",
            options: ["Yes, I trust this folder", "No, exit"]
        )
        let cases: [(terminalID: String, title: String, isFocused: Bool, pid: Int)] = [
            ("claude-transition-existing", "shell", true, 2101),
            ("claude-transition-new-tab", "nambouchara@Nams-MacBook-Pro:~", false, 2102),
            ("claude-transition-managed", "Claude Code", false, 2103),
        ]

        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: """
                Accessing workspace:

                /Users/nambouchara

                Quick safety check: Is this a project you created or one you trust?

                Security guide

                 ❯ 1. Yes, I trust this folder
                   2. No, exit

                 Enter to confirm · Esc to cancel
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.pid,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: "Thinking...",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.pid,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )
            let observedContext = builder.build(
                snapshots: [current],
                previousSnapshotsByTerminalID: [entry.terminalID: previous]
            ).context

            let result = try await startWithObservedContextCase(
                snapshots: [current],
                observedContext: observedContext,
                response: try makeStepResponse(
                    thought: "The Claude trust prompt is already clear.",
                    action: .respond(message: "Use the structured Claude options.")
                )
            )

            forwardedUnderstandings.append(try #require(result.understanding))
            #expect(result.messages.contains { $0.content == "Use the structured Claude options." })
        }

        let first = try #require(forwardedUnderstandings.first)
        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == first })
        #expect(first.agentIdentity == .claudeCode)
        #expect(first.interactionState == .waitingChoice)
        #expect(first.interactionContext == expectedContext)
    }

    @Test
    func startingAndStoppingConversationClearsStructuredTerminalContext() async {
        let conversation = await MainActor.run { ForemanConversation() }
        let runtimeState = await MainActor.run { conversation.runtimeState }
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
        let activeGoal = ForemanProjectGoal(
            projectID: "/tmp/project",
            objective: "Preserve this project goal."
        )

        await MainActor.run {
            runtimeState.updateTerminalContext(overview: overview, understandings: [understanding])
            runtimeState.setActiveProjectGoal(activeGoal)
            conversation.addHiddenContext("Hidden context from previous reactive event.")
            conversation.start(goal: "new session", mode: .interactive)
        }

        let clearedOnStart = await MainActor.run {
            runtimeState.lastOverview == nil &&
            runtimeState.lastUnderstandings.isEmpty &&
            runtimeState.activeProjectGoal == activeGoal &&
            conversation.hiddenContext.isEmpty
        }
        #expect(clearedOnStart)

        await MainActor.run {
            runtimeState.updateTerminalContext(overview: overview, understandings: [understanding])
            conversation.addHiddenContext("Hidden context from stopped reactive event.")
            conversation.stop()
        }

        let clearedOnStop = await MainActor.run {
            runtimeState.lastOverview == nil &&
            runtimeState.lastUnderstandings.isEmpty &&
            runtimeState.activeProjectGoal == activeGoal &&
            conversation.hiddenContext.isEmpty
        }
        #expect(clearedOnStop)
    }

    @Test
    func hiddenContextKeepsOnlyRecentEntries() async {
        let conversation = await MainActor.run { ForemanConversation() }

        await MainActor.run {
            for index in 0..<12 {
                conversation.addHiddenContext("reactive context \(index)")
            }
        }

        let hiddenContext = await MainActor.run { conversation.hiddenContext }
        #expect(hiddenContext.count == 8)
        #expect(hiddenContext.first == "reactive context 4")
        #expect(hiddenContext.last == "reactive context 11")
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
    func uiPhaseCanAwaitApprovalWithoutGoal() {
        let phase = ConversationUIPhase.resolve(
            goal: nil,
            isRunning: true,
            status: .waitingForUser,
            lastAction: .sendCommand(
                terminalID: "term-1",
                command: "1",
                reason: "Approve once"
            )
        )

        #expect(phase == .awaitingApproval(command: "1"))
    }

    @Test
    func uiPhaseTreatsAmbiguousSidebarTargetAsChoosingTarget() {
        let phase = ConversationUIPhase.resolve(
            goal: "Coordinate the waiting terminals",
            isRunning: false,
            status: .idle,
            lastAction: nil,
            resolvedTarget: .ambiguous(options: [
                .terminalReply(terminalID: "term-1", fingerprint: "fp-1", title: "term-1"),
                .project(title: "Guide Foreman"),
            ])
        )

        #expect(phase == .choosingTarget(options: [
            .terminalReply(terminalID: "term-1", fingerprint: "fp-1", title: "term-1"),
            .project(title: "Guide Foreman"),
        ]))
    }

    @Test
    func uiPhaseTreatsCompletedSidebarGoalAsCompleted() {
        let phase = ConversationUIPhase.resolve(
            goal: "Ship the sidebar",
            isRunning: false,
            status: .idle,
            lastAction: nil,
            resolvedTarget: .completedGoal(projectID: "/tmp/ghostty")
        )

        #expect(phase == .goalCompleted)
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

    @Test
    func statusDisplayTreatsCompletedGoalPhaseAsComplete() {
        let display = ConversationStatusDisplay.resolve(
            status: .idle,
            phase: .goalCompleted
        )

        #expect(display == .complete)
    }

    // MARK: - Reactive Auto-Drive Tests

    @Test
    func reactToEventRunsOneIterationAndStops() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Kimi needs approval.",
                action: AgentAction.respond(message: "Kimi is waiting for approval.")
            ),
        ])
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: CommandRecorder()
        )

        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingApproval,
            deltaText: "Allow edit to auth.ts? [y/n]",
            timestamp: Date()
        )
        await agent.react(to: event, captureSnapshots: sampleSnapshots)

        try await waitFor {
            await MainActor.run { conversation.messages.count >= 1 }
        }

        let messages = await MainActor.run { conversation.messages }
        #expect(!messages.contains { $0.role == .user && $0.content.contains("Recent output:") })
        #expect(messages.contains { $0.role == .agent && $0.content == "Kimi is waiting for approval." })
        #expect(messages.first { $0.content == "Kimi is waiting for approval." }?.terminalID == "term-1")
        let isRunning = await MainActor.run { conversation.isRunning }
        #expect(isRunning == false)
    }

    @Test
    func reactToEventDoesNotDuplicateGoalMessages() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "First reaction.",
                action: AgentAction.respond(message: "First.")
            ),
            try makeStepResponse(
                thought: "Second reaction.",
                action: AgentAction.respond(message: "Second.")
            ),
        ])
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: CommandRecorder()
        )

        let event1 = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingApproval,
            deltaText: "First approval request",
            timestamp: Date()
        )
        await agent.react(to: event1, captureSnapshots: sampleSnapshots)

        try await waitFor {
            await MainActor.run { conversation.messages.count >= 1 }
        }

        // React again to a second event
        let event2 = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            deltaText: "Second text request",
            timestamp: Date()
        )
        await agent.react(to: event2, captureSnapshots: sampleSnapshots)

        try await waitFor {
            await MainActor.run {
                conversation.messages.contains { $0.content == "Second." }
            }
        }

        let messages = await MainActor.run { conversation.messages }
        let goalMessages = messages.filter { $0.role == .user && $0.content.contains("Monitor") }
        #expect(goalMessages.isEmpty, "Should not add generic goal messages")
        #expect(!messages.contains { $0.content.contains("Error reacting to event") })
    }

    @Test
    func reactToEventStoresContextAsHiddenPromptContext() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Kimi needs a reply.",
                action: AgentAction.respond(message: "I can handle that.")
            ),
        ])
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: CommandRecorder()
        )

        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            deltaText: "User asked for a concise answer.",
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: "term-1|kimi|waitingText|concise"
        )

        await agent.react(to: event, captureSnapshots: sampleSnapshots)

        try await waitFor {
            await MainActor.run { conversation.messages.count >= 1 }
        }

        let visibleMessages = await MainActor.run { conversation.messages }
        let hiddenContext = await MainActor.run { conversation.hiddenContext }
        #expect(!visibleMessages.contains { $0.content.contains("User asked for a concise answer.") })
        #expect(hiddenContext.contains { $0.contains("User asked for a concise answer.") })
    }

    @Test
    func draftPendingAttentionForWaitingTextExposesLLMReplyWithoutSending() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(replyDrafts: [
            try makeReplyDraftResponse(
                thought: "Kimi is asking what to do next.",
                suggestion: .replyToAgent(
                    terminalID: "term-1",
                    message: "Read README.md and summarize what this project does.",
                    reason: "Kimi has entered the mend repo and is asking for the next instruction.",
                    confidence: 1.0
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            deltaText: "What would you like me to do here?",
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: "term-1|kimi|waitingText|next"
        )

        let attention = try await agent.draftPendingAttention(
            for: event,
            captureSnapshots: sampleSnapshots
        )

        let commands = await commandRecorder.recordedCommands()
        let action = try #require(attention?.actions.first)
        #expect(commands.isEmpty)
        #expect(attention?.terminalID == "term-1")
        #expect(attention?.agentIdentity == .kimi)
        #expect(attention?.interactionState == .waitingText)
        #expect(attention?.fingerprint == "term-1|kimi|waitingText|next")
        #expect(attention?.title == "Suggested reply")
        #expect(action.title == "Read README.md and summarize what this project does.")
        #expect(action.payload == "Read README.md and summarize what this project does.")
        #expect(action.style == .primary)
    }

    @Test
    func draftPendingAttentionForAskHumanDoesNotInventFallbackWorkerPrompt() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(replyDrafts: [
            try makeReplyDraftResponse(
                thought: "The agent needs a goal from the human.",
                suggestion: .askHuman(
                    terminalID: "term-1",
                    message: "What should Kimi do in the mend directory?",
                    reason: "Kimi is asking for the next task and Foreman has no active user goal.",
                    confidence: 1.0
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            deltaText: "What would you like me to do here?",
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: "term-1|kimi|waitingText|next"
        )

        let attention = try await agent.draftPendingAttention(
            for: event,
            captureSnapshots: sampleSnapshots
        )

        let commands = await commandRecorder.recordedCommands()
        #expect(commands.isEmpty)
        #expect(attention?.terminalID == "term-1")
        #expect(attention?.title == "Needs direction")
        #expect(attention?.description == "What should Kimi do in the mend directory?")
        #expect(attention?.detail == "Kimi is asking for the next task and Foreman has no active user goal.")
        #expect(attention?.actions.isEmpty == true)
    }

    @Test
    func draftPendingAttentionForNoActionReturnsNil() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(replyDrafts: [
            try makeReplyDraftResponse(
                thought: "The waiting text is not actionable.",
                suggestion: .noAction(reason: "Only welcome screen chrome is visible.", confidence: 1.0)
            ),
        ])
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: CommandRecorder()
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            deltaText: "── input ──",
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: "term-1|kimi|waitingText|chrome"
        )

        let attention = try await agent.draftPendingAttention(
            for: event,
            captureSnapshots: sampleSnapshots
        )

        #expect(attention == nil)
    }

    @Test
    func draftPendingAttentionUsesSuppliedObservedContext() async throws {
        let snapshots = kimiInputChromeSnapshots(
            terminalID: "kimi-observed",
            title: "Kimi Code",
            isFocused: true
        )
        let observedContext = kimiObservedWaitingTextContext(
            terminalID: "kimi-observed",
            snapshots: snapshots
        )
        let result = try await draftPendingAttentionCase(
            snapshots: snapshots,
            observedContext: observedContext,
            event: AgentNeedsAttentionEvent(
                terminalID: "kimi-observed",
                agentIdentity: .kimi,
                interactionState: .waitingText,
                deltaText: "── input ──",
                timestamp: Date(timeIntervalSince1970: 1),
                fingerprint: "kimi-observed|kimi|waitingText|wire"
            ),
            replyDraft: try makeReplyDraftResponse(
                thought: "Kimi is waiting for a scoped next step.",
                suggestion: .replyToAgent(
                    terminalID: "kimi-observed",
                    message: "Summarize the repository first.",
                    reason: "The current wire-aware question is specific enough to answer directly.",
                    confidence: 1.0
                )
            )
        )

        #expect(result.signature?.title == "Suggested reply")
        #expect(result.understanding?.interactionContext == .waitingText(question: "What should I do here?"))
        #expect(result.understanding?.lastMeaningfulEvent == "What should I do here?")
        #expect(result.understanding?.shortExplanation == "Kimi is waiting for your response: What should I do here?")
    }

    @Test
    func draftPendingAttentionWithObservedContextKeepsLaunchPathParity() async throws {
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("kimi-observed-existing", "shell", true),
            ("kimi-observed-new-tab", "nambouchara@Nams-MacBook-Pro:~", false),
            ("kimi-observed-managed", "Kimi Code", false),
        ]

        var signatures: [PendingAttentionSignature] = []
        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let snapshots = kimiInputChromeSnapshots(
                terminalID: entry.terminalID,
                title: entry.title,
                isFocused: entry.isFocused
            )
            let observedContext = kimiObservedWaitingTextContext(
                terminalID: entry.terminalID,
                snapshots: snapshots
            )
            let result = try await draftPendingAttentionCase(
                snapshots: snapshots,
                observedContext: observedContext,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .kimi,
                    interactionState: .waitingText,
                    deltaText: "── input ──",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|kimi|waitingText|wire"
                ),
                replyDraft: try makeReplyDraftResponse(
                    thought: "Kimi is waiting for a scoped next step.",
                    suggestion: .replyToAgent(
                        terminalID: entry.terminalID,
                        message: "Summarize the repository first.",
                        reason: "The current wire-aware question is specific enough to answer directly.",
                        confidence: 1.0
                    )
                )
            )

            signatures.append(try #require(result.signature))
            forwardedUnderstandings.append(try #require(result.understanding))
        }

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == forwardedUnderstandings.first })
        #expect(forwardedUnderstandings.first?.interactionContext == .waitingText(question: "What should I do here?"))
        #expect(forwardedUnderstandings.first?.lastMeaningfulEvent == "What should I do here?")
        #expect(signatures.first?.title == "Suggested reply")
        #expect(signatures.first?.description == "The current wire-aware question is specific enough to answer directly.")
        #expect(signatures.first?.actions.first?.title == "Summarize the repository first.")
    }

    @Test
    func draftPendingAttentionForKimiInputChromeReturnsNilAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, snapshots: [TerminalSnapshot])] = [
            ("kimi-input-existing", kimiInputChromeSnapshots(terminalID: "kimi-input-existing", title: "shell", isFocused: true)),
            ("kimi-input-new-tab", kimiInputChromeSnapshots(terminalID: "kimi-input-new-tab", title: "nambouchara@Nams-MacBook-Pro:~")),
            ("kimi-input-managed", kimiInputChromeSnapshots(terminalID: "kimi-input-managed", title: "Kimi Code")),
        ]

        for entry in cases {
            let result = try await draftPendingAttentionCase(
                snapshots: entry.snapshots,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .kimi,
                    interactionState: .waitingText,
                    deltaText: "── input ──",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|kimi|waitingText|chrome"
                ),
                replyDraft: try makeReplyDraftResponse(
                    thought: "The waiting text is not actionable.",
                    suggestion: .noAction(reason: "Only welcome screen chrome is visible.", confidence: 1.0)
                )
            )

            #expect(result.signature == nil)
            #expect(result.understanding?.interactionState == .waitingText)
            #expect(result.understanding?.interactionContext == .waitingText(question: nil))
        }
    }

    @Test
    func draftPendingAttentionForGenericCodexWireContextReturnsNilAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("codex-wire-existing", "shell", true),
            ("codex-wire-new-tab", "nambouchara@Nams-MacBook-Pro:~", false),
            ("codex-wire-managed", "Codex", false),
        ]

        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let snapshots = genericCodexWireSnapshots(
                terminalID: entry.terminalID,
                title: entry.title,
                isFocused: entry.isFocused
            )
            let observedContext = genericCodexWireObservedContext(
                terminalID: entry.terminalID,
                title: entry.title,
                isFocused: entry.isFocused
            )
            let deltaText = observedContext.understandings.first?.lastMeaningfulEvent ?? "codex"
            let result = try await draftPendingAttentionCase(
                snapshots: snapshots,
                observedContext: observedContext,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .codex,
                    interactionState: .waitingText,
                    deltaText: deltaText,
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|codex|waitingText|wire-generic"
                ),
                replyDraft: try makeReplyDraftResponse(
                    thought: "This Codex waiting state has no actionable question yet.",
                    suggestion: .noAction(
                        reason: "Codex has not asked a concrete question.",
                        confidence: 1.0
                    )
                )
            )

            #expect(result.signature == nil)
            forwardedUnderstandings.append(try #require(result.understanding))
        }

        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == forwardedUnderstandings.first })
        #expect(forwardedUnderstandings.first?.agentIdentity == .codex)
        #expect(forwardedUnderstandings.first?.interactionState == .waitingText)
        #expect(forwardedUnderstandings.first?.interactionContext == .waitingText(question: nil))
    }

    @Test
    func draftPendingAttentionForGenericClaudeWireContextReturnsNilAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("claude-wire-existing", "shell", true),
            ("claude-wire-new-tab", "nambouchara@Nams-MacBook-Pro:~", false),
            ("claude-wire-managed", "Claude", false),
        ]

        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let snapshots = genericClaudeWireSnapshots(
                terminalID: entry.terminalID,
                title: entry.title,
                isFocused: entry.isFocused
            )
            let observedContext = genericClaudeWireObservedContext(
                terminalID: entry.terminalID,
                title: entry.title,
                isFocused: entry.isFocused
            )
            let deltaText = observedContext.understandings.first?.lastMeaningfulEvent ?? "claude"
            let result = try await draftPendingAttentionCase(
                snapshots: snapshots,
                observedContext: observedContext,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .claudeCode,
                    interactionState: .waitingText,
                    deltaText: deltaText,
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|claude|waitingText|wire-generic"
                ),
                replyDraft: try makeReplyDraftResponse(
                    thought: "This Claude waiting state has no actionable question yet.",
                    suggestion: .noAction(
                        reason: "Claude has not asked a concrete question.",
                        confidence: 1.0
                    )
                )
            )

            #expect(result.signature == nil)
            forwardedUnderstandings.append(try #require(result.understanding))
        }

        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == forwardedUnderstandings.first })
        #expect(forwardedUnderstandings.first?.agentIdentity == .claudeCode)
        #expect(forwardedUnderstandings.first?.interactionState == .waitingText)
        #expect(forwardedUnderstandings.first?.interactionContext == .waitingText(question: nil))
    }

    @Test
    func draftPendingAttentionForKimiRepliesSharesParityAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, snapshots: [TerminalSnapshot])] = [
            ("kimi-existing", kimiReplySnapshots(terminalID: "kimi-existing", title: "shell", isFocused: true)),
            ("kimi-new-tab", kimiReplySnapshots(terminalID: "kimi-new-tab", title: "nambouchara@Nams-MacBook-Pro:~")),
            ("kimi-managed", kimiReplySnapshots(terminalID: "kimi-managed", title: "Kimi Code")),
        ]

        var signatures: [PendingAttentionSignature] = []
        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let result = try await draftPendingAttentionCase(
                snapshots: entry.snapshots,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .kimi,
                    interactionState: .waitingText,
                    deltaText: "What would you like me to do here?",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|kimi|waitingText|next"
                ),
                replyDraft: try makeReplyDraftResponse(
                    thought: "Kimi is asking what to do next.",
                    suggestion: .replyToAgent(
                        terminalID: entry.terminalID,
                        message: "Read README.md and summarize what this project does.",
                        reason: "Kimi has entered the mend repo and is asking for the next instruction.",
                        confidence: 1.0
                    )
                )
            )

            signatures.append(try #require(result.signature))
            forwardedUnderstandings.append(try #require(result.understanding))
        }

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == forwardedUnderstandings.first })
        #expect(signatures.first?.title == "Suggested reply")
        #expect(signatures.first?.description == "Kimi has entered the mend repo and is asking for the next instruction.")
        #expect(signatures.first?.detail == "What would you like me to do here?")
        #expect(signatures.first?.actions.first?.title == "Read README.md and summarize what this project does.")
        #expect(forwardedUnderstandings.first?.interactionState == .waitingText)
        #expect(forwardedUnderstandings.first?.interactionContext == .waitingText(question: "What would you like me to do here?"))
    }

    @Test
    func draftPendingAttentionForKimiAskHumanSharesParityAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, snapshots: [TerminalSnapshot])] = [
            ("kimi-existing", kimiReplySnapshots(terminalID: "kimi-existing", title: "shell", isFocused: true)),
            ("kimi-new-tab", kimiReplySnapshots(terminalID: "kimi-new-tab", title: "nambouchara@Nams-MacBook-Pro:~")),
            ("kimi-managed", kimiReplySnapshots(terminalID: "kimi-managed", title: "Kimi Code")),
        ]
        let projectGoal = "Coordinate the next Foreman goal-runtime slice across agent terminals."
        let runtime = ForemanProjectGoalRuntime()
        await runtime.saveGoal(projectGoal, for: "/Users/nambouchara/speed2")

        var signatures: [PendingAttentionSignature] = []

        for entry in cases {
            let result = try await draftPendingAttentionCase(
                snapshots: entry.snapshots,
                observedContext: nil,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .kimi,
                    interactionState: .waitingText,
                    deltaText: "What would you like me to do here?",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|kimi|waitingText|next"
                ),
                replyDraft: try makeReplyDraftResponse(
                    thought: "The agent needs a goal from the human.",
                    suggestion: .askHuman(
                        terminalID: entry.terminalID,
                        message: "What should Kimi do in the mend directory?",
                        reason: "Kimi is asking for the next task and Foreman has no active user goal.",
                        confidence: 1.0
                    )
                ),
                goalRuntime: runtime
            )

            signatures.append(try #require(result.signature))
        }

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.title == "Needs direction")
        #expect(signatures.first?.description == "What should Kimi do in the mend directory?")
        #expect(signatures.first?.detail == "Kimi is asking for the next task and Foreman has no active user goal.")
        #expect(signatures.first?.actions.isEmpty == true)
    }

    @Test
    func draftPendingAttentionForCodexAuthoritativeReplyEscalatesWithoutLLMDraftAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, snapshots: [TerminalSnapshot])] = [
            ("codex-existing", codexReplySnapshots(terminalID: "codex-existing", title: "shell", isFocused: true)),
            ("codex-new-tab", codexReplySnapshots(terminalID: "codex-new-tab", title: "nambouchara@Nams-MacBook-Pro:~")),
            ("codex-managed", codexReplySnapshots(terminalID: "codex-managed", title: "OpenAI Codex")),
        ]

        var signatures: [PendingAttentionSignature] = []
        var draftCallCounts: [Int] = []

        for entry in cases {
            let result = try await draftPendingAttentionCase(
                snapshots: entry.snapshots,
                observedContext: nil,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .codex,
                    interactionState: .waitingText,
                    deltaText: "What should I work on next?",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|codex|waitingText|next"
                ),
                replyDraft: nil
            )

            signatures.append(try #require(result.signature))
            draftCallCounts.append(result.replyDraftCallCount)
        }

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(draftCallCounts.allSatisfy { $0 == 0 })
        #expect(signatures.first?.title == "Needs direction")
        #expect(signatures.first?.description == "• Hello. What do you want to work on in ghostty?")
        #expect(signatures.first?.detail == nil)
        #expect(signatures.first?.actions.isEmpty == true)
    }

    @Test
    func draftPendingAttentionForCompletedGoalSuppressesRecommendationsAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, snapshots: [TerminalSnapshot])] = [
            ("codex-complete-existing", codexReplySnapshots(terminalID: "codex-complete-existing", title: "shell", isFocused: true)),
            ("codex-complete-new-tab", codexReplySnapshots(terminalID: "codex-complete-new-tab", title: "nambouchara@Nams-MacBook-Pro:~")),
            ("codex-complete-managed", codexReplySnapshots(terminalID: "codex-complete-managed", title: "OpenAI Codex")),
        ]
        let runtime = ForemanProjectGoalRuntime()
        await runtime.saveGoal("Ship the goal evaluator.", for: "/tmp/project")
        await runtime.recordEvaluation(
            .init(
                progress: .completed,
                evidenceSnapshot: "Codex completed the evaluator slice and the project goal looks done.",
                evaluatedAt: Date(timeIntervalSince1970: 10)
            ),
            for: "/tmp/project"
        )

        var signatures: [PendingAttentionSignature] = []

        for entry in cases {
            let conversation = await MainActor.run { ForemanConversation() }
            let client = ScriptedForemanClient(replyDrafts: [
                try makeReplyDraftResponse(
                    thought: "This should never be drafted once the goal is complete.",
                    suggestion: .replyToAgent(
                        terminalID: entry.terminalID,
                        message: "Keep going.",
                        reason: "This should not be used.",
                        confidence: 1.0
                    )
                ),
            ])
            let commandRecorder = CommandRecorder()
            let agent = makeAgent(
                conversation: conversation,
                client: client,
                commandRecorder: commandRecorder,
                goalRuntime: runtime,
                preferredTerminalID: entry.terminalID
            )

            let attention = try await agent.draftPendingAttention(
                for: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .codex,
                    interactionState: .waitingText,
                    deltaText: "What should I work on next?",
                    timestamp: Date(timeIntervalSince1970: 11),
                    fingerprint: "\(entry.terminalID)|codex|waitingText|complete"
                ),
                captureSnapshots: { entry.snapshots }
            )

            signatures.append(try #require(pendingAttentionSignature(attention)))
            let draftCalls = await client.replyDraftCallCount()
            #expect(draftCalls == 0)
        }

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.title == "Goal complete")
        #expect(signatures.first?.description.contains("continue") == true)
        #expect(signatures.first?.description.contains("close") == true)
        #expect(signatures.first?.detail?.contains("/goal reopen") == true)
        #expect(signatures.first?.detail?.contains("/goal clear") == true)
        #expect(signatures.first?.actions.isEmpty == true)
    }

    @Test
    func draftPendingAttentionForCompletedGoalSuppressesAuthoritativeWorkerAttention() async throws {
        let runtime = ForemanProjectGoalRuntime()
        await runtime.saveGoal("Ship the goal evaluator.", for: "/tmp/project")
        await runtime.recordEvaluation(
            .init(
                progress: .completed,
                evidenceSnapshot: "Codex finished the evaluator slice and the project goal is done.",
                evaluatedAt: Date(timeIntervalSince1970: 10)
            ),
            for: "/tmp/project"
        )

        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(replyDrafts: [
            try makeReplyDraftResponse(
                thought: "This should never be drafted once the goal is complete.",
                suggestion: .replyToAgent(
                    terminalID: "term-1",
                    message: "Keep going.",
                    reason: "This should not be used.",
                    confidence: 1.0
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder,
            goalRuntime: runtime,
            preferredTerminalID: "term-1"
        )

        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Should I preserve the API?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex"
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
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "Should I preserve the API?",
            importantDetails: [],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            workerSnapshot: workerSnapshot
        )

        let attention = try await agent.draftPendingAttention(
            for: AgentNeedsAttentionEvent(
                terminalID: "term-1",
                agentIdentity: .codex,
                interactionState: .waitingText,
                deltaText: "Should I preserve the API?",
                timestamp: Date(timeIntervalSince1970: 11),
                fingerprint: "term-1|codex|waitingText|complete-authoritative"
            ),
            observedContext: ForemanObservedTerminalContext(
                terminals: [snapshot],
                understandings: [understanding],
                workerSnapshots: ["term-1": workerSnapshot]
            ),
            captureSnapshots: { [snapshot] }
        )

        let signature = try #require(pendingAttentionSignature(attention))
        #expect(signature.title == "Goal complete")
        #expect(signature.description.contains("continue") == true)
        #expect(signature.description.contains("close") == true)
        #expect(signature.detail?.contains("/goal reopen") == true)
        #expect(signature.detail?.contains("/goal clear") == true)
        #expect(signature.actions.isEmpty == true)
        let draftCalls = await client.replyDraftCallCount()
        #expect(draftCalls == 0)
    }

    @Test
    func draftPendingAttentionAskHumanKeepsGoalActiveAndStoresEvidenceAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, snapshots: [TerminalSnapshot])] = [
            ("codex-blocked-existing", codexReplySnapshots(terminalID: "codex-blocked-existing", title: "shell", isFocused: true)),
            ("codex-blocked-new-tab", codexReplySnapshots(terminalID: "codex-blocked-new-tab", title: "nambouchara@Nams-MacBook-Pro:~")),
            ("codex-blocked-managed", codexReplySnapshots(terminalID: "codex-blocked-managed", title: "OpenAI Codex")),
        ]
        let projectGoal = "Coordinate the next goal-runtime slice."
        let runtime = ForemanProjectGoalRuntime()
        await runtime.saveGoal(projectGoal, for: "/tmp/project")

        var signatures: [PendingAttentionSignature] = []

        for entry in cases {
            let result = try await draftPendingAttentionCase(
                snapshots: entry.snapshots,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .codex,
                    interactionState: .waitingText,
                    deltaText: "What should I work on next?",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|codex|waitingText|blocked"
                ),
                replyDraft: nil,
                goalRuntime: runtime
            )

            signatures.append(try #require(result.signature))
        }

        let goal = await runtime.goal(for: "/tmp/project")

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.title == "Needs direction")
        #expect(signatures.first?.description == "• Hello. What do you want to work on in ghostty?")
        #expect(signatures.first?.actions.isEmpty == true)
        #expect(goal?.status == .active)
        #expect(goal?.completedAt == nil)
        #expect(goal?.lastEvaluatedAt != nil)
        #expect(goal?.lastEvidenceSnapshot?.contains("waiting for direction") == true)
    }

    @Test
    func draftPendingAttentionForClaudeAuthoritativeReplyEscalatesWithoutLLMDraftAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, snapshots: [TerminalSnapshot])] = [
            ("claude-existing", claudeReplySnapshots(terminalID: "claude-existing", title: "shell", isFocused: true)),
            ("claude-new-tab", claudeReplySnapshots(terminalID: "claude-new-tab", title: "nambouchara@Nams-MacBook-Pro:~")),
            ("claude-managed", claudeReplySnapshots(terminalID: "claude-managed", title: "Claude Code")),
        ]

        var signatures: [PendingAttentionSignature] = []
        var draftCallCounts: [Int] = []

        for entry in cases {
            let result = try await draftPendingAttentionCase(
                snapshots: entry.snapshots,
                observedContext: nil,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .claudeCode,
                    interactionState: .waitingText,
                    deltaText: "What should I do next?",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|claude|waitingText|next"
                ),
                replyDraft: nil
            )

            signatures.append(try #require(result.signature))
            draftCallCounts.append(result.replyDraftCallCount)
        }

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(draftCallCounts.allSatisfy { $0 == 0 })
        #expect(signatures.first?.title == "Needs direction")
        #expect(signatures.first?.description == "What should I do next?")
        #expect(signatures.first?.detail == nil)
        #expect(signatures.first?.actions.isEmpty == true)
    }

    @Test
    func draftPendingAttentionForCodexFirstClassRepliesDoNotInventSuggestedResponseAcrossLaunchPaths() async throws {
        let cases: [(terminalID: String, snapshots: [TerminalSnapshot])] = [
            ("codex-existing", codexReplySnapshots(terminalID: "codex-existing", title: "shell", isFocused: true)),
            ("codex-new-tab", codexReplySnapshots(terminalID: "codex-new-tab", title: "nambouchara@Nams-MacBook-Pro:~")),
            ("codex-managed", codexReplySnapshots(terminalID: "codex-managed", title: "OpenAI Codex")),
        ]

        var signatures: [PendingAttentionSignature] = []
        var draftCallCounts: [Int] = []

        for entry in cases {
            let result = try await draftPendingAttentionCase(
                snapshots: entry.snapshots,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .codex,
                    interactionState: .waitingText,
                    deltaText: "What should I work on next?",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|codex|waitingText|next"
                )
            )

            signatures.append(try #require(result.signature))
            draftCallCounts.append(result.replyDraftCallCount)
        }

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(draftCallCounts.allSatisfy { $0 == 0 })
        #expect(signatures.first?.title == "Needs direction")
        #expect(signatures.first?.description == "• Hello. What do you want to work on in ghostty?")
        #expect(signatures.first?.detail == nil)
        #expect(signatures.first?.actions.isEmpty == true)
    }

    @Test
    func reactiveIterationUsesSuppliedObservedContext() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "The question is already clear from the structured context.",
                action: .respond(message: "Use the structured waiting question.")
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let snapshots = kimiInputChromeSnapshots(
            terminalID: "kimi-reactive",
            title: "Kimi Code",
            isFocused: true
        )
        let observedContext = kimiObservedWaitingTextContext(
            terminalID: "kimi-reactive",
            snapshots: snapshots
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "kimi-reactive",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            deltaText: "── input ──",
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: "kimi-reactive|kimi|waitingText|wire"
        )

        await agent.react(
            to: event,
            observedContext: observedContext,
            captureSnapshots: { snapshots }
        )

        try await waitFor {
            await MainActor.run { conversation.messages.contains { $0.content == "Use the structured waiting question." } }
        }

        let payloads = await client.recordedUnderstandings()
        let forwarded = try #require(payloads.first?.first)
        #expect(forwarded.agentInteractionContext == .waitingText(question: "What should I do here?"))
        #expect(forwarded.lastMeaningfulEvent == "What should I do here?")
        let runtimeState = await MainActor.run { conversation.runtimeState }
        let lastUnderstandings = await MainActor.run { runtimeState.lastUnderstandings }
        #expect(lastUnderstandings.first?.agentInteractionContext == .waitingText(question: "What should I do here?"))
    }

    @Test
    func reactiveObservedContextKeepsLaunchPathParity() async throws {
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("kimi-reactive-existing", "shell", true),
            ("kimi-reactive-new-tab", "nambouchara@Nams-MacBook-Pro:~", false),
            ("kimi-reactive-managed", "Kimi Code", false),
        ]

        var forwardedUnderstandings: [UnderstandingSignature] = []

        for entry in cases {
            let snapshots = kimiInputChromeSnapshots(
                terminalID: entry.terminalID,
                title: entry.title,
                isFocused: entry.isFocused
            )
            let observedContext = kimiObservedWaitingTextContext(
                terminalID: entry.terminalID,
                snapshots: snapshots
            )
            let result = try await reactiveIterationCase(
                snapshots: snapshots,
                observedContext: observedContext,
                event: AgentNeedsAttentionEvent(
                    terminalID: entry.terminalID,
                    agentIdentity: .kimi,
                    interactionState: .waitingText,
                    deltaText: "── input ──",
                    timestamp: Date(timeIntervalSince1970: 1),
                    fingerprint: "\(entry.terminalID)|kimi|waitingText|wire"
                ),
                response: try makeStepResponse(
                    thought: "The question is already clear from the structured context.",
                    action: .respond(message: "Use the structured waiting question.")
                )
            )

            forwardedUnderstandings.append(try #require(result.understanding))
        }

        #expect(forwardedUnderstandings.dropFirst().allSatisfy { $0 == forwardedUnderstandings.first })
        #expect(forwardedUnderstandings.first?.interactionContext == .waitingText(question: "What should I do here?"))
        #expect(forwardedUnderstandings.first?.lastMeaningfulEvent == "What should I do here?")
    }

    @Test
    func reactAutonomousModeExecutesCommandDirectly() async throws {
        let conversation = await MainActor.run {
            let c = ForemanConversation()
            c.mode = .autonomous
            return c
        }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Terminal needs a command.",
                action: AgentAction.sendCommand(terminalID: "term-1", command: "yes", reason: "Approve Kimi's edit.")
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingApproval,
            deltaText: "Allow edit to auth.ts? [y/n]",
            timestamp: Date()
        )
        await agent.react(to: event, captureSnapshots: sampleSnapshots)

        try await waitFor {
            let commands = await commandRecorder.recordedCommands()
            return commands.contains { $0.terminalID == "term-1" && $0.command == "yes" }
        }

        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.role == .agent && $0.content == "▶️ Sent: yes" })
    }

    @Test
    func reactAutonomousModePausesWhenWorkerSnapshotIsPlanning() async throws {
        let conversation = await MainActor.run {
            let c = ForemanConversation()
            c.mode = .autonomous
            return c
        }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Kimi already suggested the safest option.",
                action: AgentAction.sendCommand(
                    terminalID: "term-1",
                    command: "1",
                    reason: "Choose Keep current API."
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let observedContext = choiceObservedContext(
            isPlanning: true,
            execution: .autonomousOK
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingChoice,
            deltaText: "Which direction should I take?",
            timestamp: Date()
        )

        await agent.react(
            to: event,
            observedContext: observedContext,
            captureSnapshots: { observedContext.terminals }
        )

        try await waitForStatus(.waitingForUser, in: conversation)

        let commands = await commandRecorder.recordedCommands()
        #expect(commands.isEmpty)

        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.role == .agent && $0.content == ForemanRuntimePolicy.planModeMessage })
    }

    @Test
    func reactAutonomousModePausesWhenWorkerSuggestionNeedsManualReview() async throws {
        let conversation = await MainActor.run {
            let c = ForemanConversation()
            c.mode = .autonomous
            return c
        }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Kimi suggested the safest option.",
                action: AgentAction.sendCommand(
                    terminalID: "term-1",
                    command: "1",
                    reason: "Choose Keep current API."
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let observedContext = choiceObservedContext(
            isPlanning: false,
            execution: .manualOnly
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingChoice,
            deltaText: "Which direction should I take?",
            timestamp: Date()
        )

        await agent.react(
            to: event,
            observedContext: observedContext,
            captureSnapshots: { observedContext.terminals }
        )

        try await waitForStatus(.waitingForUser, in: conversation)

        let commands = await commandRecorder.recordedCommands()
        #expect(commands.isEmpty)

        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.role == .agent && $0.content == ForemanRuntimePolicy.manualReviewMessage })
    }

    @Test
    func reactAutonomousModeExecutesWorkerAuthorizedSuggestion() async throws {
        let conversation = await MainActor.run {
            let c = ForemanConversation()
            c.mode = .autonomous
            return c
        }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Kimi already suggested the safest option.",
                action: AgentAction.sendCommand(
                    terminalID: "term-1",
                    command: "1",
                    reason: "Choose Keep current API."
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let observedContext = choiceObservedContext(
            isPlanning: false,
            execution: .autonomousOK
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingChoice,
            deltaText: "Which direction should I take?",
            timestamp: Date()
        )

        await agent.react(
            to: event,
            observedContext: observedContext,
            captureSnapshots: { observedContext.terminals }
        )

        try await waitFor {
            let commands = await commandRecorder.recordedCommands()
            return commands.contains { $0.terminalID == "term-1" && $0.command == "1" }
        }

        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.role == .agent && $0.content == "▶️ Sent: 1" })
    }

    @Test
    func startInteractiveModeUsesWorkerSuggestionWithoutPlannerCall() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Foreman should not need to plan this.",
                action: AgentAction.sendCommand(
                    terminalID: "term-1",
                    command: "1",
                    reason: "Choose Keep current API."
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )
        let observedContext = choiceObservedContext(
            isPlanning: false,
            execution: .manualOnly
        )

        await agent.start(
            goal: "Continue the worker.",
            mode: .interactive,
            captureSnapshots: { observedContext.terminals },
            captureObservedContext: { observedContext }
        )

        try await waitForStatus(.waitingForUser, in: conversation)

        let commands = await commandRecorder.recordedCommands()
        #expect(commands.isEmpty)
        #expect(await client.agentStepCallCount() == 0)
    }

    @Test
    func startInteractiveModeUsesWorkerSuggestionWithoutSynthesizingForemanAction() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Foreman should not need to plan this.",
                action: AgentAction.sendCommand(
                    terminalID: "term-1",
                    command: "1",
                    reason: "Choose Keep current API."
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let actionRecorder = ActionRecorder()
        let observedContext = choiceObservedContext(
            isPlanning: false,
            execution: .manualOnly
        )
        let service = ForemanService(client: client)
        let agent = ForemanAgent(
            conversation: conversation,
            foremanService: service,
            goalRuntime: ForemanProjectGoalRuntime(),
            onSendCommand: { terminalID, command in
                await commandRecorder.record(terminalID: terminalID, command: command)
                return true
            },
            onStatusChange: { _ in },
            onAction: { action, thought in
                Task {
                    await actionRecorder.record(action: action, thought: thought)
                }
            }
        )

        await agent.start(
            goal: "Continue the worker.",
            mode: .interactive,
            captureSnapshots: { observedContext.terminals },
            captureObservedContext: { observedContext }
        )

        try await waitForStatus(.waitingForUser, in: conversation)

        let commands = await commandRecorder.recordedCommands()
        #expect(commands.isEmpty)
        #expect(await client.agentStepCallCount() == 0)
        #expect(await actionRecorder.recordedActions().isEmpty)
    }

    @Test
    func startAutonomousModeUsesWorkerSuggestionWithoutPlannerCall() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Foreman should not need to plan this.",
                action: AgentAction.sendCommand(
                    terminalID: "term-1",
                    command: "1",
                    reason: "Choose Keep current API."
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let initialContext = choiceObservedContext(
            isPlanning: false,
            execution: .autonomousOK
        )
        let followupContext = runningObservedContextAfterSuggestedChoice()
        let contextSource = await MainActor.run {
            MutableObservedContextSource(initialContext)
        }
        let service = ForemanService(client: client)
        let agent = ForemanAgent(
            conversation: conversation,
            foremanService: service,
            goalRuntime: ForemanProjectGoalRuntime(),
            onSendCommand: { terminalID, command in
                await commandRecorder.record(terminalID: terminalID, command: command)
                contextSource.current = followupContext
                return true
            },
            onStatusChange: { _ in },
            onAction: { _, _ in }
        )

        await agent.start(
            goal: "Continue the worker.",
            mode: .autonomous,
            captureSnapshots: { contextSource.current.terminals },
            captureObservedContext: { contextSource.current }
        )

        try await waitFor {
            let commands = await commandRecorder.recordedCommands()
            let isRunning = await MainActor.run { conversation.isRunning }
            return commands.contains { $0.terminalID == "term-1" && $0.command == "1" } && !isRunning
        }

        #expect(await client.agentStepCallCount() == 0)
    }

    @Test
    func startAutonomousModeUsesWorkerSuggestionWithoutSynthesizingForemanAction() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Foreman should not need to plan this.",
                action: AgentAction.sendCommand(
                    terminalID: "term-1",
                    command: "1",
                    reason: "Choose Keep current API."
                )
            ),
        ])
        let commandRecorder = CommandRecorder()
        let actionRecorder = ActionRecorder()
        let initialContext = choiceObservedContext(
            isPlanning: false,
            execution: .autonomousOK
        )
        let followupContext = runningObservedContextAfterSuggestedChoice()
        let contextSource = await MainActor.run {
            MutableObservedContextSource(initialContext)
        }
        let service = ForemanService(client: client)
        let agent = ForemanAgent(
            conversation: conversation,
            foremanService: service,
            goalRuntime: ForemanProjectGoalRuntime(),
            onSendCommand: { terminalID, command in
                await commandRecorder.record(terminalID: terminalID, command: command)
                contextSource.current = followupContext
                return true
            },
            onStatusChange: { _ in },
            onAction: { action, thought in
                Task {
                    await actionRecorder.record(action: action, thought: thought)
                }
            }
        )

        await agent.start(
            goal: "Continue the worker.",
            mode: .autonomous,
            captureSnapshots: { contextSource.current.terminals },
            captureObservedContext: { contextSource.current }
        )

        try await waitFor {
            let commands = await commandRecorder.recordedCommands()
            let isRunning = await MainActor.run { conversation.isRunning }
            return commands.contains { $0.terminalID == "term-1" && $0.command == "1" } && !isRunning
        }

        #expect(await client.agentStepCallCount() == 0)
        #expect(await actionRecorder.recordedActions().isEmpty)
    }

    @Test
    func reactInteractiveModePausesForApproval() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = ScriptedForemanClient(responses: [
            try makeStepResponse(
                thought: "Terminal needs a command.",
                action: AgentAction.sendCommand(terminalID: "term-1", command: "yes", reason: "Approve Kimi's edit.")
            ),
        ])
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingApproval,
            deltaText: "Allow edit to auth.ts? [y/n]",
            timestamp: Date()
        )
        await agent.react(to: event, captureSnapshots: sampleSnapshots)

        try await waitForStatus(.waitingForUser, in: conversation)

        let commands = await commandRecorder.recordedCommands()
        #expect(commands.isEmpty)

        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.role == .agent && $0.content == "Approve Kimi's edit." })
        #expect(messages.first { $0.content == "Approve Kimi's edit." }?.terminalID == "term-1")
    }

    @Test
    func genericUserMessageDoesNotReopenCompletedGoal() async throws {
        let runtime = ForemanProjectGoalRuntime()
        await runtime.saveGoal("Ship the evaluator slice.", for: "/tmp/project")
        await runtime.recordEvaluation(
            .init(
                progress: .completed,
                evidenceSnapshot: "The evaluator is already complete.",
                evaluatedAt: Date(timeIntervalSince1970: 20)
            ),
            for: "/tmp/project"
        )
        let completedGoal = try #require(await runtime.goal(for: "/tmp/project"))
        let conversation = await MainActor.run {
            let c = ForemanConversation()
            c.goal = completedGoal.goalText
            c.setActiveProjectGoal(completedGoal)
            return c
        }
        let client = ScriptedForemanClient()
        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder,
            goalRuntime: runtime
        )

        await agent.receiveUserMessage("continue")

        let persistedGoal = await runtime.goal(for: "/tmp/project")
        #expect(persistedGoal?.status == .completed)
        let runtimeState = await MainActor.run { conversation.runtimeState }
        #expect(await MainActor.run { runtimeState.activeProjectGoal?.status } == .completed)
    }

    @Test
    func draftPendingAttentionUsesWorkerSuggestionBeforeLLMReplyDraft() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let client = FastPathRecordingForemanClient()
        let service = ForemanService(client: client)
        let commandRecorder = CommandRecorder()
        let runtime = ForemanProjectGoalRuntime()
        let agent = ForemanAgent(
            conversation: conversation,
            foremanService: service,
            goalRuntime: runtime,
            preferredTerminalID: "term-1",
            onSendCommand: { terminalID, command in
                await commandRecorder.record(terminalID: terminalID, command: command)
                return true
            },
            onStatusChange: { _ in },
            onAction: { _, _ in }
        )

        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            deltaText: "Should I preserve the API?",
            timestamp: Date(),
            fingerprint: "codex-session-1|7|req-7"
        )
        let terminalSnapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex",
            cwd: "/tmp/repo",
            isFocused: true,
            visibleText: "Should I preserve the API?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex"
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
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "Should I preserve the API?",
            importantDetails: [],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            workerSnapshot: workerSnapshot
        )

        let attention = try await agent.draftPendingAttention(
            for: event,
            observedContext: ForemanObservedTerminalContext(
                terminals: [terminalSnapshot],
                understandings: [understanding],
                workerSnapshots: ["term-1": workerSnapshot]
            ),
            captureSnapshots: { [terminalSnapshot] }
        )

        #expect(attention?.actions.first?.title == "Preserve the API")
        #expect(await client.draftReplyCallCount == 0)
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

private func makeReplyDraftResponse(
    thought: String,
    suggestion: AgentReplyDraftSuggestion
) throws -> AgentReplyDraftResponse {
    struct DraftEnvelope: Encodable {
        let thought: String
        let suggestion: AgentReplyDraftSuggestion
    }

    let data = try JSONEncoder().encode(DraftEnvelope(thought: thought, suggestion: suggestion))
    return try JSONDecoder().decode(AgentReplyDraftResponse.self, from: data)
}

private func makeAgent(
    conversation: ForemanConversation,
    client: ScriptedForemanClient,
    commandRecorder: CommandRecorder,
    goalRuntime: ForemanProjectGoalRuntime = ForemanProjectGoalRuntime(),
    preferredTerminalID: String? = nil
) -> ForemanAgent {
    let service = ForemanService(client: client)
    return ForemanAgent(
        conversation: conversation,
        foremanService: service,
        goalRuntime: goalRuntime,
        preferredTerminalID: preferredTerminalID,
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
private func runningKimiSnapshots() -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            • The user asked me to finish the analysis. I am reading the project and preparing the final answer.
            ⠋ Using WriteFile (mend/docs/generalization-analysis.md)

            agent (Kimi-k2.6 *) ~/speed2
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
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

@MainActor
private func successfulTestSnapshots() -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "npm test\nuser@host %",
            recentScrollbackLines: [
                "npm test",
                "user@host %",
            ],
            lastInputPreview: "npm test"
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

private actor ActionRecorder {
    struct RecordedAction: Equatable, Sendable {
        let action: AgentAction
        let thought: String
    }

    private var actions: [RecordedAction] = []

    func record(action: AgentAction, thought: String) {
        actions.append(.init(action: action, thought: thought))
    }

    func recordedActions() -> [RecordedAction] {
        actions
    }
}

private func pendingAttentionSignature(_ attention: PendingAgentAttention?) -> ForemanAgentTests.PendingAttentionSignature? {
    guard let attention else { return nil }
    return .init(
        agentIdentity: attention.agentIdentity,
        interactionState: attention.interactionState,
        title: attention.title,
        description: attention.description,
        detail: attention.detail,
        actions: attention.actions,
        status: attention.status,
        errorMessage: attention.errorMessage
    )
}

private func understandingSignature(_ understanding: TerminalUnderstanding?) -> ForemanAgentTests.UnderstandingSignature? {
    guard let understanding else { return nil }
    return .init(
        state: understanding.state,
        agentIdentity: understanding.agentIdentity,
        interactionState: understanding.agentInteractionState,
        supportLevel: understanding.supportLevel,
        lastMeaningfulEvent: understanding.lastMeaningfulEvent,
        shortExplanation: understanding.shortExplanation,
        importantDetails: understanding.importantDetails,
        suggestedNextActions: understanding.suggestedNextActions,
        interactionContext: understanding.agentInteractionContext
    )
}

private func draftPendingAttentionCase(
    snapshots: [TerminalSnapshot],
    observedContext: ForemanObservedTerminalContext? = nil,
    event: AgentNeedsAttentionEvent,
    replyDraft: AgentReplyDraftResponse? = nil,
    goalRuntime: ForemanProjectGoalRuntime = ForemanProjectGoalRuntime()
) async throws -> (
    signature: ForemanAgentTests.PendingAttentionSignature?,
    understanding: ForemanAgentTests.UnderstandingSignature?,
    replyDraftCallCount: Int
) {
    let conversation = await MainActor.run { ForemanConversation() }
    let client = ScriptedForemanClient(replyDrafts: replyDraft.map { [$0] } ?? [])
    let commandRecorder = CommandRecorder()
    let agent = makeAgent(
        conversation: conversation,
        client: client,
        commandRecorder: commandRecorder,
        goalRuntime: goalRuntime,
        preferredTerminalID: event.terminalID
    )

    let attention = try await agent.draftPendingAttention(
        for: event,
        observedContext: observedContext,
        captureSnapshots: { snapshots }
    )

    let commands = await commandRecorder.recordedCommands()
    #expect(commands.isEmpty)
    let understandings = await client.recordedUnderstandings()
    let replyDraftCallCount = await client.replyDraftCallCount()

    return (
        signature: pendingAttentionSignature(attention),
        understanding: understandingSignature(understandings.first?.first),
        replyDraftCallCount: replyDraftCallCount
    )
}

private func reactiveIterationCase(
    snapshots: [TerminalSnapshot],
    observedContext: ForemanObservedTerminalContext? = nil,
    event: AgentNeedsAttentionEvent,
    response: AgentStepResponse
) async throws -> (
    understanding: ForemanAgentTests.UnderstandingSignature?,
    messages: [ConversationMessage]
) {
    let conversation = await MainActor.run { ForemanConversation() }
    let client = ScriptedForemanClient(responses: [response])
    let commandRecorder = CommandRecorder()
    let agent = makeAgent(
        conversation: conversation,
        client: client,
        commandRecorder: commandRecorder
    )

    await agent.react(
        to: event,
        observedContext: observedContext,
        captureSnapshots: { snapshots }
    )

    try await waitFor {
        let payloads = await client.recordedUnderstandings()
        return !payloads.isEmpty
    }

    let commands = await commandRecorder.recordedCommands()
    #expect(commands.isEmpty)
    let understandings = await client.recordedUnderstandings()
    let messages = await MainActor.run { conversation.messages }

    return (
        understanding: understandingSignature(understandings.first?.first),
        messages: messages
    )
}

private func startWithObservedContextCase(
    snapshots: [TerminalSnapshot],
    observedContext: ForemanObservedTerminalContext,
    response: AgentStepResponse
) async throws -> (
    understanding: ForemanAgentTests.UnderstandingSignature?,
    messages: [ConversationMessage]
) {
    let conversation = await MainActor.run { ForemanConversation() }
    let client = ScriptedForemanClient(responses: [response])
    let commandRecorder = CommandRecorder()
    let agent = makeAgent(
        conversation: conversation,
        client: client,
        commandRecorder: commandRecorder
    )

    await agent.start(
        goal: "use structured context",
        mode: .interactive,
        captureSnapshots: { snapshots },
        captureObservedContext: { observedContext }
    )

    try await waitFor {
        let payloads = await client.recordedUnderstandings()
        let isRunning = await MainActor.run { conversation.isRunning }
        return !payloads.isEmpty && !isRunning
    }

    let commands = await commandRecorder.recordedCommands()
    #expect(commands.isEmpty)
    let understandings = await client.recordedUnderstandings()
    let messages = await MainActor.run { conversation.messages }

    return (
        understanding: understandingSignature(understandings.first?.first),
        messages: messages
    )
}

private actor ScriptedForemanClient: ForemanLLMClient {
    private var responses: [AgentStepResponse]
    private var replyDrafts: [AgentReplyDraftResponse]
    private var understandingsLog: [[TerminalUnderstanding]] = []
    private var overviewsLog: [TerminalOverview] = []
    private var stepCallCount = 0
    private var replyDraftCount = 0

    init(
        responses: [AgentStepResponse] = [],
        replyDrafts: [AgentReplyDraftResponse] = []
    ) {
        self.responses = responses
        self.replyDrafts = replyDrafts
    }

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw ScriptedForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw ScriptedForemanClientError.unexpectedCall
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        stepCallCount += 1
        understandingsLog.append(understandings)
        overviewsLog.append(overview)
        guard !responses.isEmpty else {
            throw ScriptedForemanClientError.missingResponse
        }
        return responses.removeFirst()
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        stepCallCount += 1
        guard !responses.isEmpty else {
            throw ScriptedForemanClientError.missingResponse
        }
        return responses.removeFirst()
    }

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse {
        replyDraftCount += 1
        understandingsLog.append(understandings)
        overviewsLog.append(overview)
        guard !replyDrafts.isEmpty else {
            throw ScriptedForemanClientError.missingResponse
        }
        return replyDrafts.removeFirst()
    }

    func recordedUnderstandings() -> [[TerminalUnderstanding]] {
        understandingsLog
    }

    func recordedOverviews() -> [TerminalOverview] {
        overviewsLog
    }

    func agentStepCallCount() -> Int {
        stepCallCount
    }

    func replyDraftCallCount() -> Int {
        replyDraftCount
    }
}

@MainActor
private final class MutableObservedContextSource {
    var current: ForemanObservedTerminalContext

    init(_ current: ForemanObservedTerminalContext) {
        self.current = current
    }
}

private func kimiReplySnapshots(
    terminalID: String,
    title: String,
    isFocused: Bool = false
) -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-1",
            title: title,
            cwd: "/Users/nambouchara/speed2",
            isFocused: isFocused,
            visibleText: """
            I'm now in the /Users/nambouchara/speed2/mend directory. Here's what's inside:
            .claude/
            docs/
            hooks/
            install.sh
            journal-skill/
            skill/
            templates/
            LICENSE
            README.md
            .gitignore

            What would you like me to do here?

            ─ input ─────────────────────────────────────────────────────────


            agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
            context: 5.4% (14.3k/262.1k)
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        ),
    ]
}

private func kimiInputChromeSnapshots(
    terminalID: String,
    title: String,
    isFocused: Bool = false
) -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-1",
            title: title,
            cwd: "/Users/nambouchara/speed2",
            isFocused: isFocused,
            visibleText: """
            ─ input ─────────────────────────────────────────────────────────

            agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
            context: 5.4% (14.3k/262.1k)
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        ),
    ]
}

private func kimiObservedWaitingTextContext(
    terminalID: String,
    snapshots: [TerminalSnapshot]
) -> ForemanObservedTerminalContext {
    ForemanObservedTerminalContext(
        terminals: snapshots,
        understandings: [
            .preview(
                terminalID: terminalID,
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response: What should I do here?",
                lastMeaningfulEvent: "What should I do here?",
                importantDetails: ["What should I do here?"],
                suggestedNextActions: [
                    .init(
                        title: "Reply to the agent",
                        command: nil,
                        reason: "What should I do here?",
                        isRecommended: true
                    ),
                ],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                supportLevel: .firstClass,
                evidence: [.init(source: .wireSignal, detail: "Wire record: QuestionRequest", confidence: 0.98)],
                agentInteractionContext: .waitingText(question: "What should I do here?")
            ),
        ],
        workerSnapshots: [:]
    )
}

private func choiceObservedContext(
    isPlanning: Bool,
    execution: TerminalWorkerSuggestionExecution
) -> ForemanObservedTerminalContext {
    let snapshots = [
        TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Which direction should I take?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        ),
    ]
    let workerSnapshot = TerminalWorkerSnapshot(
        schemaVersion: 1,
        terminalID: "term-1",
        workerSessionID: "kimi-session-12",
        revision: 12,
        observedAt: Date(timeIntervalSince1970: 1_748_333_333),
        ttlMilliseconds: 15_000,
        workerGoal: "compare API directions",
        agent: .init(identity: .kimi),
        state: .init(
            lifecycle: .running,
            attention: .choiceRequired,
            summary: isPlanning ? "Kimi is waiting in plan mode." : "Kimi suggested the safest option.",
            details: ["Two API directions are available."],
            runtimeFlags: isPlanning ? [.planning] : []
        ),
        request: .init(
            id: "req-12",
            kind: .choice,
            prompt: "Which direction should I take?",
            options: [
                .init(id: "1", label: "Keep current API", recommended: true),
                .init(id: "2", label: "Allow breaking change", recommended: false),
            ]
        ),
        suggestions: [
            .init(
                id: "keep-api",
                kind: .choice,
                title: "Keep current API",
                payload: .option("1"),
                rationale: "Lowest migration risk.",
                recommended: true,
                execution: execution,
                requestID: "req-12"
            ),
        ]
    )
    let understanding = TerminalUnderstanding.preview(
        terminalID: "term-1",
        state: .waiting,
        shortExplanation: isPlanning ? "Kimi is waiting in plan mode." : "Kimi suggested the safest option.",
        lastMeaningfulEvent: "Which direction should I take?",
        importantDetails: ["Two API directions are available."],
        suggestedNextActions: [
            .init(
                title: "Keep current API",
                command: nil,
                reason: "Lowest migration risk.",
                isRecommended: true
            ),
        ],
        agentIdentity: .kimi,
        agentInteractionState: .waitingChoice,
        supportLevel: .firstClass,
        evidence: [.init(source: .runtime, detail: "authoritative_worker_snapshot", confidence: 1.0)],
        agentInteractionContext: .waitingChoice(
            question: "Which direction should I take?",
            options: ["Keep current API", "Allow breaking change"],
            requestID: "req-12",
            sessionID: "kimi-session-12",
            revision: 12,
            isPlanning: isPlanning
        ),
        workerSnapshot: workerSnapshot
    )

    return ForemanObservedTerminalContext(
        terminals: snapshots,
        understandings: [understanding],
        workerSnapshots: ["term-1": workerSnapshot]
    )
}

private func runningObservedContextAfterSuggestedChoice() -> ForemanObservedTerminalContext {
    let snapshots = [
        TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Applying the selected API direction.",
            recentScrollbackLines: [],
            lastInputPreview: "1",
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        ),
    ]
    let workerSnapshot = TerminalWorkerSnapshot(
        schemaVersion: 1,
        terminalID: "term-1",
        workerSessionID: "kimi-session-12",
        revision: 13,
        observedAt: Date(timeIntervalSince1970: 1_748_333_334),
        ttlMilliseconds: 15_000,
        workerGoal: "compare API directions",
        agent: .init(identity: .kimi),
        state: .init(
            lifecycle: .running,
            attention: .none,
            summary: "Kimi is applying the selected API direction.",
            details: ["The worker is continuing with the approved choice."],
            runtimeFlags: []
        ),
        request: nil,
        suggestions: []
    )
    let understanding = TerminalUnderstanding.preview(
        terminalID: "term-1",
        state: .running,
        shortExplanation: "Kimi is applying the selected API direction.",
        lastMeaningfulEvent: "Applying the selected API direction.",
        importantDetails: ["The worker is continuing with the approved choice."],
        suggestedNextActions: [],
        agentIdentity: .kimi,
        agentInteractionState: .running,
        supportLevel: .firstClass,
        evidence: [.init(source: .runtime, detail: "authoritative_worker_snapshot", confidence: 1.0)],
        agentInteractionContext: .running(
            stepDescription: "Applying the selected API direction.",
            sessionID: "kimi-session-12",
            revision: 13
        ),
        workerSnapshot: workerSnapshot
    )

    return ForemanObservedTerminalContext(
        terminals: snapshots,
        understandings: [understanding],
        workerSnapshots: ["term-1": workerSnapshot]
    )
}

private func codexReplySnapshots(
    terminalID: String,
    title: String,
    isFocused: Bool = false
) -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-1",
            title: title,
            cwd: "/tmp/project",
            isFocused: isFocused,
            visibleText: """
            • Hello. What do you want to work on in ghostty?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        ),
    ]
}

private func claudeReplySnapshots(
    terminalID: String,
    title: String,
    isFocused: Bool = false
) -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-1",
            title: title,
            cwd: "/tmp/project",
            isFocused: isFocused,
            visibleText: """
            I inspected the repository layout and summarized the active files.

            What should I do next?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        ),
    ]
}

private func genericCodexWireSnapshots(
    terminalID: String,
    title: String,
    isFocused: Bool = false
) -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-1",
            title: title,
            cwd: "/tmp/project",
            isFocused: isFocused,
            visibleText: "codex",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        ),
    ]
}

private func genericCodexWireObservedContext(
    terminalID: String,
    title: String,
    isFocused: Bool = false
) -> ForemanObservedTerminalContext {
    let snapshots = genericCodexWireSnapshots(
        terminalID: terminalID,
        title: title,
        isFocused: isFocused
    )
    let codexWireRecordsByTerminalID = [
        terminalID: [
            CodexWireRecord(
                timestamp: "2026-05-04T12:00:10Z",
                type: "event_msg",
                payload: CodexWirePayload(
                    id: nil,
                    cwd: "/tmp/project",
                    originator: nil,
                    cliVersion: nil,
                    type: "task_complete",
                    turnId: "turn-1",
                    startedAt: nil,
                    completedAt: 1714828810,
                    durationMs: 9000,
                    reason: nil,
                    lastAgentMessage: nil,
                    callId: nil,
                    processId: nil,
                    command: nil,
                    status: nil,
                    message: nil,
                    phase: nil
                )
            ),
        ],
    ]

    return ForemanObservedContextBuilder()
        .build(
            snapshots: snapshots,
            codexWireRecordsByTerminalID: codexWireRecordsByTerminalID
        )
        .context
}

private func genericClaudeWireSnapshots(
    terminalID: String,
    title: String,
    isFocused: Bool = false
) -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-1",
            title: title,
            cwd: "/tmp/project",
            isFocused: isFocused,
            visibleText: "claude",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        ),
    ]
}

private func genericClaudeWireObservedContext(
    terminalID: String,
    title: String,
    isFocused: Bool = false
) -> ForemanObservedTerminalContext {
    let snapshots = genericClaudeWireSnapshots(
        terminalID: terminalID,
        title: title,
        isFocused: isFocused
    )
    let claudeWireRecordsByTerminalID = [
        terminalID: [
            ClaudeSessionState(
                pid: 12345,
                sessionId: "session-\(terminalID)",
                cwd: "/tmp/project",
                status: "idle",
                updatedAt: 1714828801000,
                startedAt: 1714828800000,
                version: "2.1.128",
                kind: "interactive"
            ),
        ],
    ]

    return ForemanObservedContextBuilder()
        .build(
            snapshots: snapshots,
            claudeWireRecordsByTerminalID: claudeWireRecordsByTerminalID
        )
        .context
}

private func kimiQuestionRecord(question: String) -> KimiWireRecord {
    KimiWireRecord(
        timestamp: 1,
        message: KimiWireMessage(
            type: "QuestionRequest",
            payload: KimiWirePayload(
                questions: [
                    QuestionItem(
                        question: question,
                        header: nil,
                        options: nil,
                        multi_select: nil
                    ),
                ]
            )
        )
    )
}

private actor FastPathRecordingForemanClient: ForemanLLMClient {
    private(set) var draftReplyCallCount = 0

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw ScriptedForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw ScriptedForemanClientError.unexpectedCall
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        throw ScriptedForemanClientError.unexpectedCall
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        throw ScriptedForemanClientError.unexpectedCall
    }

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse {
        draftReplyCallCount += 1
        return AgentReplyDraftResponse(
            thought: "fallback",
            suggestion: .noAction(reason: "should not be called", confidence: 0.0)
        )
    }
}

private enum ScriptedForemanClientError: Error {
    case unexpectedCall
    case missingResponse
}
