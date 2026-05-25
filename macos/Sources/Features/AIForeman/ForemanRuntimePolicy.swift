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
    static let manualModeMessage =
        "Manual mode requires explicit send or approval."
    static let ambiguousTargetMessage =
        "Choose a terminal before continuing."

    func continuationDecision(
        mode: AgentMode,
        activeGoalStatus: ForemanProjectGoalStatus?,
        resolvedTarget: ForemanSidebarTarget,
        selectedSnapshot: TerminalWorkerSnapshot?
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

        if case .ambiguous = resolvedTarget {
            return .requireUser(Self.ambiguousTargetMessage)
        }

        return .allowAutonomousDispatch
    }

    func shouldReopenCompletedGoal(for input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/goal reopen") || trimmed.hasPrefix("/goal continue")
    }
}
