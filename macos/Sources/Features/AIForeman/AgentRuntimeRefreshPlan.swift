import Foundation

struct AgentRuntimeRefreshPlan {
    enum MonitorTarget: Equatable, Sendable {
        case kimi(workingDirectory: String)
        case codex(workingDirectory: String?)
        case claude(pid: Int?)
    }

    struct Entry: Equatable, Sendable {
        let snapshot: TerminalSnapshot
        let detection: AgentRuntimeDetector.Detection?
        let monitorTarget: MonitorTarget?
    }

    let entries: [Entry]

    private let entriesByTerminalID: [String: Entry]

    init(
        snapshots: [TerminalSnapshot],
        previousSnapshotsByTerminalID: [String: TerminalSnapshot] = [:],
        kimiWireRecordsByTerminalID: [String: [KimiWireRecord]] = [:],
        codexWireRecordsByTerminalID: [String: [CodexWireRecord]] = [:],
        claudeWireRecordsByTerminalID: [String: [ClaudeSessionState]] = [:],
        detector: AgentRuntimeDetector = AgentRuntimeDetector()
    ) {
        let builtEntries = snapshots.map { snapshot in
            let detection = detector.detect(
                current: snapshot,
                previous: previousSnapshotsByTerminalID[snapshot.terminalID],
                kimiWireRecords: kimiWireRecordsByTerminalID[snapshot.terminalID] ?? [],
                codexWireRecords: codexWireRecordsByTerminalID[snapshot.terminalID] ?? [],
                claudeWireRecords: claudeWireRecordsByTerminalID[snapshot.terminalID] ?? []
            )
            let identity = detection?.identity ?? detector.identity(for: snapshot)

            let monitorTarget: MonitorTarget? = switch identity {
            case .some(.kimi):
                .kimi(workingDirectory: snapshot.cwd ?? "")
            case .some(.codex):
                .codex(workingDirectory: snapshot.cwd)
            case .some(.claudeCode):
                .claude(pid: snapshot.runtime.foregroundProcessID)
            case .some(.none), .some(.unknown), nil:
                nil
            }

            return Entry(
                snapshot: snapshot,
                detection: detection,
                monitorTarget: monitorTarget
            )
        }

        self.entries = builtEntries
        self.entriesByTerminalID = Dictionary(
            uniqueKeysWithValues: builtEntries.map { ($0.snapshot.terminalID, $0) }
        )
    }

    func entry(for terminalID: String) -> Entry? {
        entriesByTerminalID[terminalID]
    }
}
