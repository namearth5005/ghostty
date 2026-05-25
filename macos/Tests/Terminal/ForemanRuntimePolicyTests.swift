import Foundation
import Testing
@testable import Ghostty

struct ForemanRuntimePolicyTests {
    @Test
    func planningSnapshotBlocksAutonomousContinuation() {
        let policy = ForemanRuntimePolicy()
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "kimi-session-12",
            revision: 12,
            observedAt: Date(timeIntervalSince1970: 1_748_333_333),
            ttlMilliseconds: 15_000,
            workerGoal: "compare API directions",
            agent: .init(identity: .kimi),
            state: .init(
                lifecycle: .running,
                attention: .choiceRequired,
                summary: "Kimi is waiting in plan mode.",
                details: ["Two API directions are available."],
                runtimeFlags: [.planning]
            ),
            request: .init(
                id: "req-12",
                kind: .choice,
                prompt: "Which direction should I take?",
                options: [
                    .init(id: "1", label: "Keep current API", recommended: true),
                    .init(id: "2", label: "Allow breaking change", recommended: false),
                ]
            ),
            suggestions: [
                .init(
                    id: "keep-api",
                    kind: .choice,
                    title: "Keep current API",
                    payload: .option("1"),
                    rationale: "Lowest migration risk.",
                    recommended: true,
                    execution: .autonomousOK,
                    requestID: "req-12"
                ),
            ]
        )

        let decision = policy.continuationDecision(
            mode: .autonomous,
            activeGoalStatus: .active,
            resolvedTarget: .terminalReply(terminalID: "term-1", fingerprint: snapshot.attentionFingerprint),
            selectedSnapshot: snapshot
        )

        #expect(decision == .requireUser(ForemanRuntimePolicy.planModeMessage))
    }

    @Test
    func completedGoalDoesNotReopenOnGenericChatInput() {
        let policy = ForemanRuntimePolicy()

        #expect(policy.shouldReopenCompletedGoal(for: "continue") == false)
        #expect(policy.shouldReopenCompletedGoal(for: "/goal reopen") == true)
        #expect(policy.shouldReopenCompletedGoal(for: "/goal continue") == true)
    }
}
