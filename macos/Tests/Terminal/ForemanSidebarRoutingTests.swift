import Testing
@testable import Ghostty

struct ForemanSidebarRoutingTests {
    @Test
    func selectedWaitingTerminalResolvesReplyTarget() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-2",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [
                "term-2": makeAttention(terminalID: "term-2", fingerprint: "fp-2"),
            ],
            terminalRows: [makeRow("term-1"), makeRow("term-2")],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix"
            )
        )

        #expect(
            router.resolveTarget(from: state) ==
            .terminalReply(terminalID: "term-2", fingerprint: "fp-2")
        )
    }

    @Test
    func selectedAuthoritativeWorkerWithoutPendingAttentionResolvesReplyTarget() {
        let router = ForemanSidebarRouter()
        let fingerprint = "codex-session-41|41|req-41"
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-2",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [:],
            terminalRows: [makeRow("term-1"), makeRow("term-2")],
            workerSnapshotsByTerminalID: [
                "term-2": makeWorkerSnapshot(terminalID: "term-2", fingerprint: fingerprint),
            ],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix"
            )
        )

        #expect(
            router.resolveTarget(from: state) ==
            .terminalReply(terminalID: "term-2", fingerprint: fingerprint)
        )
    }

    @Test
    func ambiguousWaitingTargetsRequireExplicitChoice() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-3",
            focusedTerminalID: "term-3",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [
                "term-1": makeAttention(terminalID: "term-1", fingerprint: "fp-1"),
                "term-2": makeAttention(terminalID: "term-2", fingerprint: "fp-2"),
            ],
            terminalRows: [makeRow("term-1"), makeRow("term-2"), makeRow("term-3")],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix"
            )
        )

        #expect(
            router.resolveTarget(from: state) ==
            .ambiguous(options: [
                .terminalReply(terminalID: "term-1", fingerprint: "fp-1", title: "term-1"),
                .terminalReply(terminalID: "term-2", fingerprint: "fp-2", title: "term-2"),
                .project(title: "Guide Foreman"),
            ])
        )
    }

    @Test
    func completedGoalSuppressesExecutableSuggestion() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-1",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [:],
            terminalRows: [makeRow("term-1")],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix",
                status: .completed
            )
        )
        let action = TerminalSuggestedAction(
            title: "Run the test suite",
            command: "xcodebuild test -scheme Ghostty",
            reason: "Verify the sidebar change.",
            isRecommended: true
        )

        let result = router.resolveSuggestion(action, terminalID: "term-1", state: state)

        #expect(
            result.outcome ==
            .suppressed(
                message: "The saved project goal is complete. Reopen or extend it before dispatching more work."
            )
        )
    }

    @Test
    func authoritativeWorkerReplySuggestionRoutesDirectlyToTerminalReply() {
        let router = ForemanSidebarRouter()
        let fingerprint = "codex-session-41|41|req-41"
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-1",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [:],
            terminalRows: [makeRow("term-1")],
            workerSnapshotsByTerminalID: [
                "term-1": makeWorkerSnapshot(terminalID: "term-1", fingerprint: fingerprint),
            ],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix"
            )
        )
        let action = TerminalSuggestedAction(
            title: "Preserve the API",
            command: nil,
            reason: "Lowest migration risk.",
            isRecommended: true,
            authoritativeFingerprint: fingerprint,
            authoritativePayload: "Preserve the current API and adapt the internals."
        )

        let result = router.resolveSuggestion(action, terminalID: "term-1", state: state)

        #expect(
            result.outcome ==
            .dispatch(
                .sendTerminalReply(
                    terminalID: "term-1",
                    fingerprint: fingerprint,
                    message: "Preserve the current API and adapt the internals."
                )
            )
        )
    }

    @Test
    func authoritativeWorkerGuidanceSuggestionRoutesThroughTerminalScopedForemanIntent() {
        let router = ForemanSidebarRouter()
        let fingerprint = "codex-session-52|52|req-52"
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-1",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [:],
            terminalRows: [makeRow("term-1")],
            workerSnapshotsByTerminalID: [
                "term-1": makeWorkerSnapshot(terminalID: "term-1", fingerprint: fingerprint),
            ],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix"
            )
        )
        let action = TerminalSuggestedAction(
            title: "Reply to the agent",
            command: nil,
            reason: "Codex needs direction.",
            isRecommended: true,
            authoritativeFingerprint: fingerprint,
            guidancePrompt: "What should I do here?"
        )

        let result = router.resolveSuggestion(action, terminalID: "term-1", state: state)

        #expect(
            result.outcome ==
            .dispatch(
                .guideForemanForTerminal(
                    terminalID: "term-1",
                    fingerprint: fingerprint,
                    message: "What should I do here?"
                )
            )
        )
    }

    @Test
    func completedGoalSuppressesPendingAttentionAction() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-1",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [
                "term-1": makeAttention(terminalID: "term-1", fingerprint: "fp-1"),
            ],
            terminalRows: [makeRow("term-1")],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix",
                status: .completed
            )
        )

        let result = router.resolveExplicitIntent(
            .sendPendingAttentionAction(
                terminalID: "term-1",
                fingerprint: "fp-1",
                payload: "1"
            ),
            state: state
        )

        #expect(
            result.outcome ==
            .suppressed(
                message: "The saved project goal is complete. Reopen or extend it before dispatching more work."
            )
        )
    }

    @Test
    func completedGoalAllowsExplicitGoalManagement() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-1",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [:],
            terminalRows: [makeRow("term-1")],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix",
                status: .completed
            )
        )

        let result = router.resolveExplicitIntent(
            .clearGoal(projectID: "/tmp/ghostty"),
            state: state
        )

        #expect(
            result.outcome ==
            .dispatch(.clearGoal(projectID: "/tmp/ghostty"))
        )
    }

    @Test
    func staleFingerprintBlocksReplyAndPreservesDraft() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-1",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [
                "term-1": makeAttention(terminalID: "term-1", fingerprint: "fresh-fp"),
            ],
            terminalRows: [makeRow("term-1")],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix"
            )
        )

        let result = router.resolveExplicitIntent(
            .sendTerminalReply(
                terminalID: "term-1",
                fingerprint: "stale-fp",
                message: "Yes, continue."
            ),
            state: state
        )

        #expect(
            result.outcome ==
            .blocked(
                message: "The terminal target changed before the message was sent.",
                draftToPreserve: "Yes, continue."
            )
        )
    }

    @Test
    func preferredProjectTargetOverridesAmbiguousWaitingTargets() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-3",
            focusedTerminalID: "term-3",
            preferredTarget: .project,
            pendingAttentionByTerminalID: [
                "term-1": makeAttention(terminalID: "term-1", fingerprint: "fp-1"),
                "term-2": makeAttention(terminalID: "term-2", fingerprint: "fp-2"),
            ],
            terminalRows: [makeRow("term-1"), makeRow("term-2"), makeRow("term-3")],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix"
            )
        )

        #expect(router.resolveTarget(from: state) == .project(projectID: "/tmp/ghostty"))
    }

    @Test
    func workerSnapshotFingerprintAllowsDirectReplyWithoutPendingAttention() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-1",
            focusedTerminalID: "term-1",
            preferredTarget: nil,
            pendingAttentionByTerminalID: [:],
            terminalRows: [makeRow("term-1")],
            workerSnapshotsByTerminalID: [
                "term-1": makeWorkerSnapshot(
                    terminalID: "term-1",
                    fingerprint: "codex-session-41|41|req-41"
                ),
            ],
            activeProjectGoal: ForemanProjectGoal(
                projectID: "/tmp/ghostty",
                objective: "Ship the sidebar fix"
            )
        )

        let result = router.resolveExplicitIntent(
            .sendTerminalReply(
                terminalID: "term-1",
                fingerprint: "codex-session-41|41|req-41",
                message: "Preserve the current API and adapt the internals."
            ),
            state: state
        )

        #expect(
            result.outcome ==
            .dispatch(
                .sendTerminalReply(
                    terminalID: "term-1",
                    fingerprint: "codex-session-41|41|req-41",
                    message: "Preserve the current API and adapt the internals."
                )
            )
        )
    }

    private func makeAttention(terminalID: String, fingerprint: String) -> PendingAgentAttention {
        PendingAgentAttention(
            terminalID: terminalID,
            agentIdentity: .codex,
            interactionState: .waitingText,
            fingerprint: fingerprint,
            title: "Codex needs a reply",
            description: "Answer the active prompt.",
            actions: [
                .init(
                    id: "continue",
                    title: "Continue",
                    payload: "1",
                    style: .primary
                ),
            ]
        )
    }

    private func makeRow(_ terminalID: String) -> TerminalSummaryRowModel {
        TerminalSummaryRowModel(
            terminalID: terminalID,
            title: terminalID,
            cwd: "/tmp/ghostty",
            state: "waiting",
            summary: "Waiting for input.",
            agentIdentity: "codex",
            agentInteractionState: "waiting_text",
            supportLevel: "first_class",
            evidenceSummary: "wire_signal",
            isFocused: false,
            suggestedActions: [],
            pendingAttention: nil,
            agentContextType: "waitingText",
            agentContextTitle: "Needs a reply",
            agentContextDescription: "Answer the active prompt.",
            agentContextDetail: nil,
            agentContextOptions: nil
        )
    }

    private func makeWorkerSnapshot(
        terminalID: String,
        fingerprint: String
    ) -> TerminalWorkerSnapshot {
        let requestID = fingerprint.components(separatedBy: "|").last ?? "req-1"
        return TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: terminalID,
            workerSessionID: "codex-session-41",
            revision: 41,
            observedAt: Date(timeIntervalSince1970: 1_748_222_222),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .blocked,
                attention: .replyRequired,
                summary: "Codex is waiting for a reply.",
                details: ["Asked whether the API should stay stable."],
                runtimeFlags: []
            ),
            request: .init(
                id: requestID,
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: []
        )
    }
}
