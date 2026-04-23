import Testing
@testable import Ghostty

struct TerminalSnapshotTests {
    @Test
    func snapshotNormalizesVisibleTextAndStripsControlSequences() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "editor",
            cwd: nil,
            isFocused: false,
            visibleText: "hello\rworld\u{1b}[31m!\u{1b}[0m\u{07}",
            recentScrollbackLines: ["line"],
            lastInputPreview: nil
        )

        #expect(snapshot.visibleText == "hello\nworld!")
        #expect(snapshot.summaryInput == "editor\nhello\nworld!\nline")
    }

    @Test
    func snapshotTruncatesScrollbackAndFlagsLikelyTUIForCommonCommands() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "editor",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "tmux new-session",
            recentScrollbackLines: Array(repeating: "line", count: 500),
            lastInputPreview: "tmux new-session"
        )

        #expect(snapshot.signals.likelyTUI == true)
        #expect(snapshot.recentScrollback.split(separator: "\n").count == 250)
        #expect(snapshot.summaryInput.contains("tmux new-session"))
    }

    @Test
    func snapshotDoesNotFlagPlainShellPromptAsTUI() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-2",
            windowID: "win-2",
            tabID: "tab-2",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "user@host$",
            recentScrollbackLines: ["ready"],
            lastInputPreview: "echo hello"
        )

        #expect(snapshot.signals.likelyTUI == false)
    }

    @Test
    func snapshotFlagsLikelyLongRunningForCommonBuildCommands() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-3",
            windowID: "win-3",
            tabID: "tab-3",
            title: "build",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "Building...",
            recentScrollbackLines: ["running"],
            lastInputPreview: "make test"
        )

        #expect(snapshot.signals.likelyLongRunning == true)
    }
}
