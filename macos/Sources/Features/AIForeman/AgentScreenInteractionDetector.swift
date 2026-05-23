import Foundation

struct AgentScreenInteractionDetector {
    enum Reason: Equatable, Sendable {
        case kimiWelcome
        case kimiInputRegion
        case approvalPrompt
        case choiceMenu
    }

    struct Detection: Equatable, Sendable {
        let context: AgentInteractionContext
        let reason: Reason
    }

    func detect(
        identity: AgentIdentity,
        visibleText: String,
        lastEvent: String
    ) -> Detection? {
        let normalizedLastEvent = lastEvent.trimmingCharacters(in: .whitespacesAndNewlines)

        if identity == .kimi && isKimiWelcomeScreen(visibleText) {
            return Detection(
                context: .waitingText(question: nil),
                reason: .kimiWelcome
            )
        }

        if hasApprovalPrompt(in: visibleText, identity: identity) {
            return Detection(
                context: .waitingApproval(description: lastEvent, tool: nil),
                reason: .approvalPrompt
            )
        }

        if let menu = TerminalScreenText.activeChoiceMenuContext(from: visibleText) {
            let question = menu.question ?? (normalizedLastEvent.isEmpty ? nil : normalizedLastEvent)

            if !menu.options.isEmpty, let question {
                return Detection(
                    context: .waitingChoice(question: question, options: menu.options),
                    reason: .choiceMenu
                )
            }

            return Detection(
                context: .waitingText(question: question),
                reason: .choiceMenu
            )
        }

        if containsChoiceMarkers(in: visibleText, identity: identity),
           let question = activeChoicePromptQuestion(identity: identity, lastEvent: normalizedLastEvent) {
            return Detection(
                context: .waitingText(question: question),
                reason: .choiceMenu
            )
        }

        if identity == .kimi && isKimiInputRegion(visibleText) {
            return Detection(
                context: .waitingText(question: nil),
                reason: .kimiInputRegion
            )
        }

        return nil
    }

    private func hasApprovalPrompt(in visibleText: String, identity: AgentIdentity) -> Bool {
        let lines = visibleText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return false
        }

        let trailingApprovalLines = lines
            .reversed()
            .prefix { isApprovalTailLine(String($0), identity: identity) }

        guard !trailingApprovalLines.isEmpty else {
            return false
        }

        return trailingApprovalLines.contains { isApprovalMarker(String($0), identity: identity) }
    }

    private func isApprovalTailLine(_ line: String, identity: AgentIdentity) -> Bool {
        let lowered = line.lowercased()

        switch identity {
        case .kimi:
            return isKimiApprovalLine(lowered)
        case .codex:
            return isCodexApprovalLine(lowered)
        case .claudeCode:
            return isClaudeApprovalLine(lowered)
        case .none, .unknown:
            return false
        }
    }

    private func isApprovalMarker(_ line: String, identity: AgentIdentity) -> Bool {
        let lowered = line.lowercased()

        switch identity {
        case .kimi:
            return lowered.contains("shell is requesting approval to run command")
                || lowered.contains("approve once")
                || lowered.contains("approve for this session")
                || lowered.contains("reject, tell the model what to do instead")
        case .codex:
            return looksLikeCodexApprovalPrompt(lowered)
        case .claudeCode:
            return containsAny(lowered, markers: ["approve", "allow once", "allow always", "[y/n]", "yes / no", "allow this", "allow edit"])
        case .none, .unknown:
            return false
        }
    }

    private func isKimiApprovalLine(_ lowered: String) -> Bool {
        isApprovalMarker(lowered, identity: .kimi) ||
            isNumberedOptionLine(lowered) && containsAny(lowered, markers: ["approve", "reject"])
    }

    private func isCodexApprovalLine(_ lowered: String) -> Bool {
        looksLikeCodexApprovalPrompt(lowered) ||
            lowered.contains("permission required") ||
            lowered.contains("requesting permission") ||
            lowered.contains("needs your approval")
    }

    private func isClaudeApprovalLine(_ lowered: String) -> Bool {
        containsAny(lowered, markers: ["approve", "allow once", "allow always", "[y/n]", "yes / no", "allow this", "allow edit"])
    }

    private func containsChoiceMarkers(in visibleText: String, identity: AgentIdentity) -> Bool {
        let lowered = visibleText.lowercased()
        let choiceMarkers: [String]
        switch identity {
        case .kimi:
            choiceMarkers = ["choose one", "select an option"]
        case .codex:
            choiceMarkers = ["enter to confirm", "esc to cancel"]
        case .claudeCode:
            choiceMarkers = ["what do you want to do?", "enter to confirm", "esc to cancel"]
        case .none, .unknown:
            choiceMarkers = []
        }

        return containsAny(lowered, markers: choiceMarkers)
    }

    private func isKimiWelcomeScreen(_ visibleText: String) -> Bool {
        let loweredLines = normalizedNonEmptyLines(from: visibleText).map { $0.lowercased() }
        guard loweredLines.count >= 4 else {
            return false
        }

        guard loweredLines.allSatisfy(isKimiWelcomeLine) else {
            return false
        }

        return loweredLines.contains(where: { $0.contains("welcome to kimi code cli") }) &&
            loweredLines.contains(where: { $0.hasPrefix("directory:") }) &&
            loweredLines.contains(where: { $0.hasPrefix("model:") })
    }

    private func isKimiInputRegion(_ visibleText: String) -> Bool {
        let loweredLines = normalizedNonEmptyLines(from: visibleText).map { $0.lowercased() }
        guard loweredLines.count >= 3 else {
            return false
        }

        guard loweredLines.allSatisfy(isKimiInputLine) else {
            return false
        }

        return loweredLines.contains(where: { $0.contains("agent (kimi") }) &&
            loweredLines.contains(where: { $0.hasPrefix("context:") }) &&
            loweredLines.contains(where: { $0.contains("input") })
    }

    private func activeChoicePromptQuestion(identity: AgentIdentity, lastEvent: String) -> String? {
        guard !lastEvent.isEmpty else {
            return nil
        }

        if TerminalScreenText.looksLikeQuestion(lastEvent) {
            return lastEvent
        }

        return containsChoiceMarkers(in: lastEvent, identity: identity) ? lastEvent : nil
    }

    private func containsAny(_ text: String, markers: [String]) -> Bool {
        markers.contains(where: text.contains)
    }

    private func normalizedNonEmptyLines(from visibleText: String) -> [String] {
        visibleText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func isKimiWelcomeLine(_ lowered: String) -> Bool {
        lowered.contains("welcome to kimi code cli") ||
            lowered == "send /help for help information." ||
            lowered.hasPrefix("directory:") ||
            lowered.hasPrefix("model:")
    }

    private func isKimiInputLine(_ lowered: String) -> Bool {
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

        return lowered.hasPrefix("agent (kimi") || lowered.hasPrefix("context:")
    }

    private func isNumberedOptionLine(_ line: String) -> Bool {
        guard let firstScalar = line.unicodeScalars.first,
              CharacterSet.decimalDigits.contains(firstScalar) else {
            return false
        }

        return line.contains(". ")
    }

    private func looksLikeCodexApprovalPrompt(_ text: String) -> Bool {
        if text.contains("permission required") ||
            text.contains("requesting permission") ||
            text.contains("needs your approval") {
            return true
        }

        if text.contains("[y/n]") &&
            (text.contains("approve") || text.contains("permission") || text.contains("allow")) {
            return true
        }

        return false
    }
}
