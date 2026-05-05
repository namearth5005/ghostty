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
}
