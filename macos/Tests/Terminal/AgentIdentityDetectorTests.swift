import Foundation
import Testing
@testable import Ghostty

struct AgentIdentityDetectorTests {
    private let detector = AgentIdentityDetector()

    @Test
    func foregroundProcessWinsOverMisleadingFallbacks() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Welcome to Kimi Code CLI!
            What do you need help with?
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(detector.identity(for: snapshot) == .codex)
    }

    @Test
    func fallsBackToVisibleTextWhenForegroundProcessIsMissing() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Welcome to Kimi Code CLI!
            Send /help for help information.

            Directory: ~
            Model: Kimi-k2.6
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(detector.identity(for: snapshot) == .kimi)
    }

    @Test
    func claudeTrustPromptFallsBackToVisibleTextWhenForegroundProcessIsMissingAcrossLaunchPaths() {
        let visibleText = """
        Accessing workspace:

        /Users/nambouchara

        Quick safety check: Is this a project you created or one you trust?

        Security guide

         ❯ 1. Yes, I trust this folder
           2. No, exit

         Enter to confirm · Esc to cancel
        """

        let existingTab = TerminalSnapshot.makePreview(
            terminalID: "claude-existing",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTab = TerminalSnapshot.makePreview(
            terminalID: "claude-new-tab",
            windowID: "win-1",
            tabID: "tab-2",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/Users/nambouchara",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managed = TerminalSnapshot.makePreview(
            terminalID: "claude-managed",
            windowID: "win-1",
            tabID: "tab-3",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: false,
            visibleText: visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(detector.identity(for: existingTab) == .claudeCode)
        #expect(detector.identity(for: existingTab) == detector.identity(for: newTab))
        #expect(detector.identity(for: existingTab) == detector.identity(for: managed))
    }

    @Test
    func fallsBackToTitleOnlyWhenProcessIdentityIsUnavailable() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(detector.identity(for: snapshot) == .claudeCode)
    }

    @Test
    func explicitManagedTitlesRemainValidFallbackIdentitySignals() {
        let cases: [(String, AgentIdentity)] = [
            ("OpenAI Codex", .codex),
            ("Kimi Code", .kimi),
            ("Claude Code", .claudeCode),
        ]

        for (title, identity) in cases {
            let snapshot = TerminalSnapshot.makePreview(
                terminalID: "term-\(identity.rawValue)",
                windowID: "win-1",
                tabID: "tab-1",
                title: title,
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )

            #expect(detector.identity(for: snapshot) == identity)
        }
    }

    @Test
    func visibleAgentBannerCanOverrideKnownShellForeground() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Welcome to Claude Code

            What would you like to do?
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "zsh",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(detector.identity(for: snapshot) == .claudeCode)
    }

    @Test
    func managedAgentTitleDoesNotOverrideKnownShellForeground() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-managed-shell",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "nambouchara@Nams-MacBook-Pro ghostty %",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "zsh",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )

        #expect(detector.identity(for: snapshot) == nil)
    }

    @Test
    func pathLikeTitleContainingAgentNameDoesNotCreateIdentityWithoutOtherEvidence() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-claude-path",
                windowID: "win-1",
                tabID: "tab-1",
                title: "nambouchara@Nams-MacBook-Pro:~/claude-hooks",
                cwd: "/tmp/claude-hooks",
                isFocused: true,
                visibleText: "nambouchara@Nams-MacBook-Pro claude-hooks % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-codex-path",
                windowID: "win-1",
                tabID: "tab-2",
                title: "nambouchara@Nams-MacBook-Pro:~/codex-playground",
                cwd: "/tmp/codex-playground",
                isFocused: false,
                visibleText: "nambouchara@Nams-MacBook-Pro codex-playground % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-kimi-path",
                windowID: "win-1",
                tabID: "tab-3",
                title: "nambouchara@Nams-MacBook-Pro:~/kimi-tools",
                cwd: "/tmp/kimi-tools",
                isFocused: false,
                visibleText: "nambouchara@Nams-MacBook-Pro kimi-tools % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            ),
        ]

        for snapshot in snapshots {
            #expect(detector.identity(for: snapshot) == nil)
        }
    }

    @Test
    func proseMentionsOfAgentNamesDoNotCreateIdentityWithoutOtherEvidence() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-claude-prose",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: """
                I compared Claude Code, ChatGPT, and Cursor while planning this task.
                The next step is to document the tradeoffs.
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-codex-prose",
                windowID: "win-1",
                tabID: "tab-2",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: """
                OpenAI Codex is one of several tools mentioned in this migration note.
                Nothing is actively attached to the terminal.
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
        ]

        for snapshot in snapshots {
            #expect(detector.identity(for: snapshot) == nil)
        }
    }

    @Test
    func existingTabNewTabAndManagedLaunchesShareIdentityAcrossAgents() {
        let existingCodex = TerminalSnapshot.makePreview(
            terminalID: "codex-existing",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "• Hey. What do you need help with?\n\n›",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTabCodex = TerminalSnapshot.makePreview(
            terminalID: "codex-new-tab",
            windowID: "win-1",
            tabID: "tab-2",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: existingCodex.visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managedCodex = TerminalSnapshot.makePreview(
            terminalID: "codex-managed",
            windowID: "win-1",
            tabID: "tab-3",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: existingCodex.visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingKimi = TerminalSnapshot.makePreview(
            terminalID: "kimi-existing",
            windowID: "win-1",
            tabID: "tab-4",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Welcome to Kimi Code CLI!\nDirectory: /tmp/project",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTabKimi = TerminalSnapshot.makePreview(
            terminalID: "kimi-new-tab",
            windowID: "win-1",
            tabID: "tab-5",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: existingKimi.visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managedKimi = TerminalSnapshot.makePreview(
            terminalID: "kimi-managed",
            windowID: "win-1",
            tabID: "tab-6",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: existingKimi.visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let existingClaude = TerminalSnapshot.makePreview(
            terminalID: "claude-existing",
            windowID: "win-1",
            tabID: "tab-7",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Welcome to Claude Code\n\nWhat would you like to do?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let newTabClaude = TerminalSnapshot.makePreview(
            terminalID: "claude-new-tab",
            windowID: "win-1",
            tabID: "tab-8",
            title: "nambouchara@Nams-MacBook-Pro:~",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: existingClaude.visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managedClaude = TerminalSnapshot.makePreview(
            terminalID: "claude-managed",
            windowID: "win-1",
            tabID: "tab-9",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: existingClaude.visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(detector.identity(for: existingCodex) == .codex)
        #expect(detector.identity(for: existingCodex) == detector.identity(for: newTabCodex))
        #expect(detector.identity(for: existingCodex) == detector.identity(for: managedCodex))

        #expect(detector.identity(for: existingKimi) == .kimi)
        #expect(detector.identity(for: existingKimi) == detector.identity(for: newTabKimi))
        #expect(detector.identity(for: existingKimi) == detector.identity(for: managedKimi))

        #expect(detector.identity(for: existingClaude) == .claudeCode)
        #expect(detector.identity(for: existingClaude) == detector.identity(for: newTabClaude))
        #expect(detector.identity(for: existingClaude) == detector.identity(for: managedClaude))
    }
}
