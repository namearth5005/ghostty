import Foundation

struct TerminalUnderstandingEngine {
    func understand(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?
    ) -> TerminalUnderstanding {
        let visible = current.visibleText
        let lastEvent = extractLastMeaningfulEvent(from: current, previous: previous, lastOutcome: lastOutcome)
        let state = classifyState(current: current, lastOutcome: lastOutcome)
        let suggestedActions = makeSuggestions(for: current, state: state, lastEvent: lastEvent)

        return TerminalUnderstanding(
            terminalID: current.terminalID,
            title: current.title,
            cwd: current.cwd,
            state: state,
            lastMeaningfulEvent: lastEvent,
            shortExplanation: explain(state: state, snapshot: current, lastEvent: lastEvent),
            importantDetails: importantDetails(from: visible, state: state),
            suggestedNextActions: suggestedActions
        )
    }

    func makeOverview(
        current: [TerminalUnderstanding],
        previous: [TerminalUnderstanding]
    ) -> TerminalOverview {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.terminalID, $0) })
        let changed = current.filter { previousByID[$0.terminalID] != $0 }.map(\.terminalID)

        if let changedTerminal = current.first(where: { changed.contains($0.terminalID) }) {
            return TerminalOverview(
                summary: "\(changedTerminal.terminalID): \(changedTerminal.shortExplanation)",
                changedTerminalIDs: changed,
                primaryTerminalID: changedTerminal.terminalID
            )
        }

        let summary = current.isEmpty
            ? "No terminals are currently available."
            : current.map { "\($0.terminalID): \($0.shortExplanation)" }.joined(separator: " ")

        return TerminalOverview(
            summary: summary,
            changedTerminalIDs: [],
            primaryTerminalID: current.first?.terminalID
        )
    }

    private func classifyState(
        current: TerminalSnapshot,
        lastOutcome: TerminalOutcomeReport?
    ) -> TerminalUnderstandingState {
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

    private func extractLastMeaningfulEvent(
        from current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?
    ) -> String {
        if let lastOutcome, lastOutcome.terminalID == current.terminalID, let summary = lastOutcome.summary {
            return summary
        }
        let previousText = previous?.visibleText ?? ""
        let currentLines = current.visibleText
            .split(separator: "\n")
            .map(String.init)
            .filter { !looksLikePrompt($0) }
        let previousLines = Set(previousText.split(separator: "\n").map(String.init))
        return currentLines.last(where: { !previousLines.contains($0) && !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? currentLines.last
            ?? "No meaningful terminal event detected."
    }

    private func explain(
        state: TerminalUnderstandingState,
        snapshot: TerminalSnapshot,
        lastEvent: String
    ) -> String {
        switch state {
        case .failed:
            return "The terminal failed: \(lastEvent)"
        case .succeeded:
            return "The terminal completed successfully."
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
        let lines = visibleText.split(separator: "\n").map(String.init)
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
        lastEvent: String
    ) -> [TerminalSuggestedAction] {
        let input = snapshot.lastInputPreview ?? ""
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

    private func looksLikePrompt(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let promptSuffixes = ["$", "%", "#", ">", "λ", "❯", "➜", "→", "⇒"]
        return promptSuffixes.contains { trimmed.hasSuffix($0) }
    }
}
