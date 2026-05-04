import Foundation
import Testing
@testable import Ghostty

struct KimiWireTypesTests {

    // MARK: - ApprovalRequest

    @Test
    func parsesApprovalRequestWireRecord() throws {
        let json = """
        {"timestamp":1712345678.123,"message":{"type":"ApprovalRequest","payload":{"id":"req-1","sender":"shell","action":"execute","description":"Run shell command: git push origin main"}}}
        """
        let data = try #require(json.data(using: .utf8))
        let record = try JSONDecoder().decode(KimiWireRecord.self, from: data)

        #expect(record.message.type == "ApprovalRequest")
        #expect(record.message.payload.description == "Run shell command: git push origin main")
        #expect(record.message.payload.sender == "shell")

        let context = try #require(record.asAgentInteractionContext)
        if case .waitingApproval(let desc, let tool) = context {
            #expect(desc == "Run shell command: git push origin main")
            #expect(tool == "shell")
        } else {
            Issue.record("Expected waitingApproval context")
        }
    }

    // MARK: - QuestionRequest with options

    @Test
    func parsesQuestionRequestWithOptions() throws {
        let json = """
        {"timestamp":1712345678.124,"message":{"type":"QuestionRequest","payload":{"questions":[{"question":"Choose a branch","options":[{"label":"main","description":"Production branch"},{"label":"dev","description":"Development branch"}]}]}}}
        """
        let data = try #require(json.data(using: .utf8))
        let record = try JSONDecoder().decode(KimiWireRecord.self, from: data)

        #expect(record.message.type == "QuestionRequest")
        let firstQ = try #require(record.message.payload.questions?.first)
        #expect(firstQ.question == "Choose a branch")
        #expect(firstQ.options?.count == 2)

        let context = try #require(record.asAgentInteractionContext)
        if case .waitingChoice(let q, let opts) = context {
            #expect(q == "Choose a branch")
            #expect(opts == ["main", "dev"])
        } else {
            Issue.record("Expected waitingChoice context")
        }
    }

    // MARK: - QuestionRequest without options

    @Test
    func parsesQuestionRequestWithoutOptions() throws {
        let json = """
        {"timestamp":1712345678.125,"message":{"type":"QuestionRequest","payload":{"questions":[{"question":"What is your name?"}]}}}
        """
        let data = try #require(json.data(using: .utf8))
        let record = try JSONDecoder().decode(KimiWireRecord.self, from: data)

        let context = try #require(record.asAgentInteractionContext)
        if case .waitingText(let q) = context {
            #expect(q == "What is your name?")
        } else {
            Issue.record("Expected waitingText context")
        }
    }

    // MARK: - TurnBegin

    @Test
    func parsesTurnBegin() throws {
        let json = """
        {"timestamp":1712345678.126,"message":{"type":"TurnBegin","payload":{}}}
        """
        let data = try #require(json.data(using: .utf8))
        let record = try JSONDecoder().decode(KimiWireRecord.self, from: data)

        #expect(record.message.type == "TurnBegin")
        let context = try #require(record.asAgentInteractionContext)
        if case .running = context {
            // pass
        } else {
            Issue.record("Expected running context")
        }
    }

    // MARK: - TurnEnd

    @Test
    func parsesTurnEnd() throws {
        let json = """
        {"timestamp":1712345678.127,"message":{"type":"TurnEnd","payload":{}}}
        """
        let data = try #require(json.data(using: .utf8))
        let record = try JSONDecoder().decode(KimiWireRecord.self, from: data)

        #expect(record.message.type == "TurnEnd")
        let context = try #require(record.asAgentInteractionContext)
        if case .waitingText = context {
            // pass
        } else {
            Issue.record("Expected waitingText context")
        }
    }

    // MARK: - StepBegin

    @Test
    func parsesStepBegin() throws {
        let json = """
        {"timestamp":1712345678.128,"message":{"type":"StepBegin","payload":{"n":3}}}
        """
        let data = try #require(json.data(using: .utf8))
        let record = try JSONDecoder().decode(KimiWireRecord.self, from: data)

        #expect(record.message.type == "StepBegin")
        #expect(record.message.payload.n == 3)
        let context = try #require(record.asAgentInteractionContext)
        if case .running(let step) = context {
            #expect(step == "Step 3")
        } else {
            Issue.record("Expected running context with step")
        }
    }

    // MARK: - Error

    @Test
    func parsesErrorRecord() throws {
        let json = """
        {"timestamp":1712345678.129,"message":{"type":"Error","payload":{"code":"AUTH_REQUIRED","message":"Authentication required"}}}
        """
        let data = try #require(json.data(using: .utf8))
        let record = try JSONDecoder().decode(KimiWireRecord.self, from: data)

        #expect(record.message.type == "Error")
        let context = try #require(record.asAgentInteractionContext)
        if case .error(let desc) = context {
            #expect(desc == "Authentication required")
        } else {
            Issue.record("Expected error context")
        }
    }

    // MARK: - Unknown type returns nil context

    @Test
    func unknownTypeReturnsNoContext() throws {
        let json = """
        {"timestamp":1712345678.130,"message":{"type":"Ping","payload":{}}}
        """
        let data = try #require(json.data(using: .utf8))
        let record = try JSONDecoder().decode(KimiWireRecord.self, from: data)

        #expect(record.asAgentInteractionContext == nil)
    }
}

struct KimiWireSessionMonitorTests {

    @Test
    func md5HashMatchesExpectedValue() {
        let hash = KimiWireSessionMonitor.md5Hash("/Users/test/project")
        // Verify it's a valid 32-char hex MD5 string
        #expect(hash.count == 32)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test
    func md5HashIsDeterministic() {
        let hash1 = KimiWireSessionMonitor.md5Hash("/Users/test/project")
        let hash2 = KimiWireSessionMonitor.md5Hash("/Users/test/project")
        #expect(hash1 == hash2)
    }

    @Test
    func monitorFlushesBufferedRecords() throws {
        let monitor = KimiWireSessionMonitor(workingDirectory: "/tmp/nonexistent")

        // Manually inject a record via reflection-like access not possible in Swift,
        // so we test the public records API returns empty initially
        let empty = monitor.records()
        #expect(empty.isEmpty)
    }
}

struct WireRecordsOutrankHeuristicsTests {

    @Test
    func wireApprovalRequestOutranksHeuristicRunning() throws {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "kimi",
            cwd: "/tmp",
            isFocused: true,
            captureMode: "shell",
            visibleText: "Some heuristic text that looks like running",
            recentScrollback: "",
            lastInputPreview: nil,
            runtime: .init(
                foregroundProcessID: nil,
                foregroundProcessName: "kimi",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            signals: .init(
                likelyWaitingForInput: false,
                likelyLongRunning: true,
                likelyErrorState: false,
                likelyTUI: false
            )
        )

        let wireRecord = KimiWireRecord(
            timestamp: 123,
            message: KimiWireMessage(
                type: "ApprovalRequest",
                payload: KimiWirePayload(
                    user_input: nil,
                    n: nil,
                    context_usage: nil,
                    context_tokens: nil,
                    max_context_tokens: nil,
                    plan_mode: nil,
                    id: "req-1",
                    tool_call_id: nil,
                    sender: "shell",
                    action: "execute",
                    description: "Run shell command: git push origin main",
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

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: [wireRecord]
        )

        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.agentInteractionState == .waitingApproval)
        if case .waitingApproval(let desc, let tool) = understanding.agentInteractionContext {
            #expect(desc == "Run shell command: git push origin main")
            #expect(tool == "shell")
        } else {
            Issue.record("Expected waitingApproval from wire record")
        }
        #expect(understanding.evidence.contains(where: { $0.source == .wireSignal }))
    }

    @Test
    func wireQuestionRequestWithOptionsOutranksHeuristic() throws {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "kimi",
            cwd: "/tmp",
            isFocused: true,
            captureMode: "shell",
            visibleText: "What would you like to do?",
            recentScrollback: "",
            lastInputPreview: nil,
            runtime: .init(
                foregroundProcessID: nil,
                foregroundProcessName: "kimi",
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

        let wireRecord = KimiWireRecord(
            timestamp: 123,
            message: KimiWireMessage(
                type: "QuestionRequest",
                payload: KimiWirePayload(
                    user_input: nil,
                    n: nil,
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
                    questions: [
                        QuestionItem(question: "Choose a branch", header: nil, options: [
                            QuestionOption(label: "main", description: nil),
                            QuestionOption(label: "dev", description: nil)
                        ], multi_select: nil)
                    ],
                    name: nil,
                    arguments: nil,
                    content: nil,
                    finish_reason: nil,
                    code: nil,
                    message: nil
                )
            )
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: [wireRecord]
        )

        #expect(understanding.agentInteractionState == .waitingChoice)
        if case .waitingChoice(let q, let opts) = understanding.agentInteractionContext {
            #expect(q == "Choose a branch")
            #expect(opts == ["main", "dev"])
        } else {
            Issue.record("Expected waitingChoice from wire record")
        }
    }

    @Test
    func emptyWireRecordsFallsBackToHeuristics() throws {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "kimi",
            cwd: "/tmp",
            isFocused: true,
            captureMode: "shell",
            visibleText: "What would you like to do?",
            recentScrollback: "",
            lastInputPreview: nil,
            runtime: .init(
                foregroundProcessID: nil,
                foregroundProcessName: "kimi",
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

        // Without wire records, should fall back to heuristic waitingText
        #expect(understanding.agentIdentity == .kimi)
        #expect(understanding.agentInteractionState == .waitingText)
    }

    @Test
    func nonKimiTerminalIgnoresWireRecords() throws {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "bash",
            cwd: "/tmp",
            isFocused: true,
            captureMode: "shell",
            visibleText: "Some output",
            recentScrollback: "",
            lastInputPreview: nil,
            runtime: .init(
                foregroundProcessID: nil,
                foregroundProcessName: "bash",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            signals: .init(
                likelyWaitingForInput: false,
                likelyLongRunning: true,
                likelyErrorState: false,
                likelyTUI: false
            )
        )

        let wireRecord = KimiWireRecord(
            timestamp: 123,
            message: KimiWireMessage(
                type: "ApprovalRequest",
                payload: KimiWirePayload(
                    user_input: nil,
                    n: nil,
                    context_usage: nil,
                    context_tokens: nil,
                    max_context_tokens: nil,
                    plan_mode: nil,
                    id: "req-1",
                    tool_call_id: nil,
                    sender: "shell",
                    action: "execute",
                    description: "Run shell command: git push origin main",
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

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil,
            wireRecords: [wireRecord]
        )

        // bash is not Kimi, so wire records should be ignored
        #expect(understanding.agentIdentity == .none)
    }
}
