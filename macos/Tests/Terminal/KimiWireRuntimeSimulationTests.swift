import Foundation
import Testing
@testable import Ghostty

struct KimiWireRuntimeSimulationTests {

    /// Simulates the exact runtime scenario: Kimi is running in /Users/nambouchara,
    /// the real wire file exists, and we exercise the full pipeline.
    @Test
    func realWireFileProducesWaitingState() async throws {
        let workingDir = "/Users/nambouchara"
        let engine = TerminalUnderstandingEngine()

        // Create a monitor using the REAL filesystem
        let monitor = KimiWireSessionMonitor(workingDirectory: workingDir)
        monitor.start()

        // Wait for the monitor to poll
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        let records = monitor.records()
        monitor.stop()

        // Create a snapshot that mimics a Kimi terminal
        let snapshot = TerminalSnapshot(
            terminalID: "term-kimi-test",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: workingDir,
            isFocused: true,
            captureMode: "shell",
            visibleText: "Hey! How can I help you today?\n-- input",
            recentScrollback: "",
            lastInputPreview: nil,
            runtime: .init(
                foregroundProcessID: nil,
                foregroundProcessName: "Kimi Code",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            signals: .init(
                likelyWaitingForInput: true,
                likelyLongRunning: false,
                likelyErrorState: false,
                likelyTUI: false
            )
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: records
        )

        // The engine should detect Kimi
        #expect(understanding.agentIdentity == .kimi, "Engine should detect Kimi identity")

        if records.isEmpty {
            // If no wire records, heuristics should classify as waitingText (because of -- input)
            #expect(understanding.agentInteractionState == .waitingText,
                    "With no wire records, heuristics should see -- input and classify as waitingText. Got \(understanding.agentInteractionState)")
        } else {
            // With wire records, the most recent actionable record should determine state
            #expect(understanding.agentInteractionState != .running,
                    "Wire records should NOT produce running state. Got \(understanding.agentInteractionState) with \(records.count) records")

            // Verify the context is not .running
            if case .running = understanding.agentInteractionContext {
                Issue.record("Context should not be .running with wire records. Records: \(records.map(\.message.type))")
            }
        }
    }
}
