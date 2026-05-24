import Foundation

struct ForemanObservedContextBuilder {
    struct Result: Equatable, Sendable {
        let context: ForemanObservedTerminalContext
        let understandingsByTerminalID: [String: TerminalUnderstanding]
        let runtimeEntriesByTerminalID: [String: AgentRuntimeRefreshPlan.Entry]
    }

    private let understandingEngine = TerminalUnderstandingEngine()

    func build(
        snapshots: [TerminalSnapshot],
        previousSnapshotsByTerminalID: [String: TerminalSnapshot] = [:],
        lastOutcomesByTerminalID: [String: TerminalOutcomeReport] = [:],
        attachmentHintsByTerminalID: [String: AgentRuntimeAttachmentHint] = [:],
        kimiWireRecordsByTerminalID: [String: [KimiWireRecord]] = [:],
        codexWireRecordsByTerminalID: [String: [CodexWireRecord]] = [:],
        claudeWireRecordsByTerminalID: [String: [ClaudeSessionState]] = [:]
    ) -> Result {
        let runtimePlan = AgentRuntimeRefreshPlan(
            snapshots: snapshots,
            previousSnapshotsByTerminalID: previousSnapshotsByTerminalID,
            kimiWireRecordsByTerminalID: kimiWireRecordsByTerminalID,
            codexWireRecordsByTerminalID: codexWireRecordsByTerminalID,
            claudeWireRecordsByTerminalID: claudeWireRecordsByTerminalID,
            attachmentHintsByTerminalID: attachmentHintsByTerminalID
        )

        let understandings = runtimePlan.entries.map { entry in
            let snapshot = entry.snapshot
            return understandingEngine.understand(
                current: snapshot,
                previous: previousSnapshotsByTerminalID[snapshot.terminalID],
                lastOutcome: lastOutcomesByTerminalID[snapshot.terminalID],
                wireRecords: kimiWireRecordsByTerminalID[snapshot.terminalID] ?? [],
                codexWireRecords: codexWireRecordsByTerminalID[snapshot.terminalID] ?? [],
                claudeWireRecords: claudeWireRecordsByTerminalID[snapshot.terminalID] ?? [],
                runtimeDetection: entry.detection
            )
        }
        let understandingsByTerminalID = Dictionary(
            uniqueKeysWithValues: understandings.map { ($0.terminalID, $0) }
        )
        let runtimeEntriesByTerminalID = Dictionary(
            uniqueKeysWithValues: runtimePlan.entries.map { ($0.snapshot.terminalID, $0) }
        )

        return Result(
            context: ForemanObservedTerminalContext(
                terminals: snapshots,
                understandings: understandings
            ),
            understandingsByTerminalID: understandingsByTerminalID,
            runtimeEntriesByTerminalID: runtimeEntriesByTerminalID
        )
    }
}
