import Foundation
import Testing
@testable import Ghostty

struct CodexSessionMonitorTests {
    @Test
    func startIgnoresPreexistingMatchingSessionUntilFreshSessionAppears() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("codex-monitor-\(UUID().uuidString)")
        let sessionsBase = tmpDir.appendingPathComponent("sessions")
        let sessionDir = sessionsBase.appendingPathComponent("2026/05/23/stale-session")
        let sessionFile = sessionDir.appendingPathComponent("rollout-stale.jsonl")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let staleSession = """
        {"timestamp":"2026-05-23T01:00:00Z","type":"session_meta","payload":{"id":"old-session","cwd":"/tmp/project","originator":"codex-tui","cli_version":"0.133.0"}}
        {"timestamp":"2026-05-23T01:00:01Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","completed_at":1716426001,"duration_ms":1500}}
        """
        try staleSession.write(to: sessionFile, atomically: true, encoding: .utf8)
        let staleDate = Date().addingTimeInterval(-30)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: sessionFile.path)

        let monitor = CodexSessionMonitor(
            workingDirectory: "/tmp/project",
            sessionsBase: sessionsBase
        )

        monitor.start()
        defer { monitor.stop() }
        monitor.poll()

        #expect(
            monitor.records().isEmpty,
            "Fresh monitors should not inherit stale Codex sessions that existed before start."
        )
    }

    @Test
    func pollStaysBoundToResolvedSessionUntilMonitorIsRecreated() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("codex-monitor-\(UUID().uuidString)")
        let sessionsBase = tmpDir.appendingPathComponent("sessions")
        let firstSessionDir = sessionsBase.appendingPathComponent("2026/05/24/session-a")
        let secondSessionDir = sessionsBase.appendingPathComponent("2026/05/24/session-b")
        let firstSessionFile = firstSessionDir.appendingPathComponent("rollout-a.jsonl")
        let secondSessionFile = secondSessionDir.appendingPathComponent("rollout-b.jsonl")
        try FileManager.default.createDirectory(at: firstSessionDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSessionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var now = Date()
        let firstSession = """
        {"timestamp":"2026-05-24T01:00:00Z","type":"session_meta","payload":{"id":"session-a","cwd":"/tmp/project","originator":"codex-tui","cli_version":"0.133.0"}}
        {"timestamp":"2026-05-24T01:00:01Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-a","started_at":1716512401}}
        """ + "\n"
        try firstSession.write(to: firstSessionFile, atomically: true, encoding: .utf8)
        now = now.addingTimeInterval(1)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: firstSessionFile.path)

        let monitor = CodexSessionMonitor(
            workingDirectory: "/tmp/project",
            sessionsBase: sessionsBase,
            now: { now }
        )
        monitor.start()
        monitor.stop()
        monitor.poll()

        #expect(monitor.records().count == 2)
        #expect(monitor.records().last?.payload.turnId == "turn-a")

        let secondSession = """
        {"timestamp":"2026-05-24T01:00:02Z","type":"session_meta","payload":{"id":"session-b","cwd":"/tmp/project","originator":"codex-tui","cli_version":"0.133.0"}}
        {"timestamp":"2026-05-24T01:00:03Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-b","completed_at":1716512403,"duration_ms":1200}}
        """ + "\n"
        try secondSession.write(to: secondSessionFile, atomically: true, encoding: .utf8)
        now = now.addingTimeInterval(1)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: secondSessionFile.path)

        monitor.poll()

        #expect(monitor.records().count == 2)
        #expect(monitor.records().last?.payload.turnId == "turn-a")
    }
}
