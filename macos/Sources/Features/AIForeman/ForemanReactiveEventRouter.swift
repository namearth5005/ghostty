import Foundation

enum ForemanReactiveEventRouter {
    enum InitialDecision: Equatable {
        case showPendingAttention(PendingAgentAttention)
        case autoDispatchPendingAttention(PendingAgentAttention, PendingAgentAction)
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
        understanding: TerminalUnderstanding?,
        mode: AgentMode = .interactive,
        activeGoalStatus: ForemanProjectGoalStatus? = nil,
        runtimePolicy: ForemanRuntimePolicy = .init()
    ) -> InitialDecision {
        if let attention = PendingAgentAttentionFactory.make(from: event, understanding: understanding) {
            if let autoDispatch = authoritativeAutonomousDecision(
                for: event,
                understanding: understanding,
                attention: attention,
                mode: mode,
                activeGoalStatus: activeGoalStatus,
                runtimePolicy: runtimePolicy
            ) {
                return autoDispatch
            }
            return .showPendingAttention(attention)
        }

        if event.interactionState == .waitingText {
            return .draftWaitingText
        }

        return .react
    }

    private static func authoritativeAutonomousDecision(
        for event: AgentNeedsAttentionEvent,
        understanding: TerminalUnderstanding?,
        attention: PendingAgentAttention,
        mode: AgentMode,
        activeGoalStatus: ForemanProjectGoalStatus?,
        runtimePolicy: ForemanRuntimePolicy
    ) -> InitialDecision? {
        guard let snapshot = understanding?.workerSnapshot,
              snapshot.request != nil else {
            return nil
        }

        let requestSuggestions = snapshot.requestSuggestions
        guard let suggestion = requestSuggestions.first(where: \.recommended) ?? requestSuggestions.first else {
            return nil
        }

        if case .foremanPrompt = suggestion.payload {
            return nil
        }

        guard let action = attention.actions.first(where: { $0.id == suggestion.id }) else {
            return nil
        }

        let decision = runtimePolicy.continuationDecision(
            mode: mode,
            activeGoalStatus: activeGoalStatus,
            resolvedTarget: .terminalReply(
                terminalID: event.terminalID,
                fingerprint: event.fingerprint
            ),
            selectedSnapshot: snapshot,
            proposedPayload: action.payload
        )

        guard decision == .allowAutonomousDispatch else {
            return nil
        }

        return .autoDispatchPendingAttention(attention, action)
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
