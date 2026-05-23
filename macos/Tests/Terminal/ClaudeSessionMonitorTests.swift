import Foundation
import Testing
@testable import Ghostty

struct ClaudeSessionMonitorTests {

    @Test
    func fallbackScanIgnoresUnrelatedRecentSessionWhenPidFileMissing() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-monitor-\(UUID().uuidString)")
        let sessionsDir = tmpDir.appendingPathComponent("sessions")

        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        let unrelatedFile = sessionsDir.appendingPathComponent("11111.json")
        let unrelatedContent = """
        {"pid":11111,"sessionId":"other","cwd":"/tmp/other","status":"idle","updatedAt":1714828801000,"startedAt":1714828800000,"version":"2.1.128","kind":"interactive"}
        """
        try unrelatedContent.write(to: unrelatedFile, atomically: true, encoding: .utf8)

        let recentDate = Date()
        try FileManager.default.setAttributes([.modificationDate: recentDate], ofItemAtPath: unrelatedFile.path)

        let monitor = ClaudeSessionMonitor(
            pid: 99999,
            workingDirectory: "/tmp/project",
            sessionsBase: sessionsDir,
            now: { recentDate }
        )
        monitor.start()
        monitor.poll()

        #expect(
            monitor.records().isEmpty,
            "Monitor should ignore unrelated fallback sessions when the PID file is missing."
        )

        monitor.stop()
    }

    @Test
    func fallbackScanAcceptsFreshMatchingSessionWhenPidFileMissing() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-monitor-\(UUID().uuidString)")
        let sessionsDir = tmpDir.appendingPathComponent("sessions")

        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        let matchingFile = sessionsDir.appendingPathComponent("22222.json")
        let matchingContent = """
        {"pid":22222,"sessionId":"match","cwd":"/tmp/project","status":"working","updatedAt":1714828801000,"startedAt":1714828800000,"version":"2.1.128","kind":"interactive"}
        """
        try matchingContent.write(to: matchingFile, atomically: true, encoding: .utf8)

        let recentDate = Date()
        try FileManager.default.setAttributes([.modificationDate: recentDate], ofItemAtPath: matchingFile.path)

        let monitor = ClaudeSessionMonitor(
            pid: 99999,
            workingDirectory: "/tmp/project",
            sessionsBase: sessionsDir,
            now: { recentDate }
        )
        monitor.start()
        monitor.poll()

        let records = monitor.records()
        #expect(records.count == 1)
        #expect(records.first?.pid == 22222)
        #expect(records.first?.status == "working")

        monitor.stop()
    }

    @Test
    func fallbackScanStaysBoundToResolvedSessionUntilMonitorIsRecreated() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-monitor-\(UUID().uuidString)")
        let sessionsDir = tmpDir.appendingPathComponent("sessions")

        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        var now = Date()
        let firstFile = sessionsDir.appendingPathComponent("22222.json")
        let firstContent = """
        {"pid":22222,"sessionId":"match-a","cwd":"/tmp/project","status":"idle","updatedAt":1714828801000,"startedAt":1714828800000,"version":"2.1.128","kind":"interactive"}
        """
        try firstContent.write(to: firstFile, atomically: true, encoding: .utf8)
        now = now.addingTimeInterval(1)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: firstFile.path)

        let monitor = ClaudeSessionMonitor(
            pid: nil,
            workingDirectory: "/tmp/project",
            sessionsBase: sessionsDir,
            now: { now }
        )
        monitor.start()
        monitor.stop()
        monitor.poll()

        #expect(monitor.records().count == 1)
        #expect(monitor.records().first?.pid == 22222)
        #expect(monitor.records().first?.status == "idle")

        let secondFile = sessionsDir.appendingPathComponent("33333.json")
        let secondContent = """
        {"pid":33333,"sessionId":"match-b","cwd":"/tmp/project","status":"working","updatedAt":1714828802000,"startedAt":1714828800000,"version":"2.1.128","kind":"interactive"}
        """
        try secondContent.write(to: secondFile, atomically: true, encoding: .utf8)
        now = now.addingTimeInterval(1)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: secondFile.path)

        monitor.poll()

        #expect(monitor.records().count == 1)
        #expect(monitor.records().first?.pid == 22222)
        #expect(monitor.records().first?.status == "idle")
    }
}
