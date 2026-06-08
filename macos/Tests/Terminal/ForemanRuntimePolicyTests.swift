import Foundation
import Testing
@testable import Ghostty

struct ForemanRuntimePolicyTests {
    private func makeChoiceSnapshot(
        execution: TerminalWorkerSuggestionExecution = .autonomousOK,
        isPlanning: Bool = false
    ) -> TerminalWorkerSnapshot {
        TerminalWorkerSnapshot(
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
                summary: isPlanning ? "Kimi is waiting in plan mode." : "Kimi suggested a next step.",
                details: ["Two API directions are available."],
                runtimeFlags: isPlanning ? [.planning] : []
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
                    execution: execution,
                    requestID: "req-12"
                ),
            ]
        )
    }

    @Test
    func planningSnapshotBlocksAutonomousContinuation() {
        let policy = ForemanRuntimePolicy()
        let snapshot = makeChoiceSnapshot(isPlanning: true)

        let decision = policy.continuationDecision(
            mode: .autonomous,
            activeGoalStatus: .active,
            resolvedTarget: .terminalReply(terminalID: "term-1", fingerprint: snapshot.attentionFingerprint),
            selectedSnapshot: snapshot,
            proposedPayload: "1"
        )

        #expect(decision == .requireUser(ForemanRuntimePolicy.planModeMessage))
    }

    @Test
    func matchingAutonomousWorkerSuggestionAllowsAutonomousContinuation() {
        let policy = ForemanRuntimePolicy()
        let snapshot = makeChoiceSnapshot(execution: .autonomousOK)

        let decision = policy.continuationDecision(
            mode: .autonomous,
            activeGoalStatus: .active,
            resolvedTarget: .terminalReply(terminalID: "term-1", fingerprint: snapshot.attentionFingerprint),
            selectedSnapshot: snapshot,
            proposedPayload: "1"
        )

        #expect(decision == .allowAutonomousDispatch)
    }

    @Test
    func manualOnlyWorkerSuggestionRequiresUserReview() {
        let policy = ForemanRuntimePolicy()
        let snapshot = makeChoiceSnapshot(execution: .manualOnly)

        let decision = policy.continuationDecision(
            mode: .autonomous,
            activeGoalStatus: .active,
            resolvedTarget: .terminalReply(terminalID: "term-1", fingerprint: snapshot.attentionFingerprint),
            selectedSnapshot: snapshot,
            proposedPayload: "1"
        )

        #expect(decision == .requireUser(ForemanRuntimePolicy.manualReviewMessage))
    }

    @Test
    func competingPayloadRequiresUserReviewWhenWorkerAlreadySuggestedSomething() {
        let policy = ForemanRuntimePolicy()
        let snapshot = makeChoiceSnapshot(execution: .autonomousOK)

        let decision = policy.continuationDecision(
            mode: .autonomous,
            activeGoalStatus: .active,
            resolvedTarget: .terminalReply(terminalID: "term-1", fingerprint: snapshot.attentionFingerprint),
            selectedSnapshot: snapshot,
            proposedPayload: "2"
        )

        #expect(decision == .requireUser(ForemanRuntimePolicy.unsuggestedActionMessage))
    }

    @Test
    func staleSuggestionsFromOlderRequestsDoNotAuthorizeAutonomousDispatch() {
        let policy = ForemanRuntimePolicy()
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "kimi-session-12",
            revision: 13,
            observedAt: Date(timeIntervalSince1970: 1_748_333_334),
            ttlMilliseconds: 15_000,
            workerGoal: "compare API directions",
            agent: .init(identity: .kimi),
            state: .init(
                lifecycle: .running,
                attention: .choiceRequired,
                summary: "Kimi is waiting for a fresh choice.",
                details: ["The old recommendation should no longer apply."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-13",
                kind: .choice,
                prompt: "Which direction should I take now?",
                options: [
                    .init(id: "1", label: "Keep current API", recommended: false),
                    .init(id: "2", label: "Allow breaking change", recommended: true),
                ]
            ),
            suggestions: [
                .init(
                    id: "old-choice",
                    kind: .choice,
                    title: "Keep current API",
                    payload: .option("1"),
                    rationale: "This belongs to the old request.",
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
            selectedSnapshot: snapshot,
            proposedPayload: "1"
        )

        #expect(decision == .requireUser(ForemanRuntimePolicy.unsuggestedActionMessage))
    }

    @Test
    func completedGoalDoesNotReopenOnGenericChatInput() {
        let policy = ForemanRuntimePolicy()

        #expect(policy.shouldReopenCompletedGoal(for: "continue") == false)
        #expect(policy.shouldReopenCompletedGoal(for: "/goal reopen") == true)
        #expect(policy.shouldReopenCompletedGoal(for: "/goal continue") == true)
    }
}
