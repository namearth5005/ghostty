import Foundation

enum TerminalScreenText {
    static func meaningfulLines(from text: String) -> [String] {
        text.split(separator: "\n")
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty &&
                    !looksLikePrompt(trimmed) &&
                    !looksLikeTerminalInputChrome(trimmed)
            }
    }

    static func lastMeaningfulEvent(
        currentVisibleText: String,
        previousVisibleText: String
    ) -> String {
        let previousLines = Set(previousVisibleText.split(separator: "\n").map(String.init))
        let currentLines = meaningfulLines(from: currentVisibleText)

        return currentLines.last(where: { !previousLines.contains($0) && !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? currentLines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? ""
    }

    static func looksLikeQuestion(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).contains("?")
    }

    private static func looksLikePrompt(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let promptMarkers = ["$", "%", "#", ">", "λ", "❯", "➜", "→", "⇒", "›"]
        return promptMarkers.contains(where: {
            trimmed == $0 || trimmed.hasPrefix($0 + " ") || trimmed.hasSuffix(" " + $0) || trimmed.hasSuffix($0)
        })
    }

    private static func looksLikeTerminalInputChrome(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()

        if lowered == "input" {
            return true
        }

        let withoutInput = lowered
            .replacingOccurrences(of: "input", with: "")
            .trimmingCharacters(in: .whitespaces)
        let inputChromeRun = withoutInput.filter { !$0.isWhitespace }
        if lowered.contains("input"),
           !inputChromeRun.isEmpty,
           inputChromeRun.allSatisfy({ $0 == "-" || $0 == "─" || $0 == "━" }) {
            return true
        }

        if lowered.hasPrefix("agent ("),
           lowered.contains("context:") ||
            lowered.contains("ctrl-") ||
            lowered.contains("shift-tab") ||
            lowered.contains("@:") {
            return true
        }

        if lowered.hasPrefix("context:") {
            return true
        }

        return false
    }
}
