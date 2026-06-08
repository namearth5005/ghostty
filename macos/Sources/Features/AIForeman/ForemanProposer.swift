import Foundation

/// Turns a `TerminalUnderstanding` (from the dumb detection engine) into a
/// `TerminalProposal` (the friendly card). The plain summary comes from an injected
/// async source — the LLM in production — and falls back to the heuristic explanation
/// when unavailable. The action/payload always comes from the understanding, so the
/// thing we send is what the agent itself surfaced.
struct ForemanProposer {
    /// Returns a plain-English summary for a snapshot, or `nil` when no LLM is
    /// configured or the call fails.
    let summarize: (TerminalSnapshot) async -> String?

    init(summarize: @escaping (TerminalSnapshot) async -> String? = { _ in nil }) {
        self.summarize = summarize
    }

    func makeProposal(
        understanding: TerminalUnderstanding,
        snapshot: TerminalSnapshot
    ) async -> TerminalProposal? {
        guard Self.needsAttention(understanding.agentInteractionState) else {
            return nil
        }

        let action = understanding.recommendedAction ?? understanding.suggestedNextActions.first
        let payload = action.flatMap { $0.authoritativePayload ?? $0.command }
        let actionTitle = action?.title ?? Self.defaultTitle(for: understanding.agentInteractionState)

        let llmSummary = (await summarize(snapshot))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (llmSummary?.isEmpty == false ? llmSummary : nil) ?? understanding.shortExplanation

        return TerminalProposal(
            terminalID: understanding.terminalID,
            fingerprint: Self.fingerprint(for: understanding),
            summary: summary,
            actionTitle: actionTitle,
            payload: payload,
            kind: understanding.agentInteractionState
        )
    }

    /// The states that warrant interrupting the user.
    static func needsAttention(_ state: AgentInteractionState) -> Bool {
        switch state {
        case .waitingApproval, .waitingChoice, .waitingText, .error, .completed:
            return true
        case .unknown, .running:
            return false
        }
    }

    /// A stable identifier for "this exact pending state", used to detect staleness.
    /// Prefers the authoritative wire fingerprint; falls back to the screen state.
    static func fingerprint(for understanding: TerminalUnderstanding) -> String {
        if let fingerprint = understanding.workerSnapshot?.attentionFingerprint {
            return fingerprint
        }
        if let fingerprint = understanding.suggestedNextActions.compactMap(\.authoritativeFingerprint).first {
            return fingerprint
        }
        return "\(understanding.agentInteractionState.rawValue)|\(understanding.lastMeaningfulEvent)"
    }

    private static func defaultTitle(for state: AgentInteractionState) -> String {
        switch state {
        case .waitingApproval: return "Approve"
        case .waitingChoice: return "Choose"
        case .waitingText: return "Reply"
        case .error: return "Review the error"
        case .completed: return "Acknowledge"
        case .unknown, .running: return "Continue"
        }
    }
}
