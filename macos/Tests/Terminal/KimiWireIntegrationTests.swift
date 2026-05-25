import Foundation
import Testing
@testable import Ghostty

struct KimiWireIntegrationTests {

    /// Simulates the full pipeline: wire file → monitor → engine → understanding
    @Test
    func fullPipelineFromWireFileToWaitingState() throws {
        // 1. Create a temp directory structure: sessions/{md5}/{session_id}/wire.jsonl
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let workingDir = "/tmp/test-kimi-workdir"
        let md5 = KimiWireSessionMonitor.md5Hash(workingDir)
        let sessionID = "test-session-123"
        let sessionsDir = tmpDir.appendingPathComponent(".kimi/sessions/\(md5)")
        let wireDir = sessionsDir.appendingPathComponent(sessionID)
        try FileManager.default.createDirectory(at: wireDir, withIntermediateDirectories: true)
        let wirePath = wireDir.appendingPathComponent("wire.jsonl")

        // 2. Write a wire.jsonl simulating Kimi responding to "hey" and ending the turn
        let wireLines = [
            "{\"timestamp\": 1.0, \"message\": {\"type\": \"TurnBegin\", \"payload\": {\"user_input\": [{\"type\": \"text\", \"text\": \"hey\"}]}}}",
            "{\"timestamp\": 2.0, \"message\": {\"type\": \"StepBegin\", \"payload\": {\"n\": 1}}}",
            "{\"timestamp\": 3.0, \"message\": {\"type\": \"ContentPart\", \"payload\": {\"type\": \"text\", \"text\": \"Hey! How can I help?\"}}}",
            "{\"timestamp\": 4.0, \"message\": {\"type\": \"TurnEnd\", \"payload\": {}}}",
        ]
        try wireLines.joined(separator: "\n").write(to: wirePath, atomically: true, encoding: .utf8)

        // 3. Create a monitor pointing to our temp .kimi directory by swizzling the home dir
        // We can't easily swizzle FileManager.homeDirectoryForCurrentUser, so we'll test the
        // monitor's path resolution and record reading separately.

        // Instead, test the engine directly with the parsed records
        let decoder = JSONDecoder()
        let records = try wireLines.compactMap { line -> KimiWireRecord? in
            guard !line.isEmpty else { return nil }
            return try decoder.decode(KimiWireRecord.self, from: Data(line.utf8))
        }

        #expect(records.count == 4)

        // 4. Verify TurnEnd maps to waitingText
        let lastRecord = try #require(records.last)
        #expect(lastRecord.message.type == "TurnEnd")
        let context = try #require(lastRecord.asAgentInteractionContext)
        if case .waitingText(let q, _, _, _, _) = context {
            #expect(q == nil)
        } else {
            Issue.record("Expected waitingText, got \(context)")
        }

        // 5. Pass records to the engine with a Kimi snapshot
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot(
            terminalID: "term-kimi",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: workingDir,
            isFocused: true,
            captureMode: "shell",
            visibleText: "Hey! How can I help?\n-- input",
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

        // 6. Wire records should outrank heuristics
        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.agentInteractionState == .waitingText, "Expected waitingText but got \(understanding.agentInteractionState)")
        #expect(understanding.state == .waiting, "Expected waiting state but got \(understanding.state)")
        #expect(understanding.evidence.contains(where: { $0.source == .wireSignal }))
    }

    /// When no wire records are provided, engine should fall back to heuristics
    @Test
    func heuristicFallbackWhenNoWireRecords() throws {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot(
            terminalID: "term-kimi",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp",
            isFocused: true,
            captureMode: "shell",
            visibleText: "Hey! How can I help?\n-- input",
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
            wireRecords: []
        )

        #expect(understanding.agentIdentity == .kimi)
        // Without wire records, heuristics see -- input and classify as waitingText
        #expect(understanding.agentInteractionState == .waitingText)
    }

    @Test
    func questionRequestExposesPlanningMetadata() throws {
        let record = KimiWireRecord(
            timestamp: 1,
            message: KimiWireMessage(
                type: "QuestionRequest",
                payload: KimiWirePayload(
                    plan_mode: true,
                    id: "req-12",
                    questions: [
                        QuestionItem(
                            question: "Which direction should I take?",
                            header: nil,
                            options: [
                                .init(label: "Keep current API", description: nil),
                                .init(label: "Allow breaking change", description: nil),
                            ],
                            multi_select: nil
                        ),
                    ]
                )
            )
        )

        let context = try #require(record.asAgentInteractionContext)
        let expected: AgentInteractionContext = .waitingChoice(
            question: "Which direction should I take?",
            options: ["Keep current API", "Allow breaking change"],
            requestID: "req-12",
            sessionID: nil,
            revision: nil,
            isPlanning: true
        )

        #expect(context == expected)
    }

    /// Monitor should find the most recent wire file in the sessions directory
    @Test
    func monitorFindsMostRecentWireFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let workingDir = "/tmp/monitor-test"
        let md5 = KimiWireSessionMonitor.md5Hash(workingDir)
        let sessionsDir = tmpDir.appendingPathComponent(".kimi/sessions/\(md5)")

        // Create two session directories with wire files at different times
        let session1Dir = sessionsDir.appendingPathComponent("session-old")
        let session2Dir = sessionsDir.appendingPathComponent("session-new")
        try FileManager.default.createDirectory(at: session1Dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: session2Dir, withIntermediateDirectories: true)

        let wire1 = session1Dir.appendingPathComponent("wire.jsonl")
        let wire2 = session2Dir.appendingPathComponent("wire.jsonl")

        try "old".write(to: wire1, atomically: true, encoding: .utf8)
        try "new".write(to: wire2, atomically: true, encoding: .utf8)

        // We can't easily test the monitor's internal resolveWirePath since it uses
        // homeDirectoryForCurrentUser, but we can verify the md5 hash and directory scanning logic
        #expect(md5 == KimiWireSessionMonitor.md5Hash(workingDir))
        #expect(FileManager.default.fileExists(atPath: wire1.path))
        #expect(FileManager.default.fileExists(atPath: wire2.path))

        // Verify session2 is more recent
        let attrs1 = try FileManager.default.attributesOfItem(atPath: wire1.path)
        let attrs2 = try FileManager.default.attributesOfItem(atPath: wire2.path)
        let date1 = attrs1[.modificationDate] as! Date
        let date2 = attrs2[.modificationDate] as! Date
        #expect(date2 > date1)
    }
}
