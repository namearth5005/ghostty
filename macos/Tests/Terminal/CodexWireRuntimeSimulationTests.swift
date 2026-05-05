import Foundation
import Testing
@testable import Ghostty

struct CodexWireRuntimeSimulationTests {

    /// Tests that the engine correctly maps Codex task_complete to waiting state.
    @Test
    func codexTaskCompleteProducesWaitingState() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("codex-test-\(UUID().uuidString)")
        let sessionsDir = tmpDir.appendingPathComponent("sessions/2026/05/04/test-codex-session")
        let sessionFile = sessionsDir.appendingPathComponent("rollout-test.jsonl")

        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // Write a Codex session with task_started → task_complete sequence (trailing newline required)
        let sessionContent = "{\"timestamp\": \"2026-05-04T12:00:00Z\", \"type\": \"session_meta\", \"payload\": {\"id\": \"test-123\", \"cwd\": \"/tmp\", \"originator\": \"codex-tui\", \"cli_version\": \"0.128.0\"}}\n{\"timestamp\": \"2026-05-04T12:00:01Z\", \"type\": \"event_msg\", \"payload\": {\"type\": \"task_started\", \"turn_id\": \"turn-1\", \"started_at\": 1714828801}}\n{\"timestamp\": \"2026-05-04T12:00:10Z\", \"type\": \"event_msg\", \"payload\": {\"type\": \"task_complete\", \"turn_id\": \"turn-1\", \"completed_at\": 1714828810, \"duration_ms\": 9000}}\n"
        try sessionContent.write(to: sessionFile, atomically: true, encoding: .utf8)

        let monitor = CodexSessionMonitor(workingDirectory: "/tmp", sessionsBase: tmpDir.appendingPathComponent("sessions"))
        monitor.start()
        monitor.poll()

        let records = monitor.records()
        #expect(records.count >= 2, "Should have parsed at least session_meta + task_started + task_complete, got \(records.count)")

        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "test-terminal",
            windowID: "w1",
            tabID: "t1",
            title: "Codex",
            cwd: "/tmp",
            isFocused: true,
            visibleText: "codex",
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: [],
            codexWireRecords: records
        )

        #expect(understanding.agentIdentity == .codex, "Should detect Codex identity")
        #expect(understanding.agentInteractionState == .waitingText, "task_complete should map to waitingText, got \(understanding.agentInteractionState)")
        #expect(understanding.agentInteractionContext.typeString == "waitingText", "Context should be waitingText")

        monitor.stop()
    }
}
