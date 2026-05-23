import Foundation

struct AgentInteractionContextResolver {
    struct ResolvedContext: Equatable, Sendable {
        let context: AgentInteractionContext
        let detail: String
    }

    func resolve(
        identity: AgentIdentity,
        kimiWireRecords: [KimiWireRecord] = [],
        codexWireRecords: [CodexWireRecord] = [],
        claudeWireRecords: [ClaudeSessionState] = []
    ) -> ResolvedContext? {
        switch identity {
        case .kimi:
            return resolveKimi(from: kimiWireRecords)
        case .codex:
            return resolveCodex(from: codexWireRecords)
        case .claudeCode:
            return resolveClaude(from: claudeWireRecords)
        case .none, .unknown:
            return nil
        }
    }

    func resolveKimi(from wireRecords: [KimiWireRecord]) -> ResolvedContext? {
        guard let pair = wireRecords.lazy.reversed().compactMap({ record -> (KimiWireRecord, AgentInteractionContext)? in
            guard let context = record.asAgentInteractionContext else { return nil }
            return (record, context)
        }).first else {
            return nil
        }

        return ResolvedContext(
            context: enrichKimiContext(pair.1, from: wireRecords),
            detail: "Wire record: \(pair.0.message.type)"
        )
    }

    func resolveCodex(from wireRecords: [CodexWireRecord]) -> ResolvedContext? {
        guard let pair = wireRecords.lazy.reversed().compactMap({ record -> (CodexWireRecord, AgentInteractionContext)? in
            guard let context = record.asAgentInteractionContext else { return nil }
            return (record, context)
        }).first else {
            return nil
        }

        return ResolvedContext(
            context: pair.1,
            detail: "Codex wire: \(pair.0.payload.type ?? pair.0.type)"
        )
    }

    func resolveClaude(from wireRecords: [ClaudeSessionState]) -> ResolvedContext? {
        guard let pair = wireRecords.lazy.reversed().compactMap({ state -> (ClaudeSessionState, AgentInteractionContext)? in
            guard let context = state.asAgentInteractionContext else { return nil }
            return (state, context)
        }).first else {
            return nil
        }

        return ResolvedContext(
            context: pair.1,
            detail: "Claude status: \(pair.0.status ?? "unknown")"
        )
    }

    private func enrichKimiContext(
        _ context: AgentInteractionContext,
        from wireRecords: [KimiWireRecord]
    ) -> AgentInteractionContext {
        guard case .waitingText(let question) = context,
              question?.isEmpty ?? true,
              let wireQuestion = latestKimiTextQuestion(from: wireRecords) else {
            return context
        }

        return .waitingText(question: wireQuestion)
    }

    private func latestKimiTextQuestion(from wireRecords: [KimiWireRecord]) -> String? {
        for record in wireRecords.reversed() where record.message.type == "ContentPart" {
            guard let text = record.message.payload.text ?? record.message.payload.content else {
                continue
            }

            if let question = text
                .split(separator: "\n")
                .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
                .last(where: { !$0.isEmpty && $0.contains("?") }) {
                return question
            }
        }

        return nil
    }
}
