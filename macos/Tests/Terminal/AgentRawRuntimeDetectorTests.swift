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
    func kimiInputRegionMapsToBlocked() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-kimi",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            ─ input ─────────────────────────────────────────────────────────

            agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
            context: 5.4% (14.3k/262.1k)
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

    @Test
    func staleChoiceMenuHistoryDoesNotBlockClaudeWorkingState() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "claude-stale-choice",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: """
            Accessing workspace:

            /Users/nambouchara

            Quick safety check: Is this a project you created or one you trust?

             ❯ 1. Yes, I trust this folder
               2. No, exit

             Enter to confirm · Esc to cancel
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "claude-stale-choice",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: """
            Accessing workspace:

            /Users/nambouchara

            Quick safety check: Is this a project you created or one you trust?

             ❯ 1. Yes, I trust this folder
               2. No, exit

             Enter to confirm · Esc to cancel

            Thinking...
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let detection = detector.detect(identity: .claudeCode, current: current, previous: previous)

        #expect(detection.state == .working)
    }

    @Test
    func staleApprovalHistoryDoesNotBlockCodexWorkingState() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "codex-stale-approval",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Permission required

            Allow OpenAI Codex to edit auth.ts? [y/n]
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "codex-stale-approval",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Permission required

            Allow OpenAI Codex to edit auth.ts? [y/n]

            Running repository analysis...
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let detection = detector.detect(identity: .codex, current: current, previous: previous)

        #expect(detection.state == .working)
    }

    @Test
    func staleKimiWelcomeHistoryDoesNotBlockWorkingState() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "kimi-stale-welcome",
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
        let current = TerminalSnapshot.makePreview(
            terminalID: "kimi-stale-welcome",
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

            Thinking...
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let detection = detector.detect(identity: .kimi, current: current, previous: previous)

        #expect(detection.state == .working)
    }

    @Test
    func staleKimiInputHistoryDoesNotBlockWorkingState() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "kimi-stale-input",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            ─ input ─────────────────────────────────────────────────────────

            agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
            context: 5.4% (14.3k/262.1k)
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "kimi-stale-input",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            ─ input ─────────────────────────────────────────────────────────

            agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
            context: 5.4% (14.3k/262.1k)

            Reading repository files...
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let detection = detector.detect(identity: .kimi, current: current, previous: previous)

        #expect(detection.state == .working)
    }

    @Test
    func interactiveSurfaceAppearingAfterWorkingTransitionsToBlockedAcrossCodexAndClaude() {
        let codexPrevious = TerminalSnapshot.makePreview(
            terminalID: "codex-transition",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "• Working (0s • esc to interrupt)",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let codexCurrent = TerminalSnapshot.makePreview(
            terminalID: "codex-transition",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
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

        let claudePrevious = TerminalSnapshot.makePreview(
            terminalID: "claude-transition",
            windowID: "win-2",
            tabID: "tab-2",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: "Thinking...",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let claudeCurrent = TerminalSnapshot.makePreview(
            terminalID: "claude-transition",
            windowID: "win-2",
            tabID: "tab-2",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: """
            Accessing workspace:

            /Users/nambouchara

            Quick safety check: Is this a project you created or one you trust?

             ❯ 1. Yes, I trust this folder
               2. No, exit

             Enter to confirm · Esc to cancel
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let codexDetection = detector.detect(identity: .codex, current: codexCurrent, previous: codexPrevious)
        let claudeDetection = detector.detect(identity: .claudeCode, current: claudeCurrent, previous: claudePrevious)

        #expect(codexDetection.state == .blocked)
        #expect(claudeDetection.state == .blocked)
    }

    @Test
    func managedManualAndNewTabInteractiveSurfaceTransitionKeepsBlockedRawRuntimeParityAcrossCodexAndClaude() throws {
        let codexCases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("codex-transition-existing", "shell", true),
            ("codex-transition-new-tab", "nambouchara@host:~", false),
            ("codex-transition-managed", "OpenAI Codex", false),
        ]
        let claudeCases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("claude-transition-existing", "shell", true),
            ("claude-transition-new-tab", "nambouchara@host:~", false),
            ("claude-transition-managed", "Claude Code", false),
        ]

        var codexStates: [AgentRuntimeState] = []
        var claudeStates: [AgentRuntimeState] = []

        for entry in codexCases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: "• Working (0s • esc to interrupt)",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
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

            codexStates.append(detector.detect(identity: .codex, current: current, previous: previous).state)
        }

        for entry in claudeCases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-2",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: "Thinking...",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-2",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: """
                Accessing workspace:

                /Users/nambouchara

                Quick safety check: Is this a project you created or one you trust?

                 ❯ 1. Yes, I trust this folder
                   2. No, exit

                 Enter to confirm · Esc to cancel
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )

            claudeStates.append(detector.detect(identity: .claudeCode, current: current, previous: previous).state)
        }

        let firstCodex = try #require(codexStates.first)
        let firstClaude = try #require(claudeStates.first)
        #expect(codexStates.dropFirst().allSatisfy { $0 == firstCodex })
        #expect(claudeStates.dropFirst().allSatisfy { $0 == firstClaude })
        #expect(firstCodex == .blocked)
        #expect(firstClaude == .blocked)
    }

    @Test
    func resolvedInteractiveSurfaceTransitionsBackToIdleAcrossCodexAndClaude() {
        let codexPrevious = TerminalSnapshot.makePreview(
            terminalID: "codex-idle-transition",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
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
        let codexCurrent = TerminalSnapshot.makePreview(
            terminalID: "codex-idle-transition",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "nambouchara@host ghostty % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )

        let claudePrevious = TerminalSnapshot.makePreview(
            terminalID: "claude-idle-transition",
            windowID: "win-2",
            tabID: "tab-2",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: """
            Accessing workspace:

            /Users/nambouchara

            Quick safety check: Is this a project you created or one you trust?

             ❯ 1. Yes, I trust this folder
               2. No, exit

             Enter to confirm · Esc to cancel
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let claudeCurrent = TerminalSnapshot.makePreview(
            terminalID: "claude-idle-transition",
            windowID: "win-2",
            tabID: "tab-2",
            title: "Claude Code",
            cwd: "/Users/nambouchara",
            isFocused: true,
            visibleText: "nambouchara@host ghostty % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )

        let codexDetection = detector.detect(identity: .codex, current: codexCurrent, previous: codexPrevious)
        let claudeDetection = detector.detect(identity: .claudeCode, current: claudeCurrent, previous: claudePrevious)

        #expect(codexDetection.state == .idle)
        #expect(claudeDetection.state == .idle)
    }

    @Test
    func managedManualAndNewTabResolvedInteractiveSurfaceTransitionKeepsIdleRawRuntimeParityAcrossCodexAndClaude() throws {
        let codexCases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("codex-idle-existing", "shell", true),
            ("codex-idle-new-tab", "nambouchara@host:~", false),
            ("codex-idle-managed", "OpenAI Codex", false),
        ]
        let claudeCases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("claude-idle-existing", "shell", true),
            ("claude-idle-new-tab", "nambouchara@host:~", false),
            ("claude-idle-managed", "Claude Code", false),
        ]

        var codexStates: [AgentRuntimeState] = []
        var claudeStates: [AgentRuntimeState] = []

        for entry in codexCases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
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
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: "nambouchara@host ghostty % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            )

            codexStates.append(detector.detect(identity: .codex, current: current, previous: previous).state)
        }

        for entry in claudeCases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-2",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: """
                Accessing workspace:

                /Users/nambouchara

                Quick safety check: Is this a project you created or one you trust?

                 ❯ 1. Yes, I trust this folder
                   2. No, exit

                 Enter to confirm · Esc to cancel
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "win-2",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: "nambouchara@host ghostty % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            )

            claudeStates.append(detector.detect(identity: .claudeCode, current: current, previous: previous).state)
        }

        let firstCodex = try #require(codexStates.first)
        let firstClaude = try #require(claudeStates.first)
        #expect(codexStates.dropFirst().allSatisfy { $0 == firstCodex })
        #expect(claudeStates.dropFirst().allSatisfy { $0 == firstClaude })
        #expect(firstCodex == .idle)
        #expect(firstClaude == .idle)
    }
}
