import Foundation

enum ForemanReactiveEventRouter {
    enum InitialDecision: Equatable {
        case showPendingAttention(PendingAgentAttention)
        case draftWaitingText
        case react
    }

    enum DraftDecision: Equatable {
        case showPendingAttention(PendingAgentAttention)
        case ignore
        case react
    }

    static func initialDecision(
        for event: AgentNeedsAttentionEvent,
        understanding: TerminalUnderstanding?
    ) -> InitialDecision {
        if let attention = PendingAgentAttentionFactory.make(from: event, understanding: understanding) {
            return .showPendingAttention(attention)
        }

        if event.interactionState == .waitingText {
            return .draftWaitingText
        }

        return .react
    }

    static func decisionAfterDraft(
        for interactionState: AgentInteractionState,
        draftedAttention: PendingAgentAttention?
    ) -> DraftDecision {
        if let draftedAttention {
            return .showPendingAttention(draftedAttention)
        }

        switch interactionState {
        case .waitingText:
            return .ignore
        case .waitingApproval, .waitingChoice, .error, .unknown, .running, .completed:
            return .react
        }
    }
}
