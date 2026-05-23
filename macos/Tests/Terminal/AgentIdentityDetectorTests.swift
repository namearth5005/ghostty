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
