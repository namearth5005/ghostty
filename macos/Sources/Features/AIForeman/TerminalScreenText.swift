import Foundation

enum TerminalScreenText {
    struct ChoiceMenuContext: Equatable {
        let question: String?
        let options: [String]
    }

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

        if let choiceQuestion = activeChoiceMenuContext(from: currentVisibleText)?.question {
            return choiceQuestion
        }

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

    static func activeChoiceMenuContext(from visibleText: String) -> ChoiceMenuContext? {
        let trimmedLines = visibleText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let optionIndices = trimmedLines.indices.filter { isNumberedChoiceOption(trimmedLines[$0]) }

        guard optionIndices.count >= 2,
              let firstOptionIndex = optionIndices.first,
              let lastOptionIndex = optionIndices.last else {
            return nil
        }

        let trailingLines: [String]
        if lastOptionIndex + 1 < trimmedLines.endIndex {
            trailingLines = Array(trimmedLines[(lastOptionIndex + 1)...])
        } else {
            trailingLines = []
        }
        guard trailingLines.allSatisfy(isChoiceMenuFooter) else {
            return nil
        }

        let linesBeforeOptions = Array(trimmedLines[..<firstOptionIndex])
        let options = optionIndices.compactMap { extractChoiceOption(from: trimmedLines[$0]) }

        return ChoiceMenuContext(
            question: linesBeforeOptions.last(where: looksLikeQuestion),
            options: options
        )
    }

    private static func isNumberedChoiceOption(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("❯ ") {
            let remainder = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return isPlainNumberedChoiceOption(String(remainder))
        }

        return isPlainNumberedChoiceOption(trimmed)
    }

    private static func isPlainNumberedChoiceOption(_ line: String) -> Bool {
        guard let firstScalar = line.unicodeScalars.first,
              CharacterSet.decimalDigits.contains(firstScalar),
              let dotRange = line.range(of: ". ") else {
            return false
        }

        return dotRange.lowerBound != line.startIndex
    }

    private static func extractChoiceOption(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let normalized: String

        if trimmed.hasPrefix("❯ ") {
            normalized = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else {
            normalized = trimmed
        }

        guard let dotRange = normalized.range(of: ". ") else {
            return nil
        }

        let option = String(normalized[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return option.isEmpty ? nil : option
    }

    private static func isChoiceMenuFooter(_ line: String) -> Bool {
        let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lowered.isEmpty else { return false }

        return lowered.contains("enter to confirm") ||
            lowered.contains("esc to cancel")
    }
}
