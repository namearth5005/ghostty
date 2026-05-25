import Foundation
import Testing
@testable import Ghostty

struct TerminalUnderstandingTests {
    private struct InteractiveParitySignature: Equatable {
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

    private func paritySignature(_ understanding: TerminalUnderstanding) -> (
        state: TerminalUnderstandingState,
        agentIdentity: AgentIdentity,
        interactionState: AgentInteractionState,
        supportLevel: AgentSupportLevel,
        shortExplanation: String,
        suggestedActionTitles: [String]
    ) {
        (
            state: understanding.state,
            agentIdentity: understanding.agentIdentity,
            interactionState: understanding.agentInteractionState,
            supportLevel: understanding.supportLevel,
            shortExplanation: understanding.shortExplanation,
            suggestedActionTitles: understanding.suggestedNextActions.map(\.title)
        )
    }

    private func makeWorkerSnapshot() -> TerminalWorkerSnapshot {
        TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-worker",
            workerSessionID: "worker-session-1",
            revision: 3,
            observedAt: Date(timeIntervalSince1970: 1_748_222_222),
            ttlMilliseconds: 12_000,
            workerGoal: "confirm the API direction",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Waiting for an API decision.",
                details: ["The worker asked whether the API should remain stable."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-3",
                kind: .reply,
                prompt: "Should I keep the current API?",
                options: []
            ),
            suggestions: []
        )
    }

    private func interactiveParitySignature(_ understanding: TerminalUnderstanding) -> InteractiveParitySignature {
        InteractiveParitySignature(
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

    @Test
    func engineKeepsKimiIdentityWhenOutputMentionsClaudeCode() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-kimi",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/Users/nambouchara/speed2",
            isFocused: true,
            visibleText: """
            Kimi is analyzing how this project can work with Claude Code, ChatGPT, and Cursor.

            What do you want to do?

            ❯ 1. Keep the core clinical content as provider-agnostic files
              2. Create different adapters for each platform

            agent (Kimi-k2.6 *) ~/speed2
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.shortExplanation.contains("Kimi"))
        #expect(!understanding.shortExplanation.contains("Claude Code"))
    }

    @Test
    func initializerStoresWorkerSnapshot() {
        let workerSnapshot = makeWorkerSnapshot()
        let understanding = TerminalUnderstanding(
            terminalID: "term-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            state: .waiting,
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            supportLevel: .firstClass,
            lastMeaningfulEvent: "Should I keep the current API?",
            shortExplanation: "Codex is waiting for your reply.",
            importantDetails: ["The worker needs confirmation before editing the API."],
            evidence: [],
            suggestedNextActions: [],
            agentInteractionContext: .waitingText(question: "Should I keep the current API?"),
            workerSnapshot: workerSnapshot
        )

        #expect(understanding.workerSnapshot == workerSnapshot)
    }

    @Test
    func previewCarriesWorkerSnapshot() {
        let workerSnapshot = makeWorkerSnapshot()
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for your reply.",
            lastMeaningfulEvent: "Should I keep the current API?",
            importantDetails: ["The worker needs confirmation before editing the API."],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            supportLevel: .firstClass,
            evidence: [],
            agentInteractionContext: .waitingText(question: "Should I keep the current API?"),
            workerSnapshot: workerSnapshot
        )

        #expect(understanding.workerSnapshot == workerSnapshot)
    }

    @Test
    func codableRoundTripPreservesWorkerSnapshot() throws {
        let workerSnapshot = makeWorkerSnapshot()
        let understanding = TerminalUnderstanding(
            terminalID: "term-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            state: .waiting,
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            supportLevel: .firstClass,
            lastMeaningfulEvent: "Should I keep the current API?",
            shortExplanation: "Codex is waiting for your reply.",
            importantDetails: ["The worker needs confirmation before editing the API."],
            evidence: [],
            suggestedNextActions: [],
            agentInteractionContext: .waitingText(question: "Should I keep the current API?"),
            workerSnapshot: workerSnapshot
        )

        let data = try JSONEncoder().encode(understanding)
        let decoded = try JSONDecoder().decode(TerminalUnderstanding.self, from: data)

        #expect(decoded == understanding)
        #expect(decoded.workerSnapshot == workerSnapshot)
    }

    @Test
    func similarlyNamedProcessesDoNotCreateFirstClassUnderstandingWithoutSeparateScreenEvidence() {
        let engine = TerminalUnderstandingEngine()
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-claude-helper",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "helper output",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude-hooks",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-codex-helper",
                windowID: "win-1",
                tabID: "tab-2",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "helper output",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex-playground",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-kimi-helper",
                windowID: "win-1",
                tabID: "tab-3",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "helper output",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "kimi-tools",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
        ]

        for snapshot in snapshots {
            let understanding = engine.understand(current: snapshot, previous: nil, lastOutcome: nil)
            #expect(understanding.agentIdentity == .none)
            #expect(understanding.agentInteractionState == .unknown)
            #expect(understanding.supportLevel == .genericFallback)
        }
    }

    @Test
    func shellOutputMentioningAgentNamesDoesNotCreateFirstClassUnderstandingWithoutOtherEvidence() {
        let engine = TerminalUnderstandingEngine()
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-claude-prose",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: """
                I compared Claude Code, ChatGPT, and Cursor while planning this task.
                The next step is to document the tradeoffs.
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-codex-prose",
                windowID: "win-1",
                tabID: "tab-2",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: """
                OpenAI Codex is one of several tools mentioned in this migration note.
                Nothing is actively attached to the terminal.
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
        ]

        for snapshot in snapshots {
            let understanding = engine.understand(current: snapshot, previous: nil, lastOutcome: nil)
            #expect(understanding.agentIdentity == .none)
            #expect(understanding.agentInteractionState == .unknown)
            #expect(understanding.supportLevel == .genericFallback)
        }
    }

    @Test
    func managedAndManualCodexLaunchesShareUnderstandingAtQuietWelcomeScreen() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = """
        ╭───────────────────────────────────────────────╮
        │ >_ OpenAI Codex (v0.133.0)                    │
        │                                               │
        │ model:       gpt-5.4 xhigh   /model to change │
        │ directory:   ~                                │
        │ permissions: YOLO mode                        │
        ╰───────────────────────────────────────────────╯

          Tip: New Use /fast to enable our fastest inference with increased plan usage.


        › codex


          gpt-5.4 xhigh · ~
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "codex-existing",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 101,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "codex-new-tab",
            windowID: "win-1",
            tabID: "tab-2",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 202,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "codex-managed",
            windowID: "win-1",
            tabID: "tab-3",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 303,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(paritySignature(existingUnderstanding) == paritySignature(newTabUnderstanding))
        #expect(paritySignature(existingUnderstanding) == paritySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentIdentity == AgentIdentity.codex)
        #expect(existingUnderstanding.state == TerminalUnderstandingState.idle)
    }

    @Test
    func managedAndManualKimiLaunchesShareUnderstandingAtWelcomeScreen() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = """
        Welcome to Kimi Code CLI!
        Send /help for help information.

        Directory: /tmp/project
        Session: abc123
        Model: Kimi-k2.6

        ── input ──────────────────────────────────────────────
        agent (Kimi-k2.6 ●)  /tmp/project
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "kimi-existing",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 404,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "kimi-new-tab",
            windowID: "win-1",
            tabID: "tab-2",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 505,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "kimi-managed",
            windowID: "win-1",
            tabID: "tab-3",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 606,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(paritySignature(existingUnderstanding) == paritySignature(newTabUnderstanding))
        #expect(paritySignature(existingUnderstanding) == paritySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentIdentity == AgentIdentity.kimi)
        #expect(existingUnderstanding.state == TerminalUnderstandingState.waiting)
        #expect(existingUnderstanding.agentInteractionState == AgentInteractionState.waitingText)
    }

    @Test
    func managedAndManualKimiLaunchesShareUnderstandingAtInputRegion() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = """
        ─ input ─────────────────────────────────────────────────────────

        agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
        context: 5.4% (14.3k/262.1k)
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "kimi-input-existing",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 414,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "kimi-input-new-tab",
            windowID: "win-1",
            tabID: "tab-2",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 515,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "kimi-input-managed",
            windowID: "win-1",
            tabID: "tab-3",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 616,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(paritySignature(existingUnderstanding) == paritySignature(newTabUnderstanding))
        #expect(paritySignature(existingUnderstanding) == paritySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentIdentity == .kimi)
        #expect(existingUnderstanding.state == .waiting)
        #expect(existingUnderstanding.agentInteractionState == .waitingText)
        #expect(existingUnderstanding.lastMeaningfulEvent == "No meaningful terminal event detected.")
    }

    @Test
    func managedAndManualClaudeLaunchesShareUnderstandingAtTrustPrompt() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = """
        Accessing workspace:

        /Users/nambouchara

        Quick safety check: Is this a project you created or one you trust?

        Security guide

         ❯ 1. Yes, I trust this folder
           2. No, exit

         Enter to confirm · Esc to cancel
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "claude-existing",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 707,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "claude-new-tab",
            windowID: "win-1",
            tabID: "tab-2",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/Users/nambouchara",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 808,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "claude-managed",
            windowID: "win-1",
            tabID: "tab-3",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 909,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(paritySignature(existingUnderstanding) == paritySignature(newTabUnderstanding))
        #expect(paritySignature(existingUnderstanding) == paritySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentIdentity == AgentIdentity.claudeCode)
        #expect(existingUnderstanding.state == TerminalUnderstandingState.waiting)
        #expect(existingUnderstanding.agentInteractionState == AgentInteractionState.waitingChoice)
        #expect(existingUnderstanding.lastMeaningfulEvent == "Quick safety check: Is this a project you created or one you trust?")
        let expectedContext: AgentInteractionContext = .waitingChoice(
            question: "Quick safety check: Is this a project you created or one you trust?",
            options: ["Yes, I trust this folder", "No, exit"]
        )
        #expect(existingUnderstanding.agentInteractionContext == expectedContext)
    }

    @Test
    func managedManualAndNewTabCodexQuestionPromptsShareReplyUnderstandingAndSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = """
        • Hello. What do you want to work on in ghostty?

        ›
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "codex-existing-reply",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 111,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "codex-new-tab-reply",
            windowID: "win-1",
            tabID: "tab-2",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 222,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "codex-managed-reply",
            windowID: "win-1",
            tabID: "tab-3",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 333,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(newTabUnderstanding))
        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentInteractionState == .waitingText)
        #expect(existingUnderstanding.agentInteractionContext == .waitingText(question: "• Hello. What do you want to work on in ghostty?"))
        #expect(existingUnderstanding.suggestedNextActions == [
            .init(
                title: "Reply to the agent",
                command: nil,
                reason: "• Hello. What do you want to work on in ghostty?",
                isRecommended: true
            )
        ])
    }

    @Test
    func managedManualAndNewTabKimiReplyPromptsShareUnderstandingAndSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = """
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
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "kimi-existing-reply",
            windowID: "win-1",
            tabID: "tab-4",
            title: "shell",
            cwd: "/Users/nambouchara/speed2",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 444,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "kimi-new-tab-reply",
            windowID: "win-1",
            tabID: "tab-5",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/Users/nambouchara/speed2",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 555,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "kimi-managed-reply",
            windowID: "win-1",
            tabID: "tab-6",
            title: "Kimi Code",
            cwd: "/Users/nambouchara/speed2",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 666,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(newTabUnderstanding))
        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentInteractionState == .waitingText)
        #expect(existingUnderstanding.agentInteractionContext == .waitingText(question: "What would you like me to do here?"))
        #expect(existingUnderstanding.suggestedNextActions == [
            .init(
                title: "Reply to the agent",
                command: nil,
                reason: "What would you like me to do here?",
                isRecommended: true
            )
        ])
    }

    @Test
    func managedManualAndNewTabKimiApprovalPromptsShareUnderstandingAndSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = """
        Shell is requesting approval to run command

        1. Approve once
        2. Reject, tell the model what to do instead
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "kimi-existing-approval",
            windowID: "win-1",
            tabID: "tab-7",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 777,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "kimi-new-tab-approval",
            windowID: "win-1",
            tabID: "tab-8",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 888,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "kimi-managed-approval",
            windowID: "win-1",
            tabID: "tab-9",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 999,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(newTabUnderstanding))
        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentInteractionState == .waitingApproval)
        #expect(existingUnderstanding.agentInteractionContext.typeString == "waitingApproval")
        #expect(existingUnderstanding.suggestedNextActions.map(\.title) == [
            "Review the approval request",
            "Let Foreman explain the requested action",
        ])
        #expect(existingUnderstanding.suggestedNextActions.map(\.isRecommended) == [true, false])
    }

    @Test
    func managedManualAndNewTabCodexApprovalPromptsShareUnderstandingAndSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = """
        Permission required

        Allow OpenAI Codex to edit auth.ts? [y/n]
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "codex-existing-approval",
            windowID: "win-1",
            tabID: "tab-10",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 1_111,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "codex-new-tab-approval",
            windowID: "win-1",
            tabID: "tab-11",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 1_222,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "codex-managed-approval",
            windowID: "win-1",
            tabID: "tab-12",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 1_333,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(newTabUnderstanding))
        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentInteractionState == .waitingApproval)
        #expect(existingUnderstanding.agentInteractionContext.typeString == "waitingApproval")
        #expect(existingUnderstanding.lastMeaningfulEvent == "Allow OpenAI Codex to edit auth.ts? [y/n]")
        #expect(existingUnderstanding.suggestedNextActions.map(\.title) == [
            "Review the approval request",
            "Let Foreman explain the requested action",
        ])
        #expect(existingUnderstanding.suggestedNextActions.map(\.isRecommended) == [true, false])
    }

    @Test
    func managedManualAndNewTabClaudeApprovalPromptsShareUnderstandingAndSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let visibleText = "Allow Claude Code to run the suggested command? [y/n]"

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "claude-existing-approval",
            windowID: "win-1",
            tabID: "tab-13",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 1_444,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "claude-new-tab-approval",
            windowID: "win-1",
            tabID: "tab-14",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 1_555,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "claude-managed-approval",
            windowID: "win-1",
            tabID: "tab-15",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 1_666,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let existingUnderstanding = engine.understand(current: existingTab, previous: nil, lastOutcome: nil)
        let newTabUnderstanding = engine.understand(current: newTab, previous: nil, lastOutcome: nil)
        let managedUnderstanding = engine.understand(current: managed, previous: nil, lastOutcome: nil)

        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(newTabUnderstanding))
        #expect(interactiveParitySignature(existingUnderstanding) == interactiveParitySignature(managedUnderstanding))
        #expect(existingUnderstanding.agentInteractionState == .waitingApproval)
        #expect(existingUnderstanding.agentInteractionContext.typeString == "waitingApproval")
        #expect(existingUnderstanding.lastMeaningfulEvent == "Allow Claude Code to run the suggested command? [y/n]")
        #expect(existingUnderstanding.suggestedNextActions.map(\.title) == [
            "Review the approval request",
            "Let Foreman explain the requested action",
        ])
        #expect(existingUnderstanding.suggestedNextActions.map(\.isRecommended) == [true, false])
    }

    @Test
    func managedManualAndNewTabCodexRunningToReplyTransitionSharesUnderstandingAndSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let cases: [(terminalID: String, title: String, isFocused: Bool, processID: Int)] = [
            ("codex-transition-existing", "shell", true, 1_901),
            ("codex-transition-new-tab", "nambouchara@Nams-MacBook-Pro:~", false, 1_902),
            ("codex-transition-managed", "OpenAI Codex", false, 1_903),
        ]

        var previousUnderstandings: [InteractiveParitySignature] = []
        var currentUnderstandings: [InteractiveParitySignature] = []

        for entry in cases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.processID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: "• Working (0s • esc to interrupt)",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.processID,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.processID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: """
                • Hey. What do you need help with?

                ›
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.processID,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )

            let previousUnderstanding = engine.understand(current: previous, previous: nil, lastOutcome: nil)
            let currentUnderstanding = engine.understand(current: current, previous: previous, lastOutcome: nil)

            previousUnderstandings.append(interactiveParitySignature(previousUnderstanding))
            currentUnderstandings.append(interactiveParitySignature(currentUnderstanding))
        }

        #expect(previousUnderstandings.dropFirst().allSatisfy { $0 == previousUnderstandings.first })
        #expect(currentUnderstandings.dropFirst().allSatisfy { $0 == currentUnderstandings.first })
        #expect(previousUnderstandings.first?.state == .running)
        #expect(previousUnderstandings.first?.interactionState == .running)
        #expect(currentUnderstandings.first?.state == .waiting)
        #expect(currentUnderstandings.first?.interactionState == .waitingText)
        #expect(currentUnderstandings.first?.interactionContext == .waitingText(question: "• Hey. What do you need help with?"))
        #expect(currentUnderstandings.first?.suggestedNextActions == [
            .init(
                title: "Reply to the agent",
                command: nil,
                reason: "• Hey. What do you need help with?",
                isRecommended: true
            )
        ])
    }

    @Test
    func managedManualAndNewTabKimiWelcomeToWireQuestionTransitionSharesUnderstandingAndSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let question = "What should I do here?"
        let cases: [(terminalID: String, title: String, isFocused: Bool, processID: Int)] = [
            ("kimi-transition-existing", "shell", true, 2_001),
            ("kimi-transition-new-tab", "nambouchara@Nams-MacBook-Pro:~", false, 2_002),
            ("kimi-transition-managed", "Kimi Code", false, 2_003),
        ]

        var previousUnderstandings: [InteractiveParitySignature] = []
        var currentUnderstandings: [InteractiveParitySignature] = []

        for entry in cases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-2",
                tabID: "tab-\(entry.processID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: """
                Welcome to Kimi Code CLI!
                Send /help for help information.

                Directory: /tmp/project
                Session: abc123
                Model: Kimi-k2.6

                ── input ──────────────────────────────────────────────
                agent (Kimi-k2.6 ●)  /tmp/project
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.processID,
                foregroundProcessName: "kimi",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-2",
                tabID: "tab-\(entry.processID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: """
                ─ input ─────────────────────────────────────────────────────────

                agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
                context: 5.4% (14.3k/262.1k)
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.processID,
                foregroundProcessName: "kimi",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )

            let previousUnderstanding = engine.understand(current: previous, previous: nil, lastOutcome: nil)
            let currentUnderstanding = engine.understand(
                current: current,
                previous: previous,
                lastOutcome: nil,
                wireRecords: [kimiQuestionRecord(question: question)]
            )

            previousUnderstandings.append(interactiveParitySignature(previousUnderstanding))
            currentUnderstandings.append(interactiveParitySignature(currentUnderstanding))
        }

        #expect(previousUnderstandings.dropFirst().allSatisfy { $0 == previousUnderstandings.first })
        #expect(currentUnderstandings.dropFirst().allSatisfy { $0 == currentUnderstandings.first })
        #expect(previousUnderstandings.first?.state == .waiting)
        #expect(previousUnderstandings.first?.interactionState == .waitingText)
        #expect(previousUnderstandings.first?.interactionContext == .waitingText(question: nil))
        #expect(currentUnderstandings.first?.state == .waiting)
        #expect(currentUnderstandings.first?.interactionState == .waitingText)
        #expect(currentUnderstandings.first?.lastMeaningfulEvent == question)
        #expect(currentUnderstandings.first?.interactionContext == .waitingText(question: question))
        #expect(currentUnderstandings.first?.suggestedNextActions == [
            .init(
                title: "Reply to the agent",
                command: nil,
                reason: question,
                isRecommended: true
            )
        ])
    }

    @Test
    func managedManualAndNewTabClaudeRunningToTrustPromptTransitionSharesUnderstandingAndSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let trustPrompt = "Quick safety check: Is this a project you created or one you trust?"
        let expectedContext: AgentInteractionContext = .waitingChoice(
            question: trustPrompt,
            options: ["Yes, I trust this folder", "No, exit"]
        )
        let cases: [(terminalID: String, title: String, isFocused: Bool, processID: Int)] = [
            ("claude-transition-existing", "shell", true, 3_001),
            ("claude-transition-new-tab", "nambouchara@Nams-MacBook-Pro:~", false, 3_002),
            ("claude-transition-managed", "Claude Code", false, 3_003),
        ]

        var previousUnderstandings: [InteractiveParitySignature] = []
        var currentUnderstandings: [InteractiveParitySignature] = []

        for entry in cases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-3",
                tabID: "tab-\(entry.processID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: "Thinking...",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.processID,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-3",
                tabID: "tab-\(entry.processID)",
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
                foregroundProcessID: entry.processID,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )

            let previousUnderstanding = engine.understand(current: previous, previous: nil, lastOutcome: nil)
            let currentUnderstanding = engine.understand(current: current, previous: previous, lastOutcome: nil)

            previousUnderstandings.append(interactiveParitySignature(previousUnderstanding))
            currentUnderstandings.append(interactiveParitySignature(currentUnderstanding))
        }

        #expect(previousUnderstandings.dropFirst().allSatisfy { $0 == previousUnderstandings.first })
        #expect(currentUnderstandings.dropFirst().allSatisfy { $0 == currentUnderstandings.first })
        #expect(previousUnderstandings.first?.state == .running)
        #expect(previousUnderstandings.first?.interactionState == .running)
        #expect(currentUnderstandings.first?.state == .waiting)
        #expect(currentUnderstandings.first?.interactionState == .waitingChoice)
        #expect(currentUnderstandings.first?.lastMeaningfulEvent == trustPrompt)
        #expect(currentUnderstandings.first?.interactionContext == expectedContext)
        #expect(currentUnderstandings.first?.suggestedNextActions.map(\.title) == [
            "Inspect the available choices",
            "Ask Foreman to summarize the options",
        ])
        #expect(currentUnderstandings.first?.suggestedNextActions.map(\.isRecommended) == [true, false])
    }

    @Test
    func engineClassifiesCommandNotFoundAsFailedWithRankedSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "hfind . -print\nzsh: command not found: hfind\nuser@host %",
            recentScrollbackLines: ["hfind . -print", "zsh: command not found: hfind"],
            lastInputPreview: "hfind . -print"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.state == .failed)
        #expect(understanding.lastMeaningfulEvent.contains("command not found"))
        #expect(understanding.suggestedNextActions.count == 3)
        #expect(understanding.suggestedNextActions.map(\.title) == [
            "Run the likely intended find command",
            "Try fd if a faster file search was intended",
            "Confirm whether hfind was intentional",
        ])
        #expect(understanding.suggestedNextActions.map(\.isRecommended) == [true, false, false])
        #expect(understanding.suggestedNextActions.map(\.command) == ["find . -print", "fd .", nil])
        #expect(understanding.recommendedAction?.command == "find . -print")
        #expect(understanding.suggestedNextActions.first?.command == understanding.recommendedAction?.command)
    }

    @Test
    func engineClassifiesBuildOutputAsRunning() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-2",
            windowID: "win-1",
            tabID: "tab-2",
            title: "build",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "Compiling module A...\nCompiling module B...",
            recentScrollbackLines: ["Compiling module A...", "Compiling module B..."],
            lastInputPreview: "swift build"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.state == .running)
        #expect(understanding.shortExplanation.contains("build"))
    }

    @Test
    func engineIgnoresStaleOutcomeFromPreviousCommand() {
        let engine = TerminalUnderstandingEngine()
        let previous = TerminalSnapshot.makePreview(
            terminalID: "term-3",
            windowID: "win-1",
            tabID: "tab-3",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "npm test\nuser@host %",
            recentScrollbackLines: ["npm test", "user@host %"],
            lastInputPreview: "npm test"
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "term-3",
            windowID: "win-1",
            tabID: "tab-3",
            title: "build",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Compiling module A...\nCompiling module B...",
            recentScrollbackLines: ["Compiling module A...", "Compiling module B..."],
            lastInputPreview: "swift build"
        )
        let staleOutcome = TerminalOutcomeReport(
            terminalID: "term-3",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: .now,
            summary: "Previous tests passed cleanly."
        )

        let understanding = engine.understand(
            current: current,
            previous: previous,
            lastOutcome: staleOutcome
        )

        #expect(understanding.state == .running)
        #expect(understanding.lastMeaningfulEvent == "Compiling module B...")
        #expect(!understanding.shortExplanation.contains("Previous tests passed cleanly."))
    }

    @Test
    func engineUsesFreshSuccessOutcomeSummaryInExplanation() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-4",
            windowID: "win-1",
            tabID: "tab-4",
            title: "test",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "npm test\nuser@host %",
            recentScrollbackLines: ["npm test", "user@host %"],
            lastInputPreview: "npm test"
        )
        let outcome = TerminalOutcomeReport(
            terminalID: "term-4",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: .now,
            summary: "Tests finished successfully."
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: outcome
        )

        #expect(understanding.state == .succeeded)
        #expect(understanding.lastMeaningfulEvent == "Tests finished successfully.")
        #expect(understanding.shortExplanation.contains("Tests finished successfully."))
    }

    @Test
    func engineIgnoresStaleOutcomeWhenSameCommandIsRerun() {
        let engine = TerminalUnderstandingEngine()
        let previous = TerminalSnapshot.makePreview(
            terminalID: "term-5",
            windowID: "win-1",
            tabID: "tab-5",
            title: "test",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Tests: 42 passed\nuser@host %",
            recentScrollbackLines: ["npm test", "Tests: 42 passed", "user@host %"],
            lastInputPreview: "npm test"
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "term-5",
            windowID: "win-1",
            tabID: "tab-5",
            title: "test",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Running tests...\nSuite auth.spec.ts",
            recentScrollbackLines: ["npm test", "Running tests...", "Suite auth.spec.ts"],
            lastInputPreview: "npm test"
        )
        let staleOutcome = TerminalOutcomeReport(
            terminalID: "term-5",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: .now,
            summary: "Previous test run passed."
        )

        let understanding = engine.understand(
            current: current,
            previous: previous,
            lastOutcome: staleOutcome
        )

        #expect(understanding.state == .running)
        #expect(understanding.lastMeaningfulEvent == "Suite auth.spec.ts")
        #expect(!understanding.shortExplanation.contains("Previous test run passed."))
    }

    @Test
    func adaptiveOverviewMentionsOnlyChangedTerminal() {
        let engine = TerminalUnderstandingEngine()

        let previous = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .running,
                shortExplanation: "API server is booting.",
                lastMeaningfulEvent: "Server startup began.",
                importantDetails: ["Listening on port 3000 soon."],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .running,
                shortExplanation: "Tests are still running.",
                lastMeaningfulEvent: "Vitest started.",
                importantDetails: ["42 tests discovered."],
                suggestedNextActions: []
            ),
        ]

        let current = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .succeeded,
                shortExplanation: "API server is ready.",
                lastMeaningfulEvent: "Server reported ready.",
                importantDetails: ["Listening on http://localhost:3000."],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .running,
                shortExplanation: "Tests are still running.",
                lastMeaningfulEvent: "Vitest started.",
                importantDetails: ["42 tests discovered."],
                suggestedNextActions: []
            ),
        ]

        let overview = engine.makeOverview(current: current, previous: previous)

        #expect(overview.summary == "term-1: API server is ready.")
        #expect(!overview.summary.contains("term-2"))
        #expect(overview.changedTerminalIDs == ["term-1"])
    }

    @Test
    func adaptiveOverviewCountsRemovedTerminalAsChange() {
        let engine = TerminalUnderstandingEngine()

        let previous = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .running,
                shortExplanation: "API server is still running.",
                lastMeaningfulEvent: "Server is healthy.",
                importantDetails: ["Listening on http://localhost:3000."],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .running,
                shortExplanation: "Tests are still running.",
                lastMeaningfulEvent: "Vitest started.",
                importantDetails: ["42 tests discovered."],
                suggestedNextActions: []
            ),
        ]
        let current = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .running,
                shortExplanation: "API server is still running.",
                lastMeaningfulEvent: "Server is healthy.",
                importantDetails: ["Listening on http://localhost:3000."],
                suggestedNextActions: []
            ),
        ]

        let overview = engine.makeOverview(current: current, previous: previous)

        #expect(overview.summary == "term-2 is no longer available.")
        #expect(overview.changedTerminalIDs == ["term-2"])
        #expect(overview.primaryTerminalID == "term-2")
    }

    @Test
    func engineClassifiesClaudeMenuAsWaitingChoice() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-6",
            windowID: "win-1",
            tabID: "tab-6",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            What do you want to do?

            ❯ 1. Stop and wait for limit to reset
              2. Upgrade your plan

            Enter to confirm · Esc to cancel
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            usingAlternateScreen: true
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .claudeCode)
        #expect(understanding.agentInteractionState == .waitingChoice)
        #expect(understanding.state == .waiting)
        #expect(understanding.supportLevel == .firstClass)
        #expect(understanding.evidence.contains(where: { $0.source == .screenHeuristic }))
    }

    @Test
    func engineDoesNotClassifyChoiceMarkerWithoutOptionsAsWaitingChoice() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-6",
            windowID: "win-1",
            tabID: "tab-6",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            What do you want to do?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .claudeCode)
        #expect(understanding.agentInteractionState == .waitingText)
    }

    @Test
    func engineClassifiesCodexPromptAsWaitingText() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-7",
            windowID: "win-1",
            tabID: "tab-7",
            title: "speed2",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            • Hey. What do you need help with?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .codex)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.state == .waiting)
        #expect(understanding.shortExplanation.contains("waiting"))
    }

    @Test
    func engineIgnoresCodexWelcomePermissionsLineWhenClassifyingPrompt() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-7b",
            windowID: "win-1",
            tabID: "tab-7b",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            >_ OpenAI Codex (v0.131.0)

            model: gpt-5.4 xhigh
            directory: ~/speed2/ghostty
            permissions: YOLO mode

            • Hello. What do you want to work on in ghostty?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .codex)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.agentInteractionContext == .waitingText(question: "• Hello. What do you want to work on in ghostty?"))
        #expect(understanding.shortExplanation.contains("waiting"))
    }

    @Test
    func enginePreservesLastActionableClaudeWireStateWhenTrailingStatusIsUnknown() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-7c",
            windowID: "win-1",
            tabID: "tab-7c",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Welcome to Claude Code",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude"
        )
        let actionable = ClaudeSessionState(
            pid: 12345,
            sessionId: "session-1",
            cwd: "/tmp/project",
            status: "needs_approval",
            updatedAt: 1714828801000,
            startedAt: 1714828800000,
            version: "2.1.128",
            kind: "interactive"
        )
        let trailingUnknown = ClaudeSessionState(
            pid: 12345,
            sessionId: "session-1",
            cwd: "/tmp/project",
            status: "syncing",
            updatedAt: 1714828802000,
            startedAt: 1714828800000,
            version: "2.1.128",
            kind: "interactive"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            claudeWireRecords: [actionable, trailingUnknown]
        )

        #expect(understanding.agentIdentity == .claudeCode)
        #expect(understanding.agentInteractionState == .waitingApproval)
        #expect(understanding.state == .waiting)
        #expect(understanding.evidence.contains(where: { $0.source == .wireSignal }))
    }

    @Test
    func engineUsesCodexWireRecordsToPreserveIdentityWhenSurfaceIsGeneric() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-wire",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "codex",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let records = [
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
        ]

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            codexWireRecords: records
        )

        #expect(understanding.agentIdentity == .codex)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.agentInteractionContext == .waitingText(question: nil))
        #expect(understanding.evidence.contains(where: { $0.source == .wireSignal }))
    }

    @Test
    func engineUsesClaudeSessionStateToPreserveIdentityWhenSurfaceIsGeneric() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "claude-wire",
            windowID: "win-1",
            tabID: "tab-2",
            title: "Claude",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "claude",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let records = [
            ClaudeSessionState(
                pid: 12345,
                sessionId: "session-1",
                cwd: "/tmp/project",
                status: "idle",
                updatedAt: 1714828801000,
                startedAt: 1714828800000,
                version: "2.1.128",
                kind: "interactive"
            ),
        ]

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            claudeWireRecords: records
        )

        #expect(understanding.agentIdentity == .claudeCode)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.agentInteractionContext == .waitingText(question: nil))
        #expect(understanding.evidence.contains(where: { $0.source == .wireSignal }))
    }

    @Test
    func engineKeepsKimiQuestionAboveInputChromeAsWaitingTextPrompt() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-8",
            windowID: "win-1",
            tabID: "tab-8",
            title: "Kimi Code",
            cwd: "/Users/nambouchara/speed2",
            isFocused: true,
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
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.lastMeaningfulEvent == "What would you like me to do here?")
        #expect(understanding.shortExplanation.contains("What would you like me to do here?"))
        #expect(understanding.importantDetails.contains("What would you like me to do here?"))
    }

    @Test
    func managedAgentTitleAloneDoesNotCreateFirstClassUnderstanding() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-shell",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "nambouchara@Nams-MacBook-Pro ghostty % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "zsh",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .none)
        #expect(understanding.supportLevel == .genericFallback)
        #expect(understanding.state == .waiting)
    }
}
