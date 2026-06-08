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

    @Test
    func snapshotDoesNotTreatDebugBuildBannerAsLongRunningWork() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-debug",
            windowID: "win-debug",
            tabID: "tab-debug",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            You're running a debug build of Ghostty! Performance will be degraded.

            gpt-5.4 medium · ~/tmp/project
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(snapshot.signals.likelyWaitingForInput == true)
        #expect(snapshot.signals.likelyLongRunning == false)
    }

    @Test
    func snapshotDetectsVariousShellPrompts() {
        let prompts = ["$", "%", "#", ">", "λ", "❯", "➜"]
        for prompt in prompts {
            let snapshot = TerminalSnapshot.makePreview(
                terminalID: "term-\(prompt)",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp",
                isFocused: true,
                visibleText: "user@host \(prompt)",
                recentScrollbackLines: ["ready"],
                lastInputPreview: nil
            )
            #expect(snapshot.signals.likelyWaitingForInput == true, "Prompt '\(prompt)' should be detected")
        }
    }

    @Test
    func snapshotFlagsErrorStateForFailureMarkers() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-4",
            windowID: "win-4",
            tabID: "tab-4",
            title: "test",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "Test suite failed with 3 assertions",
            recentScrollbackLines: ["panic"],
            lastInputPreview: nil
        )

        #expect(snapshot.signals.likelyErrorState == true)
    }

    @Test
    func snapshotFlagsDockerBuildAsLongRunning() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-5",
            windowID: "win-5",
            tabID: "tab-5",
            title: "docker",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "docker build -t myapp .",
            recentScrollbackLines: ["Step 1/10"],
            lastInputPreview: nil
        )

        #expect(snapshot.signals.likelyLongRunning == true)
    }

    @Test
    func snapshotPrefersSemanticPromptSignalWhenVisibleTailIsNotPromptLike() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-6",
            windowID: "win-6",
            tabID: "tab-6",
            title: "claude",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "What do you want to do?\n1. Stop and wait for limit to reset\n2. Upgrade your plan\nEnter to confirm · Esc to cancel",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            cursorIsAtPrompt: true
        )

        #expect(snapshot.runtime.cursorIsAtPrompt == true)
        #expect(snapshot.signals.likelyWaitingForInput == true)
    }
}
