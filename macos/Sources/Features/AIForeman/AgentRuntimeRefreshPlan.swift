import Foundation

struct AgentRuntimeRefreshPlan {
    enum MonitorTarget: Equatable, Sendable {
        case kimi(workingDirectory: String)
        case codex(workingDirectory: String)
        case claude(pid: Int, workingDirectory: String?)
        case claudeWorkingDirectory(String)
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
            let monitorTarget = Self.monitorTarget(for: identity, snapshot: snapshot)

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

    private static func monitorTarget(
        for identity: AgentIdentity?,
        snapshot: TerminalSnapshot
    ) -> MonitorTarget? {
        let workingDirectory = normalizedWorkingDirectory(snapshot.cwd)

        switch identity {
        case .some(.kimi):
            guard let workingDirectory else { return nil }
            return .kimi(workingDirectory: workingDirectory)

        case .some(.codex):
            guard let workingDirectory else { return nil }
            return .codex(workingDirectory: workingDirectory)

        case .some(.claudeCode):
            if let pid = snapshot.runtime.foregroundProcessID {
                return .claude(pid: pid, workingDirectory: workingDirectory)
            }
            if let workingDirectory {
                return .claudeWorkingDirectory(workingDirectory)
            }
            return nil

        case .some(.none), .some(.unknown), nil:
            return nil
        }
    }

    private static func normalizedWorkingDirectory(_ workingDirectory: String?) -> String? {
        guard let workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty else {
            return nil
        }

        return workingDirectory
    }
}
