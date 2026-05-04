import Foundation
import Testing
@testable import Ghostty

struct TerminalUnderstandingTests {
    @Test
    func engineClassifiesCommandNotFoundAsFailedWithRankedSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "hfind . -print\nzsh: command not found: hfind\nuser@host %",
            recentScrollbackLines: ["hfind . -print", "zsh: command not found: hfind"],
            lastInputPreview: "hfind . -print"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.state == .failed)
        #expect(understanding.lastMeaningfulEvent.contains("command not found"))
        #expect(understanding.suggestedNextActions.count == 3)
        #expect(understanding.suggestedNextActions.map(\.title) == [
            "Run the likely intended find command",
            "Try fd if a faster file search was intended",
            "Confirm whether hfind was intentional",
        ])
        #expect(understanding.suggestedNextActions.map(\.isRecommended) == [true, false, false])
        #expect(understanding.suggestedNextActions.map(\.command) == ["find . -print", "fd .", nil])
        #expect(understanding.recommendedAction?.command == "find . -print")
        #expect(understanding.suggestedNextActions.first?.command == understanding.recommendedAction?.command)
    }

    @Test
    func engineClassifiesBuildOutputAsRunning() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-2",
            windowID: "win-1",
            tabID: "tab-2",
            title: "build",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "Compiling module A...\nCompiling module B...",
            recentScrollbackLines: ["Compiling module A...", "Compiling module B..."],
            lastInputPreview: "swift build"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.state == .running)
        #expect(understanding.shortExplanation.contains("build"))
    }

    @Test
    func engineIgnoresStaleOutcomeFromPreviousCommand() {
        let engine = TerminalUnderstandingEngine()
        let previous = TerminalSnapshot.makePreview(
            terminalID: "term-3",
            windowID: "win-1",
            tabID: "tab-3",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "npm test\nuser@host %",
            recentScrollbackLines: ["npm test", "user@host %"],
            lastInputPreview: "npm test"
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "term-3",
            windowID: "win-1",
            tabID: "tab-3",
            title: "build",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Compiling module A...\nCompiling module B...",
            recentScrollbackLines: ["Compiling module A...", "Compiling module B..."],
            lastInputPreview: "swift build"
        )
        let staleOutcome = TerminalOutcomeReport(
            terminalID: "term-3",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: .now,
            summary: "Previous tests passed cleanly."
        )

        let understanding = engine.understand(
            current: current,
            previous: previous,
            lastOutcome: staleOutcome
        )

        #expect(understanding.state == .running)
        #expect(understanding.lastMeaningfulEvent == "Compiling module B...")
        #expect(!understanding.shortExplanation.contains("Previous tests passed cleanly."))
    }

    @Test
    func engineUsesFreshSuccessOutcomeSummaryInExplanation() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-4",
            windowID: "win-1",
            tabID: "tab-4",
            title: "test",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "npm test\nuser@host %",
            recentScrollbackLines: ["npm test", "user@host %"],
            lastInputPreview: "npm test"
        )
        let outcome = TerminalOutcomeReport(
            terminalID: "term-4",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: .now,
            summary: "Tests finished successfully."
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: outcome
        )

        #expect(understanding.state == .succeeded)
        #expect(understanding.lastMeaningfulEvent == "Tests finished successfully.")
        #expect(understanding.shortExplanation.contains("Tests finished successfully."))
    }

    @Test
    func engineIgnoresStaleOutcomeWhenSameCommandIsRerun() {
        let engine = TerminalUnderstandingEngine()
        let previous = TerminalSnapshot.makePreview(
            terminalID: "term-5",
            windowID: "win-1",
            tabID: "tab-5",
            title: "test",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Tests: 42 passed\nuser@host %",
            recentScrollbackLines: ["npm test", "Tests: 42 passed", "user@host %"],
            lastInputPreview: "npm test"
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "term-5",
            windowID: "win-1",
            tabID: "tab-5",
            title: "test",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Running tests...\nSuite auth.spec.ts",
            recentScrollbackLines: ["npm test", "Running tests...", "Suite auth.spec.ts"],
            lastInputPreview: "npm test"
        )
        let staleOutcome = TerminalOutcomeReport(
            terminalID: "term-5",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: .now,
            summary: "Previous test run passed."
        )

        let understanding = engine.understand(
            current: current,
            previous: previous,
            lastOutcome: staleOutcome
        )

        #expect(understanding.state == .running)
        #expect(understanding.lastMeaningfulEvent == "Suite auth.spec.ts")
        #expect(!understanding.shortExplanation.contains("Previous test run passed."))
    }

    @Test
    func adaptiveOverviewMentionsOnlyChangedTerminal() {
        let engine = TerminalUnderstandingEngine()

        let previous = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .running,
                shortExplanation: "API server is booting.",
                lastMeaningfulEvent: "Server startup began.",
                importantDetails: ["Listening on port 3000 soon."],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .running,
                shortExplanation: "Tests are still running.",
                lastMeaningfulEvent: "Vitest started.",
                importantDetails: ["42 tests discovered."],
                suggestedNextActions: []
            ),
        ]

        let current = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .succeeded,
                shortExplanation: "API server is ready.",
                lastMeaningfulEvent: "Server reported ready.",
                importantDetails: ["Listening on http://localhost:3000."],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .running,
                shortExplanation: "Tests are still running.",
                lastMeaningfulEvent: "Vitest started.",
                importantDetails: ["42 tests discovered."],
                suggestedNextActions: []
            ),
        ]

        let overview = engine.makeOverview(current: current, previous: previous)

        #expect(overview.summary == "term-1: API server is ready.")
        #expect(!overview.summary.contains("term-2"))
        #expect(overview.changedTerminalIDs == ["term-1"])
    }

    @Test
    func adaptiveOverviewCountsRemovedTerminalAsChange() {
        let engine = TerminalUnderstandingEngine()

        let previous = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .running,
                shortExplanation: "API server is still running.",
                lastMeaningfulEvent: "Server is healthy.",
                importantDetails: ["Listening on http://localhost:3000."],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .running,
                shortExplanation: "Tests are still running.",
                lastMeaningfulEvent: "Vitest started.",
                importantDetails: ["42 tests discovered."],
                suggestedNextActions: []
            ),
        ]
        let current = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .running,
                shortExplanation: "API server is still running.",
                lastMeaningfulEvent: "Server is healthy.",
                importantDetails: ["Listening on http://localhost:3000."],
                suggestedNextActions: []
            ),
        ]

        let overview = engine.makeOverview(current: current, previous: previous)

        #expect(overview.summary == "term-2 is no longer available.")
        #expect(overview.changedTerminalIDs == ["term-2"])
        #expect(overview.primaryTerminalID == "term-2")
    }

    @Test
    func engineClassifiesClaudeMenuAsWaitingChoice() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-6",
            windowID: "win-1",
            tabID: "tab-6",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            What do you want to do?

            ❯ 1. Stop and wait for limit to reset
              2. Upgrade your plan

            Enter to confirm · Esc to cancel
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            usingAlternateScreen: true
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .claudeCode)
        #expect(understanding.agentInteractionState == .waitingChoice)
        #expect(understanding.state == .waiting)
        #expect(understanding.supportLevel == .firstClass)
        #expect(understanding.evidence.contains(where: { $0.source == .screenHeuristic }))
    }

    @Test
    func engineClassifiesCodexPromptAsWaitingText() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-7",
            windowID: "win-1",
            tabID: "tab-7",
            title: "speed2",
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

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.agentIdentity == .codex)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.state == .waiting)
        #expect(understanding.shortExplanation.contains("waiting"))
    }
}
