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
        let normalizedLastEvent = lastEvent.trimmingCharacters(in: .whitespacesAndNewlines)

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

    private func isKimiWelcomeScreen(_ loweredVisibleText: String) -> Bool {
        loweredVisibleText.contains("welcome to kimi code cli")
            && loweredVisibleText.contains("directory:")
            && loweredVisibleText.contains("model:")
    }

    private func isKimiInputRegion(_ loweredVisibleText: String) -> Bool {
        loweredVisibleText.contains("agent (kimi")
            && loweredVisibleText.contains("input")
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
