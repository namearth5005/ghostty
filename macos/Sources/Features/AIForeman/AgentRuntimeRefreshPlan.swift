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
        let shouldRestartMonitor: Bool
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
            let shouldRestartMonitor = Self.shouldRestartMonitor(
                for: identity,
                current: snapshot,
                previous: previousSnapshotsByTerminalID[snapshot.terminalID]
            )

            return Entry(
                snapshot: snapshot,
                detection: detection,
                monitorTarget: monitorTarget,
                shouldRestartMonitor: shouldRestartMonitor
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

    private static func shouldRestartMonitor(
        for identity: AgentIdentity?,
        current: TerminalSnapshot,
        previous: TerminalSnapshot?
    ) -> Bool {
        guard let identity,
              identity == .codex || identity == .kimi || identity == .claudeCode,
              let previous else {
            return false
        }

        if let previousPID = previous.runtime.foregroundProcessID,
           let currentPID = current.runtime.foregroundProcessID,
           previousPID != currentPID {
            return true
        }

        return previous.signals.likelyWaitingForInput &&
            !current.signals.likelyWaitingForInput &&
            current.visibleText != previous.visibleText
    }
}
