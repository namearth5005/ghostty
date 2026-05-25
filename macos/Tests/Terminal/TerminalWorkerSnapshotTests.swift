import Foundation
import Testing
@testable import Ghostty

struct TerminalWorkerSnapshotTests {
    private func makeChoiceSnapshot() -> TerminalWorkerSnapshot {
        TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-2",
            workerSessionID: "kimi-session-9",
            revision: 12,
            observedAt: Date(timeIntervalSince1970: 1_748_111_111),
            ttlMilliseconds: 10_000,
            workerGoal: "compare the refactor options",
            agent: .init(identity: .kimi),
            state: .init(
                lifecycle: .blocked,
                attention: .choiceRequired,
                summary: "Kimi needs a refactor choice.",
                details: ["Two API directions are available."],
                runtimeFlags: [.planning]
            ),
            request: .init(
                id: "req-12",
                kind: .choice,
                prompt: "Which direction should I take?",
                options: [
                    .init(id: "keep_api", label: "Keep current API", recommended: true),
                    .init(id: "break_api", label: "Allow breaking change", recommended: false),
                ]
            ),
            suggestions: [
                .init(
                    id: "s2",
                    kind: .choice,
                    title: "Keep the current API",
                    payload: .option("keep_api"),
                    rationale: "Preserves compatibility while the refactor lands.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-12"
                ),
            ]
        )
    }

    @Test
    func recommendedSuggestionPrefersExplicitRecommendedFlag() throws {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-1",
            revision: 7,
            observedAt: Date(timeIntervalSince1970: 1_748_000_000),
            ttlMilliseconds: 15_000,
            workerGoal: "investigate auth failures",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for a reply.",
                details: ["Asked whether the API should stay stable."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-7",
                kind: .reply,
                prompt: "Should I preserve the current API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "s0",
                    kind: .reply,
                    title: "Break the API",
                    payload: .text("Change the API now and accept migration work."),
                    rationale: "Fastest route to the new internals.",
                    recommended: false,
                    execution: .manualOnly,
                    requestID: "req-7"
                ),
                .init(
                    id: "s1",
                    kind: .reply,
                    title: "Preserve the API",
                    payload: .text("Preserve the current API and adapt the internals."),
                    rationale: "Lowest migration risk.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-7"
                ),
            ]
        )

        #expect(snapshot.recommendedSuggestion?.id == "s1")
        #expect(snapshot.attentionFingerprint == "codex-session-1|7|req-7")
    }

    @Test
    func snapshotRoundTripsThroughJSON() throws {
        let snapshot = makeChoiceSnapshot()

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalWorkerSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.suggestions.first?.payload == .option("keep_api"))
    }

    @Test
    func snapshotEncodesStableWireShape() throws {
        let snapshot = makeChoiceSnapshot()
        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["schema_version"] as? Int == 1)
        #expect(object["terminal_id"] as? String == "term-2")
        #expect(object["worker_session_id"] as? String == "kimi-session-9")
        #expect(object["ttl_ms"] as? Int == 10_000)
        #expect(object["worker_goal"] as? String == "compare the refactor options")

        let state = try #require(object["state"] as? [String: Any])
        #expect(state["runtime_flags"] as? [String] == ["planning"])

        let request = try #require(object["request"] as? [String: Any])
        #expect(request["kind"] as? String == "choice")
        #expect(request["prompt"] as? String == "Which direction should I take?")

        let suggestions = try #require(object["suggestions"] as? [[String: Any]])
        let firstSuggestion = try #require(suggestions.first)
        #expect(firstSuggestion["kind"] as? String == "choice")
        #expect(firstSuggestion["request_id"] as? String == "req-12")

        let payload = try #require(firstSuggestion["payload"] as? [String: String])
        #expect(payload.count == 1)
        #expect(payload["option"] == "keep_api")
    }

    @Test
    func decodingRejectsSuggestionKindPayloadMismatch() throws {
        let json = """
        {
          "schema_version": 1,
          "terminal_id": "term-3",
          "worker_session_id": "codex-session-4",
          "revision": 4,
          "observed_at": 1748111111,
          "ttl_ms": 15000,
          "worker_goal": "choose the API direction",
          "agent": {
            "identity": "codex"
          },
          "state": {
            "lifecycle": "running",
            "attention": "choice_required",
            "summary": "Codex is waiting on a choice.",
            "details": [],
            "runtime_flags": []
          },
          "request": {
            "id": "req-4",
            "kind": "choice",
            "prompt": "Which direction should I take?",
            "options": []
          },
          "suggestions": [
            {
              "id": "s4",
              "kind": "choice",
              "title": "Run the migration",
              "payload": {
                "command": "pnpm migrate"
              },
              "rationale": "Move forward quickly.",
              "recommended": true,
              "execution": "manual_only",
              "request_id": "req-4"
            }
          ]
        }
        """

        let data = try #require(json.data(using: .utf8))

        do {
            _ = try JSONDecoder().decode(TerminalWorkerSnapshot.self, from: data)
            Issue.record("Expected mismatched suggestion kind and payload to fail decoding.")
        } catch {
            #expect(error is DecodingError)
        }
    }
}
