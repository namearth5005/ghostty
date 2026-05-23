import Foundation

struct AgentIdentityDetector {
    func identity(for snapshot: TerminalSnapshot) -> AgentIdentity? {
        if let foregroundProcessName = normalized(snapshot.runtime.foregroundProcessName) {
            if let processMatch = detectIdentity(inProcessName: foregroundProcessName) {
                return processMatch
            }

            return detectIdentity(inVisibleText: snapshot.visibleText)
        }

        if let visibleMatch = detectIdentity(inVisibleText: snapshot.visibleText) {
            return visibleMatch
        }

        return detectIdentity(inTitle: snapshot.title)
    }

    func matches(_ snapshot: TerminalSnapshot, identity expectedIdentity: AgentIdentity) -> Bool {
        identity(for: snapshot) == expectedIdentity
    }

    private func detectIdentity(inVisibleText visibleText: String) -> AgentIdentity? {
        let loweredVisible = visibleText.lowercased()
        let lines = normalizedVisibleLines(from: loweredVisible)

        if lines.contains(where: { $0.hasPrefix("welcome to kimi code cli") || $0.hasPrefix("agent (kimi") }) {
            return .kimi
        }
        if lines.contains(where: { $0 == "welcome to claude code" || $0 == "claude code" }) ||
            looksLikeClaudeTrustPrompt(loweredVisible) {
            return .claudeCode
        }
        if lines.contains(where: looksLikeCodexBannerLine) {
            return .codex
        }

        return nil
    }

    private func detectIdentity(inProcessName candidate: String?) -> AgentIdentity? {
        guard let candidate else { return nil }
        let lowered = candidate.lowercased()

        if matchesExplicitProcessName(lowered, aliases: ["kimi", "kimi code", "kimi-code"]) {
            return .kimi
        }
        if matchesExplicitProcessName(lowered, aliases: ["claude", "claude code", "claude-code"]) {
            return .claudeCode
        }
        if matchesExplicitProcessName(lowered, aliases: ["codex", "openai codex"]) {
            return .codex
        }

        return nil
    }

    private func detectIdentity(inTitle candidate: String?) -> AgentIdentity? {
        guard let lowered = normalized(candidate)?.lowercased() else {
            return nil
        }

        if matchesExplicitTitle(lowered, exact: "kimi code") {
            return .kimi
        }
        if matchesExplicitTitle(lowered, exact: "claude code") {
            return .claudeCode
        }
        if matchesExplicitTitle(lowered, exact: "openai codex") {
            return .codex
        }

        return nil
    }

    private func matchesExplicitTitle(_ loweredTitle: String, exact canonicalTitle: String) -> Bool {
        loweredTitle == canonicalTitle ||
            loweredTitle.hasPrefix(canonicalTitle + " (") ||
            loweredTitle.hasPrefix(canonicalTitle + " -") ||
            loweredTitle.hasPrefix(canonicalTitle + " —")
    }

    private func normalizedVisibleLines(from loweredVisibleText: String) -> [String] {
        loweredVisibleText
            .split(separator: "\n")
            .map { line in
                String(line)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "│┃|"))
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    private func looksLikeClaudeTrustPrompt(_ loweredVisibleText: String) -> Bool {
        let hasTrustQuestion = loweredVisibleText.contains(
            "quick safety check: is this a project you created or one you trust?"
        )
        let hasPromptControls = loweredVisibleText.contains("enter to confirm") &&
            loweredVisibleText.contains("esc to cancel")
        let hasWorkspaceContext = loweredVisibleText.contains("accessing workspace:") ||
            loweredVisibleText.contains("security guide")

        return hasTrustQuestion && hasPromptControls && hasWorkspaceContext
    }

    private func looksLikeCodexBannerLine(_ line: String) -> Bool {
        line == "openai codex" ||
            line.hasPrefix(">_ openai codex") ||
            line.hasPrefix("openai codex (v")
    }

    private func matchesExplicitProcessName(_ loweredProcessName: String, aliases: [String]) -> Bool {
        aliases.contains(loweredProcessName)
    }

    private func normalized(_ candidate: String?) -> String? {
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else {
            return nil
        }

        return candidate
    }
}
