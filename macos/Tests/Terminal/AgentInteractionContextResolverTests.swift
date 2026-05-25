import Foundation
import Testing
@testable import Ghostty

struct AgentInteractionContextResolverTests {
    private let resolver = AgentInteractionContextResolver()

    private func decodeCodexRecord(_ json: String) throws -> CodexWireRecord {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(CodexWireRecord.self, from: data)
    }

    @Test
    func kimiTurnEndUsesLatestQuestionTextForWaitingContext() throws {
        let records = [
            KimiWireRecord(
                timestamp: 1,
                message: KimiWireMessage(
                    type: "ContentPart",
                    payload: KimiWirePayload(
                        type: "text",
                        text: """
                        I found two possible approaches.
                        Which one should I try next?
                        """
                    )
                )
            ),
            KimiWireRecord(
                timestamp: 2,
                message: KimiWireMessage(
                    type: "TurnEnd",
                    payload: KimiWirePayload()
                )
            ),
        ]

        let resolved = try #require(resolver.resolveKimi(from: records))
        let expected: AgentInteractionContext = .waitingText(question: "Which one should I try next?")

        #expect(resolved.context == expected)
        #expect(resolved.detail == "Wire record: TurnEnd")
    }

    @Test
    func kimiQuestionRequestPreservesRequestIDAndPlanningFlag() throws {
        let records = [
            KimiWireRecord(
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
            ),
        ]

        let resolved = try #require(resolver.resolveKimi(from: records))
        let expected: AgentInteractionContext = .waitingChoice(
            question: "Which direction should I take?",
            options: ["Keep current API", "Allow breaking change"],
            requestID: "req-12",
            sessionID: nil,
            revision: nil,
            isPlanning: true
        )

        #expect(resolved.context == expected)
        #expect(resolved.context.requestID == "req-12")
        #expect(resolved.context.isPlanning)
    }

    @Test
    func codexUsesLatestActionableWireRecord() throws {
        let records = [
            try decodeCodexRecord("""
            {"timestamp":"1","type":"event_msg","payload":{"type":"task_started"}}
            """),
            try decodeCodexRecord("""
            {"timestamp":"2","type":"event_msg","payload":{"type":"turn_aborted","reason":"User cancelled the turn"}}
            """),
        ]

        let resolved = try #require(resolver.resolveCodex(from: records))
        let expected: AgentInteractionContext = .error(description: "User cancelled the turn")

        #expect(resolved.context == expected)
        #expect(resolved.detail == "Codex wire: turn_aborted")
    }

    @Test
    func claudeMapsApprovalStatusToApprovalContext() throws {
        let states = [
            ClaudeSessionState(
                pid: 42,
                sessionId: "session-1",
                cwd: "/tmp/project",
                status: "working",
                updatedAt: 100,
                startedAt: 10,
                version: "1.0",
                kind: "cli"
            ),
            ClaudeSessionState(
                pid: 42,
                sessionId: "session-1",
                cwd: "/tmp/project",
                status: "waiting_for_approval",
                updatedAt: 101,
                startedAt: 10,
                version: "1.0",
                kind: "cli"
            ),
        ]

        let resolved = try #require(resolver.resolveClaude(from: states))
        let expected: AgentInteractionContext = .waitingApproval(description: "", tool: nil)

        #expect(resolved.context == expected)
        #expect(resolved.detail == "Claude status: waiting_for_approval")
    }
}
