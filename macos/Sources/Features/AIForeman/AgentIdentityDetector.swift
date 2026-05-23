import Foundation

struct AgentIdentityDetector {
    func identity(for snapshot: TerminalSnapshot) -> AgentIdentity? {
        if let foregroundProcessName = normalized(snapshot.runtime.foregroundProcessName) {
            if let processMatch = detectIdentity(in: foregroundProcessName) {
                return processMatch
            }

            return detectIdentity(inVisibleText: snapshot.visibleText)
        }

        if let visibleMatch = detectIdentity(inVisibleText: snapshot.visibleText) {
            return visibleMatch
        }

        return detectIdentity(in: snapshot.title)
    }

    func matches(_ snapshot: TerminalSnapshot, identity expectedIdentity: AgentIdentity) -> Bool {
        identity(for: snapshot) == expectedIdentity
    }

    private func detectIdentity(inVisibleText visibleText: String) -> AgentIdentity? {
        let visible = visibleText.lowercased()
        if visible.contains("welcome to kimi code cli") || visible.contains("agent (kimi") {
            return .kimi
        }
        if visible.contains("welcome to claude code") || visible.contains("claude code") {
            return .claudeCode
        }
        if visible.contains("openai codex") {
            return .codex
        }

        return nil
    }

    private func detectIdentity(in candidate: String?) -> AgentIdentity? {
        guard let candidate else { return nil }
        let lowered = candidate.lowercased()

        if lowered.contains("kimi code") || lowered == "kimi" || lowered.contains("kimi") {
            return .kimi
        }
        if lowered.contains("claude code") || lowered == "claude" || lowered.contains("claude") {
            return .claudeCode
        }
        if lowered.contains("openai codex") || lowered == "codex" || lowered.contains("codex") {
            return .codex
        }

        return nil
    }

    private func normalized(_ candidate: String?) -> String? {
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else {
            return nil
        }

        return candidate
    }
}
