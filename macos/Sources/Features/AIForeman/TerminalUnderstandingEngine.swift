import Foundation

struct TerminalUnderstandingEngine {
    private let meaningDetector = AgentMeaningDetector()
    private let projector = TerminalUnderstandingProjector()

    func understand(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?,
        wireRecords: [KimiWireRecord] = [],
        codexWireRecords: [CodexWireRecord] = [],
        claudeWireRecords: [ClaudeSessionState] = [],
        runtimeDetection: AgentRuntimeDetector.Detection? = nil
    ) -> TerminalUnderstanding {
        let applicableOutcome = applicableOutcome(for: current, previous: previous, lastOutcome: lastOutcome)
        let lastEvent = extractLastMeaningfulEvent(from: current, previous: previous, lastOutcome: applicableOutcome)
        let classification = meaningDetector.detect(
            current: current,
            previous: previous,
            lastOutcome: applicableOutcome,
            lastEvent: lastEvent,
            wireRecords: wireRecords,
            codexWireRecords: codexWireRecords,
            claudeWireRecords: claudeWireRecords,
            runtimeDetection: runtimeDetection
        )

        return projector.project(
            current: current,
            classification: classification,
            lastOutcome: applicableOutcome,
            lastEvent: lastEvent
        )
    }

    func makeOverview(
        current: [TerminalUnderstanding],
        previous: [TerminalUnderstanding]
    ) -> TerminalOverview {
        let currentIDs = Set(current.map(\.terminalID))
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.terminalID, $0) })
        let changedCurrent = current.filter { previousByID[$0.terminalID] != $0 }.map(\.terminalID)
        let removed = previous.map(\.terminalID).filter { !currentIDs.contains($0) }
        let changed = changedCurrent + removed

        if let changedTerminal = current.first(where: { changedCurrent.contains($0.terminalID) }) {
            return TerminalOverview(
                summary: "\(changedTerminal.terminalID): \(changedTerminal.shortExplanation)",
                changedTerminalIDs: changed,
                primaryTerminalID: changedTerminal.terminalID
            )
        }

        if let removedTerminalID = removed.first {
            return TerminalOverview(
                summary: "\(removedTerminalID) is no longer available.",
                changedTerminalIDs: changed,
                primaryTerminalID: removedTerminalID
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

    private func extractLastMeaningfulEvent(
        from current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?
    ) -> String {
        if let lastOutcome, lastOutcome.terminalID == current.terminalID, let summary = lastOutcome.summary {
            return summary
        }
        let event = TerminalScreenText.lastMeaningfulEvent(
            currentVisibleText: current.visibleText,
            previousVisibleText: previous?.visibleText ?? ""
        )
        return event.isEmpty ? "No meaningful terminal event detected." : event
    }

    private func applicableOutcome(
        for current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?
    ) -> TerminalOutcomeReport? {
        guard let lastOutcome, lastOutcome.terminalID == current.terminalID else {
            return nil
        }

        let activeCommand = normalizedCommand(current.lastInputPreview)
            ?? normalizedCommand(previous?.lastInputPreview)
        guard let activeCommand, activeCommand == normalizedCommand(lastOutcome.sentCommand) else {
            return nil
        }

        if isFreshExecutionTransition(current: current, previous: previous) {
            return nil
        }

        return lastOutcome
    }

    private func normalizedCommand(_ command: String?) -> String? {
        guard let command else {
            return nil
        }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func isFreshExecutionTransition(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?
    ) -> Bool {
        guard let previous else { return false }
        guard previous.signals.likelyWaitingForInput else { return false }
        guard !current.signals.likelyWaitingForInput else { return false }
        return current.visibleText != previous.visibleText
    }
}
