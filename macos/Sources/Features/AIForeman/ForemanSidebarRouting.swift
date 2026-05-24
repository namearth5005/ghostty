import Foundation

enum ForemanSidebarIntent: Equatable, Sendable {
    case guideForeman(String)
    case sendTerminalReply(terminalID: String, fingerprint: String, message: String)
    case sendTerminalCommand(terminalID: String, command: String)
    case sendPendingAttentionAction(terminalID: String, fingerprint: String, payload: String)
    case reopenCompletedGoal(projectID: String)
    case extendGoal(projectID: String, text: String)
    case clearGoal(projectID: String)
}

enum ForemanTargetOption: Equatable, Sendable {
    case terminalReply(terminalID: String, fingerprint: String, title: String)
    case project(title: String)
}

enum ForemanSidebarTarget: Equatable, Sendable {
    case project(projectID: String?)
    case terminalReply(terminalID: String, fingerprint: String)
    case ambiguous(options: [ForemanTargetOption])
    case completedGoal(projectID: String)
}

struct ForemanSidebarRoutingState: Equatable, Sendable {
    let projectID: String?
    let selectedTerminalID: String?
    let focusedTerminalID: String?
    let pendingAttentionByTerminalID: [String: PendingAgentAttention]
    let terminalRows: [TerminalSummaryRowModel]
    let activeProjectGoal: ForemanProjectGoal?
}

struct ForemanSidebarRouteResult: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case dispatch(ForemanSidebarIntent)
        case blocked(message: String, draftToPreserve: String?)
        case suppressed(message: String)
    }

    let target: ForemanSidebarTarget
    let outcome: Outcome
}

struct ForemanSidebarRouter {
    func resolveTarget(from state: ForemanSidebarRoutingState) -> ForemanSidebarTarget {
        if let goal = state.activeProjectGoal, goal.status == .completed {
            return .completedGoal(projectID: goal.projectID)
        }

        if let selectedTerminalID = state.selectedTerminalID,
           let attention = state.pendingAttentionByTerminalID[selectedTerminalID] {
            return .terminalReply(
                terminalID: selectedTerminalID,
                fingerprint: attention.fingerprint
            )
        }

        let waitingTerminalIDs = state.pendingAttentionByTerminalID.keys.sorted()
        if waitingTerminalIDs.count == 1,
           let terminalID = waitingTerminalIDs.first,
           let attention = state.pendingAttentionByTerminalID[terminalID] {
            return .terminalReply(
                terminalID: terminalID,
                fingerprint: attention.fingerprint
            )
        }

        if let focusedTerminalID = state.focusedTerminalID,
           let attention = state.pendingAttentionByTerminalID[focusedTerminalID] {
            return .terminalReply(
                terminalID: focusedTerminalID,
                fingerprint: attention.fingerprint
            )
        }

        if waitingTerminalIDs.count > 1 {
            let options = waitingTerminalIDs.compactMap { terminalID -> ForemanTargetOption? in
                guard let attention = state.pendingAttentionByTerminalID[terminalID] else {
                    return nil
                }

                return .terminalReply(
                    terminalID: terminalID,
                    fingerprint: attention.fingerprint,
                    title: title(for: terminalID, in: state)
                )
            } + [.project(title: "Guide Foreman")]

            return .ambiguous(options: options)
        }

        return .project(projectID: state.projectID)
    }

    func resolveSuggestion(
        _ action: TerminalSuggestedAction,
        terminalID: String,
        state: ForemanSidebarRoutingState
    ) -> ForemanSidebarRouteResult {
        let target = resolveTarget(from: state)
        if case .completedGoal = target {
            return .init(
                target: target,
                outcome: .suppressed(
                    message: "The saved project goal is complete. Reopen or extend it before dispatching more work."
                )
            )
        }

        if let command = action.command {
            return .init(
                target: target,
                outcome: .dispatch(
                    .sendTerminalCommand(terminalID: terminalID, command: command)
                )
            )
        }

        let prompt = "\(action.title) for terminal \(title(for: terminalID, in: state)). \(action.reason)"
        return .init(target: target, outcome: .dispatch(.guideForeman(prompt)))
    }

    func resolveExplicitIntent(
        _ intent: ForemanSidebarIntent,
        state: ForemanSidebarRoutingState
    ) -> ForemanSidebarRouteResult {
        let target = resolveTarget(from: state)

        switch intent {
        case .sendTerminalReply(let terminalID, let fingerprint, let message):
            guard state.pendingAttentionByTerminalID[terminalID]?.fingerprint == fingerprint else {
                return .init(
                    target: target,
                    outcome: .blocked(
                        message: "The terminal target changed before the message was sent.",
                        draftToPreserve: message
                    )
                )
            }

        case .sendPendingAttentionAction(let terminalID, let fingerprint, _):
            guard state.pendingAttentionByTerminalID[terminalID]?.fingerprint == fingerprint else {
                return .init(
                    target: target,
                    outcome: .blocked(
                        message: "The terminal target changed before the action was sent.",
                        draftToPreserve: nil
                    )
                )
            }

        default:
            break
        }

        return .init(target: target, outcome: .dispatch(intent))
    }

    private func title(
        for terminalID: String,
        in state: ForemanSidebarRoutingState
    ) -> String {
        guard let row = state.terminalRows.first(where: { $0.terminalID == terminalID }) else {
            return terminalID
        }

        return row.title.isEmpty ? terminalID : row.title
    }
}
