import Foundation

/// Monitors Codex's session JSONL files, emitting structured wire records.
///
/// Codex writes events to date-sharded files:
///   ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<UUID>.jsonl
///
/// A new session file is created for each turn, so the monitor re-resolves
/// the path on every poll and switches when a newer non-empty file appears.
final class CodexSessionMonitor {
    let workingDirectory: String?
    let sessionsBase: URL

    private var timer: Timer?
    private var lastOffset: UInt64 = 0
    private var resolvedSessionPath: URL?
    private var recordBuffer: [CodexWireRecord] = []

    var onEvent: ((CodexWireRecord) -> Void)?
    var onError: ((Error) -> Void)?

    /// If `workingDirectory` is provided, the monitor prefers sessions whose
    /// `session_meta.cwd` matches. If nil, it does a global scan.
    /// `sessionsBase` defaults to `~/.codex/sessions` but can be overridden for testing.
    init(workingDirectory: String?, sessionsBase: URL? = nil) {
        self.workingDirectory = workingDirectory
        self.sessionsBase = sessionsBase ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    func start() {
        stop()
        resolvedSessionPath = nil
        lastOffset = 0
        recordBuffer.removeAll()

        resolveSessionPath()

        let t = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer = t
        if resolvedSessionPath != nil {
            poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func records() -> [CodexWireRecord] {
        if recordBuffer.count > 100 {
            recordBuffer.removeFirst(recordBuffer.count - 100)
        }
        return recordBuffer
    }

    // MARK: - Polling

    func poll() {
        let previousPath = resolvedSessionPath
        resolveSessionPath()
        if let newPath = resolvedSessionPath, newPath != previousPath {
            DebugLogger.log("[CodexMonitor] switched session from '\(previousPath?.lastPathComponent ?? "nil")' to '\(newPath.lastPathComponent)'")
            lastOffset = 0
        }
        guard let path = resolvedSessionPath else { return }

        guard let fullData = FileManager.default.contents(atPath: path.path), !fullData.isEmpty else {
            resolvedSessionPath = nil
            lastOffset = 0
            return
        }

        if fullData.count < lastOffset {
            lastOffset = 0
        }
        guard fullData.count > lastOffset else { return }

        let newData = fullData.subdata(in: Int(lastOffset)..<fullData.count)
        guard let lastNewlineIndex = newData.lastIndex(of: 10) else { return }

        let completeData = newData.prefix(upTo: lastNewlineIndex + 1)
        let decoder = JSONDecoder()
        let lines = completeData.split(separator: 10, omittingEmptySubsequences: false)
        for line in lines {
            guard !line.isEmpty else { continue }
            do {
                let record = try decoder.decode(CodexWireRecord.self, from: Data(line))
                recordBuffer.append(record)
                onEvent?(record)
            } catch {
                onError?(error)
            }
        }

        lastOffset += UInt64(completeData.count)
    }

    // MARK: - Session Discovery

    private func resolveSessionPath() {
        guard FileManager.default.fileExists(atPath: sessionsBase.path) else { return }

        // Recursively find all .jsonl files under sessions/
        var candidateFiles: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: sessionsBase,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                      let modDate = attrs[.modificationDate] as? Date,
                      attrs[.size] as? UInt64 ?? 0 > 0 else { continue }
                candidateFiles.append(fileURL)
            }
        }

        // If workingDirectory is provided, try to find a session whose cwd matches
        if let cwd = workingDirectory, !cwd.isEmpty {
            let matching = candidateFiles.filter { url in
                guard let cwdFromMeta = extractCwd(from: url) else { return false }
                return cwdFromMeta == cwd || cwdFromMeta.hasPrefix(cwd) || cwd.hasPrefix(cwdFromMeta)
            }
            if let mostRecent = matching.max(by: { fileModDate($0) ?? .distantPast < fileModDate($1) ?? .distantPast }) {
                resolvedSessionPath = mostRecent
                return
            }
        }

        // Fallback: pick the most recently modified session file globally
        resolvedSessionPath = candidateFiles.max {
            (fileModDate($0) ?? .distantPast) < (fileModDate($1) ?? .distantPast)
        }
    }

    /// Reads the first line (session_meta) of a session file to extract cwd.
    private func extractCwd(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }
        guard let data = try? handle.read(upToCount: 4096) else { return nil }
        guard let firstNewline = data.firstIndex(of: 10) else { return nil }
        let lineData = data.prefix(upTo: firstNewline)
        guard let record = try? JSONDecoder().decode(CodexWireRecord.self, from: Data(lineData)),
              record.type == "session_meta" else { return nil }
        return record.payload.cwd
    }

    private func fileModDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}
