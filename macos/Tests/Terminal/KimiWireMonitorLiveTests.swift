import Foundation
import Testing
@testable import Ghostty

struct KimiWireMonitorLiveTests {

    /// Tests the actual monitor against the real filesystem in ~/.kimi/sessions/
    @Test
    func monitorReadsRealWireFile() throws {
        let workingDir = "/tmp/kimi-monitor-live-test"
        let md5 = KimiWireSessionMonitor.md5Hash(workingDir)
        let sessionID = "live-test-\(UUID().uuidString.prefix(8))"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".kimi/sessions/\(md5)")
        let sessionDir = sessionsDir.appendingPathComponent(sessionID)
        let wirePath = sessionDir.appendingPathComponent("wire.jsonl")

        // Clean up any previous test artifacts
        try? FileManager.default.removeItem(at: sessionDir)

        // Create the session directory and wire file (proper JSON Lines with trailing newline)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let wireContent = "{\"timestamp\": 1.0, \"message\": {\"type\": \"TurnBegin\", \"payload\": {}}}\n{\"timestamp\": 2.0, \"message\": {\"type\": \"TurnEnd\", \"payload\": {}}}\n"
        try wireContent.write(to: wirePath, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: sessionDir)
        }

        // Create and start monitor, then poll immediately
        let monitor = KimiWireSessionMonitor(workingDirectory: workingDir)
        monitor.start()
        monitor.poll()

        let records = monitor.records()
        #expect(records.count == 2, "Expected 2 records, got \(records.count). Monitor may not have found the file.")

        if let last = records.last {
            #expect(last.message.type == "TurnEnd")
        }

        monitor.stop()
    }

    /// Tests that the monitor picks the most recently modified wire file
    @Test
    func monitorPicksMostRecentSession() throws {
        let workingDir = "/tmp/kimi-monitor-recent-test"
        let md5 = KimiWireSessionMonitor.md5Hash(workingDir)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".kimi/sessions/\(md5)")

        // Clean up
        try? FileManager.default.removeItem(at: sessionsDir)

        let oldSession = sessionsDir.appendingPathComponent("old-session")
        let newSession = sessionsDir.appendingPathComponent("new-session")
        try FileManager.default.createDirectory(at: oldSession, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newSession, withIntermediateDirectories: true)

        let oldWire = oldSession.appendingPathComponent("wire.jsonl")
        let newWire = newSession.appendingPathComponent("wire.jsonl")

        try "{\"timestamp\": 1.0, \"message\": {\"type\": \"TurnBegin\", \"payload\": {}}}\n".write(to: oldWire, atomically: true, encoding: .utf8)
        try "{\"timestamp\": 2.0, \"message\": {\"type\": \"TurnEnd\", \"payload\": {}}}\n".write(to: newWire, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: sessionsDir)
        }

        let monitor = KimiWireSessionMonitor(workingDirectory: workingDir)
        monitor.start()
        monitor.poll()

        let records = monitor.records()
        #expect(records.count == 1)
        if let record = records.first {
            #expect(record.message.type == "TurnEnd", "Monitor should pick the most recent session (TurnEnd), not the old one (TurnBegin)")
        }

        monitor.stop()
    }
}
