import Foundation
import Testing
@testable import Ghostty

struct AgentMeaningDetectorTests {
    private let detector = AgentMeaningDetector()

    private func signature(_ detection: AgentMeaningDetector.Detection?) -> (
        identity: AgentIdentity?,
        interactionState: AgentInteractionState?,
        runtimeState: AgentRuntimeState?,
        context: AgentInteractionContext?,
        evidenceSource: UnderstandingEvidenceSource?
    ) {
        (
            identity: detection?.identity,
            interactionState: detection?.interactionState,
            runtimeState: detection?.runtimeState,
            context: detection?.context,
            evidenceSource: detection?.evidence.first?.source
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
    func rawBlockedCodexPromptMapsToWaitingText() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            • Hello. What do you want to work on in ghostty?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let detection = detector.detect(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            lastEvent: "• Hello. What do you want to work on in ghostty?"
        )

        #expect(detection?.identity == .codex)
        #expect(detection?.interactionState == .waitingText)
        #expect(detection?.runtimeState == .blocked)
        #expect(detection?.context == .waitingText(question: "• Hello. What do you want to work on in ghostty?"))
    }

    @Test
    func rawWorkingStateMapsToRunning() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "• Working (0s • esc to interrupt)",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let detection = detector.detect(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            lastEvent: "• Working (0s • esc to interrupt)"
        )

        #expect(detection?.interactionState == .running)
        #expect(detection?.runtimeState == .working)
        #expect(detection?.context == .running(stepDescription: "• Working (0s • esc to interrupt)"))
    }

    @Test
    func codexPromptOutranksStaleWireRunningState() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            You're running a debug build of Ghostty! Performance will be degraded.

            gpt-5.4 medium · ~/tmp/project
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let wireRecord = CodexWireRecord(
            timestamp: "2026-05-31T07:30:00Z",
            type: "event_msg",
            payload: CodexWirePayload(
                id: nil,
                cwd: "/tmp/project",
                originator: nil,
                cliVersion: nil,
                type: "task_started",
                turnId: "turn-1",
                startedAt: 1,
                completedAt: nil,
                durationMs: nil,
                reason: nil,
                lastAgentMessage: nil,
                callId: nil,
                processId: nil,
                command: nil,
                status: nil,
                message: nil,
                phase: nil
            )
        )

        let detection = detector.detect(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            lastEvent: "gpt-5.4 medium · ~/tmp/project",
            codexWireRecords: [wireRecord]
        )

        #expect(detection?.identity == .codex)
        #expect(detection?.interactionState == .unknown)
        #expect(detection?.runtimeState == .idle)
        #expect(detection?.context == AgentInteractionContext.none)
    }

    @Test
    func successfulOutcomeMapsToCompleted() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "nambouchara@host ghostty %",
            recentScrollbackLines: [],
            lastInputPreview: "npm test",
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )
        let outcome = TerminalOutcomeReport(
            terminalID: snapshot.terminalID,
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: Date(),
            summary: "Tests passed."
        )

        let detection = detector.detect(
            current: snapshot,
            previous: nil,
            lastOutcome: outcome,
            lastEvent: "Tests passed."
        )

        #expect(detection?.interactionState == .completed)
        #expect(detection?.runtimeState == .idle)
        #expect(detection?.context == .completed(summary: "Tests passed."))
        #expect(detection?.evidence.first?.source == .outcome)
    }

    @Test
    func failureOutcomeMapsToError() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "error: module not found",
            recentScrollbackLines: [],
            lastInputPreview: "npm test",
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )
        let outcome = TerminalOutcomeReport(
            terminalID: snapshot.terminalID,
            sentCommand: "npm test",
            outcome: .failure,
            detectedAt: Date(),
            summary: "error: module not found"
        )

        let detection = detector.detect(
            current: snapshot,
            previous: nil,
            lastOutcome: outcome,
            lastEvent: "error: module not found"
        )

        #expect(detection?.interactionState == .error)
        #expect(detection?.runtimeState == .blocked)
        #expect(detection?.context == .error(description: "error: module not found"))
        #expect(detection?.evidence.first?.source == .outcome)
    }

    @Test
    func kimiApprovalScreenOutranksWireRunningState() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "kimi-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Shell is requesting approval to run command

            1. Approve once
            2. Reject, tell the model what to do instead
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let wireRecord = KimiWireRecord(
            timestamp: 123,
            message: KimiWireMessage(
                type: "TurnBegin",
                payload: KimiWirePayload()
            )
        )

        let detection = detector.detect(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            lastEvent: "Shell is requesting approval to run command",
            wireRecords: [wireRecord]
        )

        #expect(detection?.interactionState == .waitingApproval)
        #expect(detection?.runtimeState == .blocked)
        #expect(detection?.evidence.first?.source == .screenHeuristic)
    }

    @Test
    func kimiApprovalScreenWithTrailingInputChromeStillMapsToWaitingApproval() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "kimi-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Shell is requesting approval to run command

            1. Approve once
            2. Approve for this session
            3. Reject, tell the model what to do instead

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
        let wireRecord = KimiWireRecord(
            timestamp: 123,
            message: KimiWireMessage(
                type: "TurnBegin",
                payload: KimiWirePayload()
            )
        )

        let detection = detector.detect(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            lastEvent: "Shell is requesting approval to run command",
            wireRecords: [wireRecord]
        )

        #expect(detection?.interactionState == .waitingApproval)
        #expect(detection?.runtimeState == .blocked)
        #expect(detection?.evidence.first?.source == .screenHeuristic)
    }

    @Test
    func managedManualAndNewTabClaudeTrustPromptsShareWaitingChoiceMeaning() {
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
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "claude-new-tab",
            windowID: "win-1",
            tabID: "tab-2",
            title: "nambouchara@host:~",
            cwd: "/Users/nambouchara",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
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
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingDetection = detector.detect(
            current: existingTab,
            previous: nil,
            lastOutcome: nil,
            lastEvent: "Quick safety check: Is this a project you created or one you trust?"
        )
        let newTabDetection = detector.detect(
            current: newTab,
            previous: nil,
            lastOutcome: nil,
            lastEvent: "Quick safety check: Is this a project you created or one you trust?"
        )
        let managedDetection = detector.detect(
            current: managed,
            previous: nil,
            lastOutcome: nil,
            lastEvent: "Quick safety check: Is this a project you created or one you trust?"
        )

        #expect(signature(existingDetection) == signature(newTabDetection))
        #expect(signature(existingDetection) == signature(managedDetection))
        #expect(existingDetection?.interactionState == .waitingChoice)
        #expect(existingDetection?.runtimeState == .blocked)
    }

    @Test
    func codexPromptAppearingAfterWorkingTransitionsFromRunningToWaitingText() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "codex-transition",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "• Working (0s • esc to interrupt)",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "codex-transition",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            • Hello. What do you want to work on in ghostty?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let detection = detector.detect(
            current: current,
            previous: previous,
            lastOutcome: nil,
            lastEvent: "• Hello. What do you want to work on in ghostty?"
        )

        #expect(detection?.identity == .codex)
        #expect(detection?.interactionState == .waitingText)
        #expect(detection?.runtimeState == .blocked)
        #expect(detection?.context == .waitingText(question: "• Hello. What do you want to work on in ghostty?"))
    }

    @Test
    func managedManualAndNewTabCodexRunningToWaitingTextTransitionSharesMeaning() throws {
        let prompt = "• Hello. What do you want to work on in ghostty?"
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("codex-transition-existing", "shell", true),
            ("codex-transition-new-tab", "nambouchara@host:~", false),
            ("codex-transition-managed", "OpenAI Codex", false),
        ]

        var detections: [(identity: AgentIdentity?, interactionState: AgentInteractionState?, runtimeState: AgentRuntimeState?, context: AgentInteractionContext?, evidenceSource: UnderstandingEvidenceSource?)] = []

        for entry in cases {
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
                foregroundProcessName: "codex",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: """
                • Hello. What do you want to work on in ghostty?

                ›
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )

            detections.append(signature(detector.detect(
                current: current,
                previous: previous,
                lastOutcome: nil,
                lastEvent: prompt
            )))
        }

        let first = try #require(detections.first)
        #expect(detections.dropFirst().allSatisfy { $0 == first })
        #expect(first.identity == .codex)
        #expect(first.interactionState == .waitingText)
        #expect(first.runtimeState == .blocked)
        #expect(first.context == .waitingText(question: prompt))
    }

    @Test
    func managedManualAndNewTabKimiWelcomeToWireQuestionTransitionSharesMeaning() throws {
        let question = "What should I do here?"
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("kimi-transition-existing", "shell", true),
            ("kimi-transition-new-tab", "nambouchara@host:~", false),
            ("kimi-transition-managed", "Kimi Code", false),
        ]

        var detections: [(identity: AgentIdentity?, interactionState: AgentInteractionState?, runtimeState: AgentRuntimeState?, context: AgentInteractionContext?, evidenceSource: UnderstandingEvidenceSource?)] = []

        for entry in cases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-2",
                tabID: "tab-\(entry.terminalID)",
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
                foregroundProcessName: "kimi",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-2",
                tabID: "tab-\(entry.terminalID)",
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
                foregroundProcessName: "kimi",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )

            detections.append(signature(detector.detect(
                current: current,
                previous: previous,
                lastOutcome: nil,
                lastEvent: "No meaningful terminal event detected.",
                wireRecords: [kimiQuestionRecord(question: question)]
            )))
        }

        let first = try #require(detections.first)
        #expect(detections.dropFirst().allSatisfy { $0 == first })
        #expect(first.identity == .kimi)
        #expect(first.interactionState == .waitingText)
        #expect(first.runtimeState == .blocked)
        #expect(first.context == .waitingText(question: question))
    }

    @Test
    func managedManualAndNewTabClaudeRunningToTrustPromptTransitionSharesMeaning() throws {
        let trustPrompt = "Quick safety check: Is this a project you created or one you trust?"
        let expectedContext: AgentInteractionContext = .waitingChoice(
            question: trustPrompt,
            options: ["Yes, I trust this folder", "No, exit"]
        )
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("claude-transition-existing", "shell", true),
            ("claude-transition-new-tab", "nambouchara@host:~", false),
            ("claude-transition-managed", "Claude Code", false),
        ]

        var detections: [(identity: AgentIdentity?, interactionState: AgentInteractionState?, runtimeState: AgentRuntimeState?, context: AgentInteractionContext?, evidenceSource: UnderstandingEvidenceSource?)] = []

        for entry in cases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-3",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: "Thinking...",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-3",
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
                foregroundProcessName: "claude",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )

            detections.append(signature(detector.detect(
                current: current,
                previous: previous,
                lastOutcome: nil,
                lastEvent: trustPrompt
            )))
        }

        let first = try #require(detections.first)
        #expect(detections.dropFirst().allSatisfy { $0 == first })
        #expect(first.identity == .claudeCode)
        #expect(first.interactionState == .waitingChoice)
        #expect(first.runtimeState == .blocked)
        #expect(first.context == expectedContext)
    }

    @Test
    func resolvedInteractiveSurfacesTransitionBackToIdleMeaningAcrossCodexAndClaude() {
        let codexPrevious = TerminalSnapshot.makePreview(
            terminalID: "codex-idle-transition",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            • Hello. What do you want to work on in ghostty?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let codexCurrent = TerminalSnapshot.makePreview(
            terminalID: "codex-idle-transition",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "nambouchara@host ghostty % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )
        let claudePrevious = TerminalSnapshot.makePreview(
            terminalID: "claude-idle-transition",
            windowID: "win-2",
            tabID: "tab-2",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: """
            Accessing workspace:

            /Users/nambouchara

            Quick safety check: Is this a project you created or one you trust?

             ❯ 1. Yes, I trust this folder
               2. No, exit

             Enter to confirm · Esc to cancel
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let claudeCurrent = TerminalSnapshot.makePreview(
            terminalID: "claude-idle-transition",
            windowID: "win-2",
            tabID: "tab-2",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: "nambouchara@host ghostty % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )

        let codexDetection = detector.detect(
            current: codexCurrent,
            previous: codexPrevious,
            lastOutcome: nil,
            lastEvent: "nambouchara@host ghostty % "
        )
        let claudeDetection = detector.detect(
            current: claudeCurrent,
            previous: claudePrevious,
            lastOutcome: nil,
            lastEvent: "nambouchara@host ghostty % "
        )

        #expect(codexDetection?.identity == .codex)
        #expect(codexDetection?.interactionState == .unknown)
        #expect(codexDetection?.runtimeState == .idle)
        #expect(codexDetection?.context == AgentInteractionContext.none)

        #expect(claudeDetection?.identity == .claudeCode)
        #expect(claudeDetection?.interactionState == .unknown)
        #expect(claudeDetection?.runtimeState == .idle)
        #expect(claudeDetection?.context == AgentInteractionContext.none)
    }
}
