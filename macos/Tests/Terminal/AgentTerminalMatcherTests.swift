import Foundation
import Testing
@testable import Ghostty

struct AgentTerminalMatcherTests {
    @Test
    func kimiOutputMentioningClaudeDirectoryDoesNotMatchClaudeMonitor() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-kimi",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/Users/nambouchara/speed2",
            isFocused: true,
            visibleText: """
            I'm now in the mend directory. Here's what's inside:
            .claude/
            docs/
            hooks/
            README.md

            What would you like me to do here?

            agent (Kimi-k2.6 *) ~/speed2
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(AgentTerminalMatcher.matches(snapshot, identity: .kimi))
        #expect(!AgentTerminalMatcher.matches(snapshot, identity: .claudeCode))
    }

    @Test
    func visibleClaudeCodeBannerStillMatchesClaudeMonitor() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-claude",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/Users/nambouchara/speed2",
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

        #expect(AgentTerminalMatcher.matches(snapshot, identity: .claudeCode))
    }
}
