import Foundation
import Testing
@testable import Ghostty

struct KimiWireAppendTests {

    /// Tests that the monitor picks up records appended after the initial read.
    @Test
    func monitorDetectsAppendedRecords() throws {
        let workingDir = "/tmp/kimi-append-test"
        let md5 = KimiWireSessionMonitor.md5Hash(workingDir)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".kimi/sessions/\(md5)")
        let sessionDir = sessionsDir.appendingPathComponent("append-test-session")
        let wirePath = sessionDir.appendingPathComponent("wire.jsonl")

        // Clean up
        try? FileManager.default.removeItem(at: sessionDir)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: sessionDir)
        }

        // Write initial records (trailing newline required for JSON Lines)
        let initialContent = "{\"timestamp\": 1.0, \"message\": {\"type\": \"TurnBegin\", \"payload\": {}}}\n{\"timestamp\": 2.0, \"message\": {\"type\": \"StepBegin\", \"payload\": {\"n\": 1}}}\n"
        try initialContent.write(to: wirePath, atomically: true, encoding: .utf8)

        let monitor = KimiWireSessionMonitor(workingDirectory: workingDir)
        monitor.start()

        // Poll immediately (no timer needed for unit test)
        monitor.poll()

        let records1 = monitor.records()
        #expect(records1.count == 2, "Should read initial 2 records, got \(records1.count)")

        // Append TurnEnd
        let appendHandle = try FileHandle(forWritingTo: wirePath)
        let newLine = "\n{\"timestamp\": 3.0, \"message\": {\"type\": \"TurnEnd\", \"payload\": {}}}\n"
        if #available(macOS 10.15.4, *) {
            try appendHandle.seekToEnd()
            try appendHandle.write(contentsOf: Data(newLine.utf8))
        } else {
            appendHandle.seekToEndOfFile()
            appendHandle.write(Data(newLine.utf8))
        }
        appendHandle.closeFile()

        // Poll again to pick up appended data
        monitor.poll()

        let records2 = monitor.records()
        #expect(records2.count == 3, "Should read 3 records after append, got \(records2.count). Buffer: \(records2.map(\.message.type))")

        // Verify TurnEnd is the last record
        if let last = records2.last {
            #expect(last.message.type == "TurnEnd")
        }

        monitor.stop()
    }
}
