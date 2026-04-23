import Foundation

struct TerminalSnapshot: Codable, Equatable, Sendable {
    struct Signals: Codable, Equatable, Sendable {
        var likelyWaitingForInput: Bool
        var likelyLongRunning: Bool
        var likelyErrorState: Bool
        var likelyTUI: Bool
    }

    let terminalID: String
    let windowID: String
    let tabID: String
    let title: String
    let cwd: String?
    let isFocused: Bool
    let captureMode: String
    let visibleText: String
    let recentScrollback: String
    let lastInputPreview: String?
    let signals: Signals

    var summaryInput: String {
        [title, cwd ?? "", lastInputPreview ?? "", visibleText, recentScrollback]
            .joined(separator: "\n")
    }

    static func makePreview(
        terminalID: String,
        windowID: String,
        tabID: String,
        title: String,
        cwd: String?,
        isFocused: Bool,
        visibleText: String,
        recentScrollbackLines: [String],
        lastInputPreview: String?
    ) -> TerminalSnapshot {
        let capped = Array(recentScrollbackLines.suffix(250)).joined(separator: "\n")
        let normalizedVisible = visibleText.replacingOccurrences(of: "\r\n", with: "\n")
        return TerminalSnapshot(
            terminalID: terminalID,
            windowID: windowID,
            tabID: tabID,
            title: title,
            cwd: cwd,
            isFocused: isFocused,
            captureMode: "shell",
            visibleText: normalizedVisible,
            recentScrollback: capped,
            lastInputPreview: lastInputPreview,
            signals: .init(
                likelyWaitingForInput: normalizedVisible.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("$"),
                likelyLongRunning: false,
                likelyErrorState: normalizedVisible.localizedCaseInsensitiveContains("error"),
                likelyTUI: normalizedVisible.contains("\u{1b}[?1049h") || (lastInputPreview?.contains("vim") == true)
            )
        )
    }
}
