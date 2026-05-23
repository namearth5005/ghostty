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
        let lowered = visibleText.lowercased()

        if identity == .kimi && isKimiWelcomeScreen(lowered) {
            return Detection(
                context: .waitingText(question: nil),
                reason: .kimiWelcome
            )
        }

        if hasApprovalPrompt(in: lowered, identity: identity) {
            return Detection(
                context: .waitingApproval(description: lastEvent, tool: nil),
                reason: .approvalPrompt
            )
        }

        if containsChoiceMarkers(in: visibleText, identity: identity) || looksLikeNumberedChoiceMenu(visibleText) {
            let question = lastEvent.isEmpty ? nil : lastEvent
            let options = extractNumberedOptions(visibleText)

            if !options.isEmpty, let question {
                return Detection(
                    context: .waitingChoice(question: question, options: options),
                    reason: .choiceMenu
                )
            }

            return Detection(
                context: .waitingText(question: question),
                reason: .choiceMenu
            )
        }

        if identity == .kimi && isKimiInputRegion(lowered) {
            return Detection(
                context: .waitingText(question: nil),
                reason: .kimiInputRegion
            )
        }

        return nil
    }

    private func hasApprovalPrompt(in loweredVisibleText: String, identity: AgentIdentity) -> Bool {
        switch identity {
        case .kimi:
            return loweredVisibleText.contains("shell is requesting approval to run command")
                || loweredVisibleText.contains("approve once")
                || loweredVisibleText.contains("approve for this session")
                || loweredVisibleText.contains("reject, tell the model what to do instead")
        case .codex:
            return looksLikeCodexApprovalPrompt(loweredVisibleText)
        case .claudeCode:
            return containsAny(loweredVisibleText, markers: ["approve", "allow once", "allow always", "[y/n]", "yes / no", "allow this", "allow edit"])
        case .none, .unknown:
            return false
        }
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

    private func extractNumberedOptions(_ text: String) -> [String] {
        let lines = text.split(separator: "\n").map(String.init)
        var options: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstScalar = trimmed.unicodeScalars.first else { continue }
            if CharacterSet.decimalDigits.contains(firstScalar) || trimmed.hasPrefix("❯ ") {
                if let dotRange = trimmed.range(of: ". ") {
                    let option = String(trimmed[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !option.isEmpty {
                        options.append(option)
                    }
                }
            }
        }
        return options
    }

    private func isKimiWelcomeScreen(_ loweredVisibleText: String) -> Bool {
        loweredVisibleText.contains("welcome to kimi code cli")
            && loweredVisibleText.contains("directory:")
            && loweredVisibleText.contains("model:")
    }

    private func isKimiInputRegion(_ loweredVisibleText: String) -> Bool {
        loweredVisibleText.contains("agent (kimi")
            && loweredVisibleText.contains("input")
    }

    private func looksLikeNumberedChoiceMenu(_ text: String) -> Bool {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let numberedCount = lines.filter { line in
            let scalars = Array(line.unicodeScalars)
            guard let first = scalars.first,
                  CharacterSet.decimalDigits.contains(first) || line.hasPrefix("❯ 1.") else {
                return false
            }
            return line.contains(". ")
        }.count

        return numberedCount >= 2
    }

    private func containsAny(_ text: String, markers: [String]) -> Bool {
        markers.contains(where: text.contains)
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
