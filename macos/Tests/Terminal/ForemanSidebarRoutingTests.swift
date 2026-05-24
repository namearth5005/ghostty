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
    func ambiguousWaitingTargetsRequireExplicitChoice() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-3",
            focusedTerminalID: "term-3",
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
    func staleFingerprintBlocksReplyAndPreservesDraft() {
        let router = ForemanSidebarRouter()
        let state = ForemanSidebarRoutingState(
            projectID: "/tmp/ghostty",
            selectedTerminalID: "term-1",
            focusedTerminalID: "term-1",
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
}
