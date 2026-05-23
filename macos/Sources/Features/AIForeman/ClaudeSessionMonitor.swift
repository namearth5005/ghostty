import Foundation

/// Monitors Claude Code's session state file for a given process.
///
/// Claude Code writes session metadata to:
///   ~/.claude/sessions/{pid}.json
///
/// The file contains a `status` field (e.g., "idle", "working") that we poll
/// to determine the agent's coarse state. Unlike Kimi/Codex, this is a single
/// JSON file that gets overwritten in place rather than appended to.
final class ClaudeSessionMonitor {
    let pid: Int?
    let workingDirectory: String?
    private let sessionsBase: URL
    private let now: () -> Date

    private var timer: Timer?
    private var recordBuffer: [ClaudeSessionState] = []
    private var lastStatus: String?
    private var monitorStartedAt: Date?
    private var resolvedFallbackPath: URL?

    var onEvent: ((ClaudeSessionState) -> Void)?
    var onError: ((Error) -> Void)?

    /// `pid` is the foreground process ID of the Claude Code instance.
    /// If nil, the monitor scans all session files and picks the most recent.
    init(
        pid: Int?,
        workingDirectory: String? = nil,
        sessionsBase: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.pid = pid
        self.workingDirectory = workingDirectory
        self.sessionsBase = sessionsBase ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
        self.now = now
    }

    func start() {
        stop()
        recordBuffer.removeAll()
        lastStatus = nil
        monitorStartedAt = now()
        resolvedFallbackPath = nil

        let t = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer = t
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Returns the most recent session state.
    func records() -> [ClaudeSessionState] {
        return recordBuffer
    }

    // MARK: - Polling

    func poll() {
        guard let state = readSessionState() else { return }

        // Only emit when the status actually changes
        if let status = state.status, status != lastStatus {
            lastStatus = status
            recordBuffer.append(state)
            onEvent?(state)
        }
    }

    // MARK: - Session Discovery

    private func readSessionState() -> ClaudeSessionState? {
        if let pid {
            let path = sessionsBase.appendingPathComponent("\(pid).json")
            if let state = parseState(at: path) {
                DebugLogger.log("[ClaudeSessionMonitor] matched PID file \(path.lastPathComponent) status=\(state.status ?? "nil")")
                resolvedFallbackPath = nil
                return state
            }
            DebugLogger.log("[ClaudeSessionMonitor] PID file not found for \(pid), falling back to scan")
        }

        if let resolvedFallbackPath {
            if let state = parseState(at: resolvedFallbackPath) {
                return state
            }
            self.resolvedFallbackPath = nil
        }

        resolvedFallbackPath = resolveFallbackPath()

        guard let resolvedFallbackPath,
              let state = parseState(at: resolvedFallbackPath) else {
            return nil
        }

        DebugLogger.log("[ClaudeSessionMonitor] fallback scan matched file status=\(state.status ?? "nil") pid=\(state.pid)")
        return state
    }

    private func resolveFallbackPath() -> URL? {
        // Fallback: scan all session files and pick the most recently modified
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsBase.path) else {
            return nil
        }

        let stalenessThreshold = now().addingTimeInterval(-600)
        let launchGraceDate = monitorStartedAt?.addingTimeInterval(-5)
        let jsonFiles = files
            .filter { $0.hasSuffix(".json") }
            .map { sessionsBase.appendingPathComponent($0) }

        let candidates = jsonFiles.compactMap { url -> (ClaudeSessionState, Date)? in
            guard let state = parseState(at: url),
                  let modDate = fileModDate(url) else { return nil }
            guard modDate > stalenessThreshold else { return nil }
            if let launchGraceDate, modDate < launchGraceDate {
                return nil
            }
            return (state, modDate)
        }

        let matchingCandidates: [(ClaudeSessionState, Date)]
        if let workingDirectory, !workingDirectory.isEmpty {
            matchingCandidates = candidates.filter { state, _ in
                guard let cwd = state.cwd, !cwd.isEmpty else { return false }
                return pathsMatch(lhs: cwd, rhs: workingDirectory)
            }
        } else {
            matchingCandidates = candidates
        }

        return matchingCandidates.max(by: { $0.1 < $1.1 })?.0.sessionFileURL(in: sessionsBase)
    }

    private func parseState(at url: URL) -> ClaudeSessionState? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = FileManager.default.contents(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(ClaudeSessionState.self, from: data)
        } catch {
            onError?(error)
            return nil
        }
    }

    private func fileModDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func pathsMatch(lhs: String, rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
    }
}

private extension ClaudeSessionState {
    func sessionFileURL(in base: URL) -> URL {
        base.appendingPathComponent("\(pid).json")
    }
}
