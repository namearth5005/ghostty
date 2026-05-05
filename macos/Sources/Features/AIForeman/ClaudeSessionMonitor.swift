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
    private let sessionsBase: URL

    private var timer: Timer?
    private var recordBuffer: [ClaudeSessionState] = []
    private var lastStatus: String?

    var onEvent: ((ClaudeSessionState) -> Void)?
    var onError: ((Error) -> Void)?

    /// `pid` is the foreground process ID of the Claude Code instance.
    /// If nil, the monitor scans all session files and picks the most recent.
    init(pid: Int?, sessionsBase: URL? = nil) {
        self.pid = pid
        self.sessionsBase = sessionsBase ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }

    func start() {
        stop()
        recordBuffer.removeAll()
        lastStatus = nil

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
                return state
            }
            DebugLogger.log("[ClaudeSessionMonitor] PID file not found for \(pid), falling back to scan")
        }

        // Fallback: scan all session files and pick the most recently modified
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsBase.path) else {
            return nil
        }

        let jsonFiles = files
            .filter { $0.hasSuffix(".json") }
            .map { sessionsBase.appendingPathComponent($0) }

        let result = jsonFiles.compactMap { url -> (ClaudeSessionState, Date)? in
            guard let state = parseState(at: url),
                  let modDate = fileModDate(url) else { return nil }
            return (state, modDate)
        }.max(by: { $0.1 < $1.1 })?.0

        if let result {
            DebugLogger.log("[ClaudeSessionMonitor] fallback scan matched file status=\(result.status ?? "nil") pid=\(result.pid)")
        }
        return result
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
}
