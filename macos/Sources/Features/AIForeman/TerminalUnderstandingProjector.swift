import Foundation

struct TerminalUnderstandingProjector {
    func project(
        current: TerminalSnapshot,
        classification: AgentMeaningDetector.Detection?,
        lastOutcome: TerminalOutcomeReport?,
        lastEvent: String
    ) -> TerminalUnderstanding {
        let state = classifyState(
            current: current,
            lastOutcome: lastOutcome,
            classification: classification
        )
        let suggestedActions = makeSuggestions(
            for: current,
            state: state,
            classification: classification,
            lastEvent: lastEvent
        )

        return TerminalUnderstanding(
            terminalID: current.terminalID,
            title: current.title,
            cwd: current.cwd,
            state: state,
            agentIdentity: classification?.identity ?? .none,
            agentInteractionState: classification?.interactionState ?? .unknown,
            supportLevel: classification?.supportLevel ?? .genericFallback,
            lastMeaningfulEvent: lastEvent,
            shortExplanation: explain(
                state: state,
                snapshot: current,
                classification: classification,
                lastEvent: lastEvent
            ),
            importantDetails: importantDetails(from: current.visibleText, state: state),
            evidence: classification?.evidence ?? [],
            suggestedNextActions: suggestedActions,
            agentInteractionContext: classification?.context ?? .none
        )
    }

    static func meaningfulTerminalLines(from text: String) -> [String] {
        text.split(separator: "\n")
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty &&
                    !looksLikePrompt(trimmed) &&
                    !looksLikeTerminalInputChrome(trimmed)
            }
    }

    private func classifyState(
        current: TerminalSnapshot,
        lastOutcome: TerminalOutcomeReport?,
        classification: AgentMeaningDetector.Detection?
    ) -> TerminalUnderstandingState {
        if let classification {
            switch classification.interactionState {
            case .waitingApproval, .waitingChoice, .waitingText:
                return .waiting
            case .running:
                return .running
            case .completed:
                return .succeeded
            case .error:
                return .failed
            case .unknown:
                switch classification.runtimeState {
                case .blocked:
                    return .waiting
                case .working:
                    return .running
                case .idle:
                    return .idle
                case .unknown:
                    break
                }
            }
        }

        if let lastOutcome, lastOutcome.terminalID == current.terminalID {
            switch lastOutcome.outcome {
            case .success:
                return .succeeded
            case .failure:
                return .failed
            case .needsInput:
                return .waiting
            case .hung:
                return .failed
            case .stillRunning, .unknown:
                break
            }
        }
        if current.visibleText.lowercased().contains("command not found") || current.signals.likelyErrorState {
            return .failed
        }
        if current.signals.likelyWaitingForInput {
            return .waiting
        }
        if current.signals.likelyLongRunning {
            return .running
        }
        if current.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .idle
        }
        return .noisyHealthy
    }

    private func explain(
        state: TerminalUnderstandingState,
        snapshot: TerminalSnapshot,
        classification: AgentMeaningDetector.Detection?,
        lastEvent: String
    ) -> String {
        if let classification {
            let name = classification.identity.displayName ?? snapshot.title
            switch classification.interactionState {
            case .waitingApproval:
                return "\(name) is waiting for approval to continue."
            case .waitingChoice:
                return "\(name) is waiting for your selection."
            case .waitingText:
                if Self.looksLikeQuestion(lastEvent) {
                    return "\(name) is waiting for your response: \(lastEvent)"
                }
                return "\(name) is waiting for your response."
            case .running:
                return "\(name) is actively working in this terminal."
            case .completed:
                return "\(name) completed its turn: \(lastEvent)"
            case .error:
                return "\(name) hit an error: \(lastEvent)"
            case .unknown:
                break
            }
        }

        switch state {
        case .failed:
            return "The terminal failed: \(lastEvent)"
        case .succeeded:
            return "The terminal completed successfully: \(lastEvent)"
        case .running:
            return "The \(snapshot.title) terminal is still running a long-lived command."
        case .waiting:
            return "The terminal is waiting for input."
        case .idle:
            return "The terminal is idle."
        case .noisyHealthy:
            return "The terminal is producing output without signs of failure."
        }
    }

    private func importantDetails(from visibleText: String, state: TerminalUnderstandingState) -> [String] {
        let lines: [String]
        switch state {
        case .waiting:
            lines = Self.meaningfulTerminalLines(from: visibleText)
        default:
            lines = visibleText.split(separator: "\n").map(String.init)
        }

        switch state {
        case .failed:
            return Array(lines.suffix(3))
        default:
            return Array(lines.suffix(2))
        }
    }

    private func makeSuggestions(
        for snapshot: TerminalSnapshot,
        state: TerminalUnderstandingState,
        classification: AgentMeaningDetector.Detection?,
        lastEvent: String
    ) -> [TerminalSuggestedAction] {
        let input = snapshot.lastInputPreview ?? ""

        if let classification {
            switch classification.interactionState {
            case .waitingApproval:
                return [
                    .init(title: "Review the approval request", command: nil, reason: lastEvent, isRecommended: true),
                    .init(title: "Let Foreman explain the requested action", command: nil, reason: "Use this when the approval UI is dense.", isRecommended: false),
                ]
            case .waitingChoice:
                return [
                    .init(title: "Inspect the available choices", command: nil, reason: lastEvent, isRecommended: true),
                    .init(title: "Ask Foreman to summarize the options", command: nil, reason: "Useful when the menu is noisy.", isRecommended: false),
                ]
            case .waitingText:
                return [
                    .init(title: "Reply to the agent", command: nil, reason: lastEvent, isRecommended: true),
                ]
            case .error:
                return [
                    .init(title: "Inspect the failure details", command: nil, reason: lastEvent, isRecommended: true),
                ]
            case .running, .completed, .unknown:
                break
            }
        }

        if state == .failed && lastEvent.lowercased().contains("command not found") && input.contains("hfind") {
            return [
                .init(
                    title: "Run the likely intended find command",
                    command: "find . -print",
                    reason: "This looks like a typo of a standard shell command.",
                    isRecommended: true
                ),
                .init(
                    title: "Try fd if a faster file search was intended",
                    command: "fd .",
                    reason: "The intended tool may have been `fd` rather than `find`.",
                    isRecommended: false
                ),
                .init(
                    title: "Confirm whether hfind was intentional",
                    command: nil,
                    reason: "Use this when the missing command may be project-specific.",
                    isRecommended: false
                ),
            ]
        }

        if state == .failed {
            return [
                .init(title: "Inspect the failure details", command: nil, reason: lastEvent, isRecommended: true),
                .init(
                    title: "Rerun the command after fixing the obvious issue",
                    command: input.isEmpty ? nil : input,
                    reason: "Useful when the failure was transient or typo-driven.",
                    isRecommended: false
                ),
                .init(
                    title: "Ask Foreman for a focused explanation",
                    command: nil,
                    reason: "Useful if the output is noisy and needs compression.",
                    isRecommended: false
                ),
            ]
        }

        return []
    }

    private static func looksLikePrompt(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let promptMarkers = ["$", "%", "#", ">", "λ", "❯", "➜", "→", "⇒", "›"]
        return promptMarkers.contains(where: {
            trimmed == $0 || trimmed.hasPrefix($0 + " ") || trimmed.hasSuffix(" " + $0) || trimmed.hasSuffix($0)
        })
    }

    private static func looksLikeQuestion(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).contains("?")
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
