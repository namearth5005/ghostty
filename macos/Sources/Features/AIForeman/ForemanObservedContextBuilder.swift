import Foundation

struct ForemanObservedContextBuilder {
    struct Result: Equatable, Sendable {
        let context: ForemanObservedTerminalContext
        let understandingsByTerminalID: [String: TerminalUnderstanding]
        let runtimeEntriesByTerminalID: [String: AgentRuntimeRefreshPlan.Entry]
    }

    private let understandingEngine = TerminalUnderstandingEngine()
    private let workerSnapshotProjector = TerminalWorkerSnapshotProjector()

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

        let initialUnderstandings = runtimePlan.entries.map { entry in
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
        let snapshotsByTerminalID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.terminalID, $0) })
        let workerSnapshots: [String: TerminalWorkerSnapshot] = Dictionary(
            uniqueKeysWithValues: initialUnderstandings.compactMap { understanding -> (String, TerminalWorkerSnapshot)? in
                guard let snapshot = snapshotsByTerminalID[understanding.terminalID] else {
                    return nil
                }

                let workerSnapshot = workerSnapshotProjector.project(
                    snapshot: snapshot,
                    workerGoal: nil,
                    identity: understanding.agentIdentity,
                    context: understanding.agentInteractionContext,
                    fallbackState: understanding.state
                )

                return workerSnapshot.map { (understanding.terminalID, $0) }
            }
        )
        let understandings = initialUnderstandings.map { understanding in
            guard let workerSnapshot = workerSnapshots[understanding.terminalID] else {
                return understanding
            }

            return TerminalUnderstanding(
                terminalID: understanding.terminalID,
                title: understanding.title,
                cwd: understanding.cwd,
                state: understanding.state,
                agentIdentity: understanding.agentIdentity,
                agentInteractionState: understanding.agentInteractionState,
                supportLevel: understanding.supportLevel,
                lastMeaningfulEvent: understanding.lastMeaningfulEvent,
                shortExplanation: understanding.shortExplanation,
                importantDetails: understanding.importantDetails,
                evidence: understanding.evidence,
                suggestedNextActions: understanding.suggestedNextActions,
                agentInteractionContext: authoritativeInteractionContext(
                    for: understanding,
                    workerSnapshot: workerSnapshot
                ),
                workerSnapshot: workerSnapshot
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
                understandings: understandings,
                workerSnapshots: workerSnapshots
            ),
            understandingsByTerminalID: understandingsByTerminalID,
            runtimeEntriesByTerminalID: runtimeEntriesByTerminalID
        )
    }

    private func authoritativeInteractionContext(
        for understanding: TerminalUnderstanding,
        workerSnapshot: TerminalWorkerSnapshot
    ) -> AgentInteractionContext {
        switch workerSnapshot.state.attention {
        case .replyRequired, .choiceRequired, .approvalRequired, .error:
            return understanding.agentInteractionContext

        case .none:
            switch workerSnapshot.state.lifecycle {
            case .running:
                return .running(
                    stepDescription: workerSnapshot.state.summary,
                    sessionID: workerSnapshot.workerSessionID,
                    revision: workerSnapshot.revision
                )
            case .completed:
                return .completed(
                    summary: workerSnapshot.state.summary,
                    sessionID: workerSnapshot.workerSessionID,
                    revision: workerSnapshot.revision
                )
            case .failed:
                return .error(
                    description: workerSnapshot.state.summary,
                    sessionID: workerSnapshot.workerSessionID,
                    revision: workerSnapshot.revision
                )
            case .idle, .blocked:
                return understanding.agentInteractionContext
            }
        }
    }
}
