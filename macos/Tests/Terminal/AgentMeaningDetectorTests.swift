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
}
