import Foundation
import Testing
@testable import Ghostty

struct TerminalWorkerSnapshotTests {
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
        let snapshot = TerminalWorkerSnapshot(
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
            suggestions: []
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalWorkerSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }
}
