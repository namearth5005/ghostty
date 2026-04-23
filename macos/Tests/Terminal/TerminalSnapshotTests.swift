import Testing
@testable import Ghostty

struct TerminalSnapshotTests {
    @Test
    func snapshotTruncatesScrollbackAndFlagsLikelyTUI() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "editor",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "\u{1b}[?1049hvim main.swift",
            recentScrollbackLines: Array(repeating: "line", count: 500),
            lastInputPreview: "vim main.swift"
        )

        #expect(snapshot.signals.likelyTUI == true)
        #expect(snapshot.recentScrollback.split(separator: "\n").count == 250)
        #expect(snapshot.summaryInput.contains("vim main.swift"))
    }
}
