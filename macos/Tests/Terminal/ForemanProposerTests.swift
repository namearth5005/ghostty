import Testing
@testable import Ghostty

struct ForemanProposerTests {
    private func understanding(
        state: AgentInteractionState,
        actions: [TerminalSuggestedAction] = [],
        explanation: String = "Heuristic explanation."
    ) -> TerminalUnderstanding {
        TerminalUnderstanding.preview(
            terminalID: "t1",
            state: .waiting,
            shortExplanation: explanation,
            lastMeaningfulEvent: "Proceed? (y/n)",
            importantDetails: [],
            suggestedNextActions: actions,
            agentIdentity: .codex,
            agentInteractionState: state
        )
    }

    private func snapshot() -> TerminalSnapshot {
        TerminalSnapshot.makePreview(
            terminalID: "t1",
            windowID: "w1",
            tabID: "tab1",
            title: "codex",
            cwd: "/tmp",
            isFocused: true,
            visibleText: "Proceed? (y/n)",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex"
        )
    }

    @Test
    func runningStateProducesNoProposal() async {
        let proposer = ForemanProposer()
        let result = await proposer.makeProposal(
            understanding: understanding(state: .running),
            snapshot: snapshot()
        )
        #expect(result == nil)
    }

    @Test
    func usesLLMSummaryWhenAvailable() async {
        let proposer = ForemanProposer(summarize: { _ in "Kimi wants to push to main. Tests passed." })
        let action = TerminalSuggestedAction(
            title: "Approve the push",
            command: nil,
            reason: "",
            isRecommended: true,
            authoritativePayload: "y"
        )

        let result = await proposer.makeProposal(
            understanding: understanding(state: .waitingApproval, actions: [action]),
            snapshot: snapshot()
        )

        #expect(result?.summary == "Kimi wants to push to main. Tests passed.")
        #expect(result?.payload == "y")
        #expect(result?.actionTitle == "Approve the push")
        #expect(result?.kind == .waitingApproval)
    }

    @Test
    func fallsBackToHeuristicSummaryWhenLLMReturnsNil() async {
        let proposer = ForemanProposer(summarize: { _ in nil })
        let action = TerminalSuggestedAction(
            title: "Approve",
            command: nil,
            reason: "",
            isRecommended: true,
            authoritativePayload: "y"
        )

        let result = await proposer.makeProposal(
            understanding: understanding(
                state: .waitingApproval,
                actions: [action],
                explanation: "Codex is asking to proceed."
            ),
            snapshot: snapshot()
        )

        #expect(result?.summary == "Codex is asking to proceed.")
        #expect(result?.payload == "y")
    }

    @Test
    func errorStateWithoutActionStillProposesWithNoPayload() async {
        let proposer = ForemanProposer(summarize: { _ in "A build error appeared." })
        let result = await proposer.makeProposal(
            understanding: understanding(state: .error),
            snapshot: snapshot()
        )

        #expect(result != nil)
        #expect(result?.payload == nil)
        #expect(result?.kind == .error)
    }

    @Test
    func attentionPolicyMatchesExpectedStates() {
        #expect(ForemanProposer.needsAttention(.waitingApproval))
        #expect(ForemanProposer.needsAttention(.waitingChoice))
        #expect(ForemanProposer.needsAttention(.waitingText))
        #expect(ForemanProposer.needsAttention(.error))
        #expect(ForemanProposer.needsAttention(.completed))
        #expect(!ForemanProposer.needsAttention(.running))
        #expect(!ForemanProposer.needsAttention(.unknown))
    }
}
