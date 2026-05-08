import Foundation
import Testing
@testable import Ghostty

struct KimiWelcomeScreenTests {

    /// When Kimi first launches, the welcome screen should be classified as waitingText
    /// (not running), because the user hasn't typed anything yet.
    @Test
    func kimiWelcomeScreenIsWaitingText() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "test-terminal",
            windowID: "w1",
            tabID: "t1",
            title: "Kimi Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: """
            Welcome to Kimi Code CLI!
            Send /help for help information.

            Directory: ~
            Session: 3f27d18e-06d3-4610-8074-7cba5f709ffb
            Model: Kimi-k2.6

            Tip: Spot a bug or have feedback? Type /feedback right in this session — every report makes Kimi better.

            --- input ---
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: []   // no wire file yet — initial state
        )

        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.agentInteractionState == .waitingText,
                "Kimi welcome screen with no wire records should be waitingText, got \(understanding.agentInteractionState)")
        #expect(understanding.agentInteractionContext.typeString == "waitingText")
        #expect(understanding.state == .waiting)
    }

    /// Once wire records exist (e.g. StepBegin), the wire signal takes precedence.
    @Test
    func kimiWithWireRecordsUsesWireSignal() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "test-terminal",
            windowID: "w1",
            tabID: "t1",
            title: "Kimi Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: "Welcome to Kimi Code CLI!",
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let wireRecords = [
            KimiWireRecord(
                timestamp: 1714828800,
                message: KimiWireMessage(
                    type: "StepBegin",
                    payload: KimiWirePayload(
                        user_input: nil,
                        n: 1,
                        context_usage: nil,
                        context_tokens: nil,
                        max_context_tokens: nil,
                        plan_mode: nil,
                        id: nil,
                        tool_call_id: nil,
                        sender: nil,
                        action: nil,
                        description: nil,
                        display: nil,
                        questions: nil,
                        name: nil,
                        arguments: nil,
                        content: nil,
                        finish_reason: nil,
                        code: nil,
                        message: nil
                    )
                )
            )
        ]

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: wireRecords
        )

        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.agentInteractionState == .running,
                "Wire signal should override welcome heuristic when records exist")
    }

    @Test
    func kimiCompletedTurnWithClaudePathMentionRemainsKimiWaitingText() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "test-terminal",
            windowID: "w1",
            tabID: "t1",
            title: "Kimi Code",
            cwd: "/Users/nambouchara/speed2",
            isFocused: true,
            visibleText: """
            ✨ go to the mend directory please
            • Used Shell (cd /Users/nambouchara/speed2/mend && pwd && ls -la)
            • I'm now in the mend directory at /Users/nambouchara/speed2/mend.
              The directory contains:
              • .claude/ – Claude configuration
              • .git/ – Git repository
              • docs/ – Documentation

            ── input ─────────────────────────────────────────────────────────────────

            agent (Kimi-k2.6 ●)  ~/speed2  ctrl-v: paste clipboard | @: mention files
            context: 5.4% (14.3k/262.1k)
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: []
        )

        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.state == .waiting)
    }

    @Test
    func kimiTurnEndUsesPreviousTextContentAsWaitingQuestion() throws {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "test-terminal",
            windowID: "w1",
            tabID: "t1",
            title: "Kimi Code",
            cwd: "/Users/nambouchara/speed2",
            isFocused: true,
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
        let decoder = JSONDecoder()
        let records = try [
            """
            {"timestamp":1,"message":{"type":"ContentPart","payload":{"type":"text","text":"I'm now in the mend directory.\\n\\nWhat would you like to do here?"}}}
            """,
            """
            {"timestamp":2,"message":{"type":"TurnEnd","payload":{}}}
            """,
        ].map { line in
            try decoder.decode(KimiWireRecord.self, from: Data(line.utf8))
        }

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: records
        )

        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.agentInteractionContext.descriptionString == "What would you like to do here?")
    }
}
