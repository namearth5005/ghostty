import Foundation
import Testing
@testable import Ghostty

struct ClaudeWireRuntimeSimulationTests {

    /// Tests that the engine correctly maps Claude session status to agent state.
    @Test
    func claudeIdleStatusProducesWaitingState() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-test-\(UUID().uuidString)")
        let sessionsDir = tmpDir.appendingPathComponent("sessions")

        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // Write a Claude session file with status "idle"
        let sessionContent = "{\"pid\": 12345, \"sessionId\": \"test-session\", \"cwd\": \"/tmp\", \"status\": \"idle\", \"updatedAt\": 1714828801000, \"startedAt\": 1714828800000, \"version\": \"2.1.128\", \"kind\": \"interactive\"}"
        let sessionFile = sessionsDir.appendingPathComponent("12345.json")
        try sessionContent.write(to: sessionFile, atomically: true, encoding: .utf8)

        let monitor = ClaudeSessionMonitor(pid: 12345, sessionsBase: sessionsDir)
        monitor.start()
        monitor.poll()

        let records = monitor.records()
        #expect(records.count == 1, "Should have parsed one session state, got \(records.count)")
        #expect(records.first?.status == "idle")

        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "test-terminal",
            windowID: "w1",
            tabID: "t1",
            title: "Claude",
            cwd: "/tmp",
            isFocused: true,
            visibleText: "claude",
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: [],
            codexWireRecords: [],
            claudeWireRecords: records
        )

        #expect(understanding.agentIdentity == .claudeCode, "Should detect Claude identity")
        #expect(understanding.agentInteractionState == .waitingText, "idle status should map to waitingText, got \(understanding.agentInteractionState)")
        #expect(understanding.agentInteractionContext.typeString == "waitingText", "Context should be waitingText")

        monitor.stop()
    }

    /// Tests that the engine correctly maps Claude "working" status to running state.
    @Test
    func claudeWorkingStatusProducesRunningState() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-test-\(UUID().uuidString)")
        let sessionsDir = tmpDir.appendingPathComponent("sessions")

        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        let sessionContent = "{\"pid\": 12346, \"sessionId\": \"test-session-2\", \"cwd\": \"/tmp\", \"status\": \"working\", \"updatedAt\": 1714828801000, \"startedAt\": 1714828800000, \"version\": \"2.1.128\", \"kind\": \"interactive\"}"
        let sessionFile = sessionsDir.appendingPathComponent("12346.json")
        try sessionContent.write(to: sessionFile, atomically: true, encoding: .utf8)

        let monitor = ClaudeSessionMonitor(pid: 12346, sessionsBase: sessionsDir)
        monitor.start()
        monitor.poll()

        let records = monitor.records()
        #expect(records.count == 1)
        #expect(records.first?.status == "working")

        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "test-terminal-2",
            windowID: "w1",
            tabID: "t1",
            title: "Claude",
            cwd: "/tmp",
            isFocused: true,
            visibleText: "claude",
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: [],
            codexWireRecords: [],
            claudeWireRecords: records
        )

        #expect(understanding.agentIdentity == .claudeCode)
        #expect(understanding.agentInteractionState == .running, "working status should map to running, got \(understanding.agentInteractionState)")
        #expect(understanding.agentInteractionContext.typeString == "running")

        monitor.stop()
    }
}
