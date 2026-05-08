import Foundation
import CryptoKit

/// Monitors Kimi's `wire.jsonl` for a given working directory, emitting structured wire records.
final class KimiWireSessionMonitor {
    let workingDirectory: String

    private let sessionsBaseDirectory: URL
    private let now: () -> Date
    private var timer: Timer?
    private var lastOffset: UInt64 = 0
    private var resolvedWirePath: URL?
    private var recordBuffer: [KimiWireRecord] = []
    private var monitorStartedAt: Date?

    var onEvent: ((KimiWireRecord) -> Void)?
    var onError: ((Error) -> Void)?

    init(
        workingDirectory: String,
        sessionsBaseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi/sessions"),
        now: @escaping () -> Date = Date.init
    ) {
        self.workingDirectory = workingDirectory
        self.sessionsBaseDirectory = sessionsBaseDirectory
        self.now = now
    }

    func start() {
        stop()
        resolvedWirePath = nil
        lastOffset = 0
        recordBuffer.removeAll()
        monitorStartedAt = now()

        // Attempt immediate discovery — only accept recent files on first start
        // to avoid picking up stale wire.jsonl from previous sessions.
        if let path = resolveWirePath() {
            resolvedWirePath = path
        }
        DebugLogger.log("[KimiWireMonitor] start wd='\(workingDirectory)' resolved='\(resolvedWirePath?.path ?? "nil")'")

        // Poll every 1.5 seconds for new lines
        let t = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer = t
        // Fire immediately if path resolved
        if resolvedWirePath != nil {
            poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Returns the current buffered records without clearing them.
    /// The buffer is trimmed to prevent unbounded growth.
    func records() -> [KimiWireRecord] {
        // Trim buffer to last 100 records to prevent unbounded growth
        if recordBuffer.count > 100 {
            recordBuffer.removeFirst(recordBuffer.count - 100)
        }
        return recordBuffer
    }

    // MARK: - Polling

    func poll() {
        // Re-resolve on every poll to catch new sessions (Kimi creates a new session per interaction).
        // Only switch to a newly-discovered file if it is recent (modified within last 2 min).
        // If resolve returns nil, keep reading from the current file so long-running
        // sessions aren't dropped just because the file hasn't been touched recently.
        let previousPath = resolvedWirePath
        let candidatePath = resolveWirePath()

        if let newPath = candidatePath, newPath != previousPath {
            let isRecent = fileIsRecent(newPath, within: 120)
            if previousPath == nil || isRecent {
                resolvedWirePath = newPath
                DebugLogger.log("[KimiWireMonitor] switched session from '\(previousPath?.lastPathComponent ?? "nil")' to '\(newPath.lastPathComponent)'")
                lastOffset = 0
            }
        }

        guard resolvedWirePath != nil else { return }
        DebugLogger.log("[KimiWireMonitor] polling path='\(resolvedWirePath?.lastPathComponent ?? "nil")' offset=\(lastOffset)")

        guard let path = resolvedWirePath else { return }

        // Read entire file using FileManager to ensure we see latest appends
        guard let fullData = FileManager.default.contents(atPath: path.path), !fullData.isEmpty else {
            // File may have been removed or truncated to empty; reset and try to rediscover
            resolvedWirePath = nil
            lastOffset = 0
            return
        }

        // If the file shrank, it was likely truncated/rewritten — reset and re-read from start
        if fullData.count < lastOffset {
            lastOffset = 0
        }

        guard fullData.count > lastOffset else { return }

        // Extract only the new bytes since our last successful read
        let newData = fullData.subdata(in: Int(lastOffset)..<fullData.count)

        // Only process complete lines (ending in newline). If the writer is
        // mid-line, leave the trailing fragment for the next poll.
        guard let lastNewlineIndex = newData.lastIndex(of: 10) else {
            return
        }

        let completeData = newData.prefix(upTo: lastNewlineIndex + 1)
        let decoder = JSONDecoder()

        // Split on newlines and parse each complete line
        let lines = completeData.split(separator: 10, omittingEmptySubsequences: false)
        for line in lines {
            guard !line.isEmpty else { continue }
            do {
                let record = try decoder.decode(KimiWireRecord.self, from: Data(line))
                recordBuffer.append(record)
                onEvent?(record)
            } catch {
                onError?(error)
            }
        }

        // Advance offset past all complete lines (including their trailing newlines)
        lastOffset += UInt64(completeData.count)
    }

    // MARK: - Path Resolution

    /// Resolves the most recent wire.jsonl path. Returns nil if no suitable file exists.
    /// Only considers files modified within the last 10 minutes to avoid picking up
    /// stale session files from previous Kimi runs.
    private func resolveWirePath() -> URL? {
        let baseDir = sessionsBaseDirectory
        let stalenessThreshold = now().addingTimeInterval(-600) // 10 minutes
        let globalScanStartedAt = monitorStartedAt?.addingTimeInterval(-5)

        var candidateDirs: [URL] = []

        if workingDirectory.isEmpty {
            // Global scan: look in ALL md5 subdirectories under ~/.kimi/sessions
            guard let md5Dirs = try? FileManager.default.contentsOfDirectory(atPath: baseDir.path) else { return nil }
            for md5 in md5Dirs {
                candidateDirs.append(baseDir.appendingPathComponent(md5))
            }
        } else {
            // Targeted scan: only the md5 matching our working directory
            let md5 = Self.md5Hash(workingDirectory)
            candidateDirs.append(baseDir.appendingPathComponent(md5))
        }

        var mostRecentPath: URL?
        var mostRecentDate: Date?

        for sessionsDir in candidateDirs {
            guard FileManager.default.fileExists(atPath: sessionsDir.path) else { continue }
            guard let sessionDirs = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir.path) else { continue }

            for sessionID in sessionDirs {
                let wirePath = sessionsDir.appendingPathComponent("\(sessionID)/wire.jsonl")
                guard FileManager.default.fileExists(atPath: wirePath.path) else { continue }

                // Skip empty files — Kimi may create a new session file before writing any records,
                // and switching to an empty file causes us to lose the prior session's state.
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: wirePath.path),
                      let modDate = attrs[.modificationDate] as? Date,
                      attrs[.size] as? UInt64 ?? 0 > 0 else { continue }

                // Skip stale files from previous sessions
                guard modDate > stalenessThreshold else { continue }

                // If cwd is unavailable, global scanning cannot prove that a
                // recent file belongs to this terminal. Only accept files that
                // appeared after this monitor started, with a short launch-race grace.
                if workingDirectory.isEmpty,
                   let globalScanStartedAt,
                   modDate < globalScanStartedAt {
                    continue
                }

                if mostRecentDate == nil || modDate > mostRecentDate! {
                    mostRecentDate = modDate
                    mostRecentPath = wirePath
                }
            }
        }

        return mostRecentPath
    }

    // MARK: - MD5 Hash

    static func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func fileModDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func fileIsRecent(_ url: URL, within seconds: TimeInterval) -> Bool {
        guard let modDate = fileModDate(url) else { return false }
        return now().timeIntervalSince(modDate) < seconds
    }
}
