import Foundation
import Testing
@testable import Ghostty

struct AgentRawRuntimeDetectorTests {
    private let detector = AgentRawRuntimeDetector()

    @Test
    func codexQuestionPromptMapsToBlocked() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-codex",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            • Hey. What do you need help with?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let detection = detector.detect(identity: .codex, current: snapshot)

        #expect(detection.state == .blocked)
    }

    @Test
    func codexWorkingHeaderMapsToWorking() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-codex",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "• Working (0s • esc to interrupt)",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let detection = detector.detect(identity: .codex, current: snapshot)

        #expect(detection.state == .working)
    }

    @Test
    func quietPromptWithoutActiveRequestMapsToIdle() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-codex",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "nambouchara@host ghostty % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )

        let detection = detector.detect(identity: .codex, current: snapshot)

        #expect(detection.state == .idle)
    }

    @Test
    func kimiWelcomeScreenMapsToBlocked() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-kimi",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Welcome to Kimi Code CLI!
            Send /help for help information.

            Directory: /tmp/project
            Model: Kimi-k2.6
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let detection = detector.detect(identity: .kimi, current: snapshot)

        #expect(detection.state == .blocked)
    }

    @Test
    func managedManualAndNewTabLaunchesShareBlockedRawStateAcrossAgents() {
        let codexVisibleText = """
        • Hey. What do you need help with?

        ›
        """
        let kimiVisibleText = """
        Welcome to Kimi Code CLI!
        Send /help for help information.

        Directory: /tmp/project
        Model: Kimi-k2.6
        """
        let claudeVisibleText = """
        Accessing workspace:

        /Users/nambouchara

        Quick safety check: Is this a project you created or one you trust?

         ❯ 1. Yes, I trust this folder
           2. No, exit

         Enter to confirm · Esc to cancel
        """

        let cases: [(AgentIdentity, [TerminalSnapshot])] = [
            (
                .codex,
                [
                    TerminalSnapshot.makePreview(
                        terminalID: "codex-existing",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "shell",
                        cwd: "/tmp/project",
                        isFocused: true,
                        visibleText: codexVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "codex",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                    TerminalSnapshot.makePreview(
                        terminalID: "codex-new-tab",
                        windowID: "win-1",
                        tabID: "tab-2",
                        title: "nambouchara@host:~",
                        cwd: "/tmp/project",
                        isFocused: false,
                        visibleText: codexVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "codex",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                    TerminalSnapshot.makePreview(
                        terminalID: "codex-managed",
                        windowID: "win-1",
                        tabID: "tab-3",
                        title: "OpenAI Codex",
                        cwd: "/tmp/project",
                        isFocused: false,
                        visibleText: codexVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "codex",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                ]
            ),
            (
                .kimi,
                [
                    TerminalSnapshot.makePreview(
                        terminalID: "kimi-existing",
                        windowID: "win-1",
                        tabID: "tab-4",
                        title: "shell",
                        cwd: "/tmp/project",
                        isFocused: true,
                        visibleText: kimiVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "kimi",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                    TerminalSnapshot.makePreview(
                        terminalID: "kimi-new-tab",
                        windowID: "win-1",
                        tabID: "tab-5",
                        title: "nambouchara@host:~",
                        cwd: "/tmp/project",
                        isFocused: false,
                        visibleText: kimiVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "kimi",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                    TerminalSnapshot.makePreview(
                        terminalID: "kimi-managed",
                        windowID: "win-1",
                        tabID: "tab-6",
                        title: "Kimi Code",
                        cwd: "/tmp/project",
                        isFocused: false,
                        visibleText: kimiVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "kimi",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                ]
            ),
            (
                .claudeCode,
                [
                    TerminalSnapshot.makePreview(
                        terminalID: "claude-existing",
                        windowID: "win-1",
                        tabID: "tab-7",
                        title: "shell",
                        cwd: "/Users/nambouchara",
                        isFocused: true,
                        visibleText: claudeVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "claude",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                    TerminalSnapshot.makePreview(
                        terminalID: "claude-new-tab",
                        windowID: "win-1",
                        tabID: "tab-8",
                        title: "nambouchara@host:~",
                        cwd: "/Users/nambouchara",
                        isFocused: false,
                        visibleText: claudeVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "claude",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                    TerminalSnapshot.makePreview(
                        terminalID: "claude-managed",
                        windowID: "win-1",
                        tabID: "tab-9",
                        title: "Claude Code",
                        cwd: "/Users/nambouchara",
                        isFocused: false,
                        visibleText: claudeVisibleText,
                        recentScrollbackLines: [],
                        lastInputPreview: nil,
                        foregroundProcessName: "claude",
                        cursorIsAtPrompt: true,
                        usingAlternateScreen: true
                    ),
                ]
            ),
        ]

        for (identity, snapshots) in cases {
            let states = snapshots.map { detector.detect(identity: identity, current: $0).state }
            #expect(states == [.blocked, .blocked, .blocked])
        }
    }
}
