import Foundation

enum PendingAgentAttentionFactory {
    static func make(
        from event: AgentNeedsAttentionEvent,
        understanding: TerminalUnderstanding?
    ) -> PendingAgentAttention? {
        switch event.interactionState {
        case .waitingApproval:
            let actions: [PendingAgentAction]
            if event.agentIdentity == .kimi {
                actions = [
                    .init(id: "approve_once", title: "Approve once", payload: "1", style: .primary),
                    .init(id: "approve_session", title: "Approve session", payload: "2", style: .secondary),
                    .init(id: "reject", title: "Reject", payload: "3", style: .destructive),
                ]
            } else {
                actions = [
                    .init(id: "approve", title: "Approve", payload: "y", style: .primary),
                    .init(id: "reject", title: "Reject", payload: "n", style: .destructive),
                ]
            }

            return PendingAgentAttention(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                fingerprint: event.fingerprint,
                title: "Needs your approval",
                description: understanding?.agentInteractionContext.descriptionString ?? event.deltaText,
                detail: understanding?.agentInteractionContext.detailString,
                actions: actions
            )

        case .waitingChoice:
            let options = understanding?.agentInteractionContext.optionsArray ?? []
            guard !options.isEmpty else {
                return nil
            }

            let actions = options.prefix(4).enumerated().map { index, option in
                PendingAgentAction(
                    id: "choice_\(index + 1)",
                    title: option,
                    payload: "\(index + 1)",
                    style: index == 0 ? .primary : .secondary
                )
            }

            return PendingAgentAttention(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                fingerprint: event.fingerprint,
                title: "Choose an option",
                description: understanding?.agentInteractionContext.descriptionString ?? event.deltaText,
                detail: nil,
                actions: actions
            )

        default:
            return nil
        }
    }
}
