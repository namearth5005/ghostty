import Foundation

enum ForemanContinuationDecision: Equatable, Sendable {
    case allowAutonomousDispatch
    case requireUser(String)
    case blockCompletedGoal(String)
}

struct ForemanRuntimePolicy {
    static let completedGoalMessage =
        "The saved project goal is complete. Reopen or extend it before dispatching more work."
    static let planModeMessage =
        "The worker is in plan mode. Choose whether to resume after the plan is reviewed."
    static let manualReviewMessage =
        "The worker suggested this step, but it still needs your review before continuing."
    static let unsuggestedActionMessage =
        "The worker did not suggest this action. Review it before continuing."
    static let manualModeMessage =
        "Manual mode requires explicit send or approval."
    static let ambiguousTargetMessage =
        "Choose a terminal before continuing."

    func continuationDecision(
        mode: AgentMode,
        activeGoalStatus: ForemanProjectGoalStatus?,
        resolvedTarget: ForemanSidebarTarget,
        selectedSnapshot: TerminalWorkerSnapshot?,
        proposedPayload: String? = nil
    ) -> ForemanContinuationDecision {
        if activeGoalStatus == .completed {
            return .blockCompletedGoal(Self.completedGoalMessage)
        }

        guard mode == .autonomous else {
            return .requireUser(Self.manualModeMessage)
        }

        if selectedSnapshot?.state.runtimeFlags.contains(.planning) == true {
            return .requireUser(Self.planModeMessage)
        }

        if let selectedSnapshot,
           let proposedPayload = normalized(proposedPayload),
           let suggestionDecision = suggestionDecision(
                for: proposedPayload,
                snapshot: selectedSnapshot
           ) {
            return suggestionDecision
        }

        if case .ambiguous = resolvedTarget {
            return .requireUser(Self.ambiguousTargetMessage)
        }

        return .allowAutonomousDispatch
    }

    func shouldReopenCompletedGoal(for input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/goal reopen") || trimmed.hasPrefix("/goal continue")
    }

    private func suggestionDecision(
        for proposedPayload: String,
        snapshot: TerminalWorkerSnapshot
    ) -> ForemanContinuationDecision? {
        let suggestions = snapshot.suggestions
        guard !suggestions.isEmpty else {
            return nil
        }

        guard let suggestion = suggestions.first(where: {
            normalized(payloadString(for: $0.payload)) == proposedPayload
        }) else {
            return .requireUser(Self.unsuggestedActionMessage)
        }

        switch suggestion.execution {
        case .autonomousOK:
            return .allowAutonomousDispatch
        case .manualOnly:
            return .requireUser(Self.manualReviewMessage)
        }
    }

    private func payloadString(for payload: TerminalWorkerSnapshot.Payload) -> String {
        switch payload {
        case .text(let value), .command(let value), .option(let value), .approval(let value), .foremanPrompt(let value):
            return value
        }
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
