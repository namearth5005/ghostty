import Foundation

enum AgentTerminalMatcher {
    static func matches(_ snapshot: TerminalSnapshot, identity: AgentIdentity) -> Bool {
        switch identity {
        case .claudeCode:
            return matches(
                snapshot,
                primaryMarkers: ["claude code", "claude"],
                visibleMarkers: ["claude code"]
            )
        case .codex:
            return matches(
                snapshot,
                primaryMarkers: ["openai codex", "codex"],
                visibleMarkers: ["openai codex"]
            )
        case .kimi:
            return matches(
                snapshot,
                primaryMarkers: ["kimi code", "kimi"],
                visibleMarkers: ["welcome to kimi code cli", "agent (kimi"]
            )
        case .none, .unknown:
            return false
        }
    }

    private static func matches(
        _ snapshot: TerminalSnapshot,
        primaryMarkers: [String],
        visibleMarkers: [String]
    ) -> Bool {
        let primaryCandidates = [
            snapshot.runtime.foregroundProcessName?.lowercased(),
            snapshot.title.lowercased(),
            snapshot.lastInputPreview?.lowercased(),
        ].compactMap { $0 }

        if primaryCandidates.contains(where: { candidate in
            primaryMarkers.contains(where: candidate.contains)
        }) {
            return true
        }

        let visible = snapshot.visibleText.lowercased()
        return visibleMarkers.contains(where: visible.contains)
    }
}
