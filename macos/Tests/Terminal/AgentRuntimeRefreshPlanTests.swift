import Foundation
import Testing
@testable import Ghostty

struct AgentRuntimeRefreshPlanTests {
    @Test
    func managedAndManualLaunchesProduceTheSameMonitorTargetAcrossAgents() {
        let manualCodex = TerminalSnapshot.makePreview(
            terminalID: "codex-manual",
            windowID: "w1",
            tabID: "t1",
            title: "shell",
            cwd: "/tmp/codex",
            isFocused: true,
            visibleText: "OpenAI Codex\nWhat should I work on next?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 101,
            foregroundProcessName: "codex"
        )
        let managedCodex = TerminalSnapshot.makePreview(
            terminalID: "codex-managed",
            windowID: "w1",
            tabID: "t2",
            title: "OpenAI Codex",
            cwd: "/tmp/codex",
            isFocused: false,
            visibleText: "OpenAI Codex\nWhat should I work on next?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 202,
            foregroundProcessName: "codex"
        )

        let manualKimi = TerminalSnapshot.makePreview(
            terminalID: "kimi-manual",
            windowID: "w1",
            tabID: "t3",
            title: "shell",
            cwd: "/tmp/kimi",
            isFocused: false,
            visibleText: "Welcome to Kimi Code CLI\nDirectory: /tmp/kimi",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 303,
            foregroundProcessName: "kimi"
        )
        let managedKimi = TerminalSnapshot.makePreview(
            terminalID: "kimi-managed",
            windowID: "w1",
            tabID: "t4",
            title: "Kimi Code",
            cwd: "/tmp/kimi",
            isFocused: false,
            visibleText: "Welcome to Kimi Code CLI\nDirectory: /tmp/kimi",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 404,
            foregroundProcessName: "kimi"
        )

        let manualClaude = TerminalSnapshot.makePreview(
            terminalID: "claude-manual",
            windowID: "w1",
            tabID: "t5",
            title: "shell",
            cwd: "/tmp/claude",
            isFocused: false,
            visibleText: "Welcome to Claude Code\nWhat would you like to do?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 505,
            foregroundProcessName: "claude"
        )
        let managedClaude = TerminalSnapshot.makePreview(
            terminalID: "claude-managed",
            windowID: "w1",
            tabID: "t6",
            title: "Claude Code",
            cwd: "/tmp/claude",
            isFocused: false,
            visibleText: "Welcome to Claude Code\nWhat would you like to do?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 606,
            foregroundProcessName: "claude"
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: [
                manualCodex,
                managedCodex,
                manualKimi,
                managedKimi,
                manualClaude,
                managedClaude,
            ]
        )

        #expect(plan.entry(for: manualCodex.terminalID)?.monitorTarget == .codex(workingDirectory: "/tmp/codex"))
        #expect(plan.entry(for: managedCodex.terminalID)?.monitorTarget == .codex(workingDirectory: "/tmp/codex"))
        #expect(plan.entry(for: manualKimi.terminalID)?.monitorTarget == .kimi(workingDirectory: "/tmp/kimi"))
        #expect(plan.entry(for: managedKimi.terminalID)?.monitorTarget == .kimi(workingDirectory: "/tmp/kimi"))
        #expect(plan.entry(for: manualClaude.terminalID)?.monitorTarget == .claude(pid: 505, workingDirectory: "/tmp/claude"))
        #expect(plan.entry(for: managedClaude.terminalID)?.monitorTarget == .claude(pid: 606, workingDirectory: "/tmp/claude"))
    }

    @Test
    func planUsesProcessIdentityBeforeMisleadingVisibleTextForMonitorTargets() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-kimi",
            windowID: "w1",
            tabID: "t1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            I'm in the repo now.
            .claude/
            README.md

            What would you like me to do here?
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 777,
            foregroundProcessName: "kimi"
        )

        let plan = AgentRuntimeRefreshPlan(snapshots: [snapshot])

        #expect(plan.entry(for: snapshot.terminalID)?.monitorTarget == .kimi(workingDirectory: "/tmp/project"))
    }

    @Test
    func similarlyNamedProcessesDoNotCreateMonitorTargetsWithoutSeparateScreenEvidence() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-claude-helper",
                windowID: "w1",
                tabID: "t1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "helper output",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude-hooks",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-codex-helper",
                windowID: "w1",
                tabID: "t2",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "helper output",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex-playground",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-kimi-helper",
                windowID: "w1",
                tabID: "t3",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "helper output",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "kimi-tools",
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
        ]

        let plan = AgentRuntimeRefreshPlan(snapshots: snapshots)

        for snapshot in snapshots {
            #expect(plan.entry(for: snapshot.terminalID)?.detection == nil)
            #expect(plan.entry(for: snapshot.terminalID)?.monitorTarget == nil)
        }
    }

    @Test
    func planCarriesForwardCanonicalRuntimeDetectionWhenWireStateExists() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-codex",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "OpenAI Codex",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 888,
            foregroundProcessName: "codex"
        )
        let wireRecord = try! JSONDecoder().decode(
            CodexWireRecord.self,
            from: Data("""
            {
              "timestamp": "2026-05-23T00:00:00Z",
              "type": "event_msg",
              "payload": {
                "type": "task_complete",
                "turn_id": "turn-1",
                "completed_at": 1714828810,
                "duration_ms": 9000
              }
            }
            """.utf8)
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: [snapshot],
            codexWireRecordsByTerminalID: [snapshot.terminalID: [wireRecord]]
        )

        let detection = try! #require(plan.entry(for: snapshot.terminalID)?.detection)
        #expect(detection.identity == .codex)
        #expect(detection.state == .blocked)
    }

    @Test
    func managedManualAndNewTabCodexWireStateProduceMatchingMonitorTargetsWhenSurfaceIsGeneric() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-existing",
                windowID: "w1",
                tabID: "t1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-new-tab",
                windowID: "w1",
                tabID: "t2",
                title: "nambouchara@host:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-managed",
                windowID: "w1",
                tabID: "t3",
                title: "Codex",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
        ]
        let wireRecord = try! JSONDecoder().decode(
            CodexWireRecord.self,
            from: Data("""
            {
              "timestamp": "2026-05-23T00:00:00Z",
              "type": "event_msg",
              "payload": {
                "type": "task_complete",
                "turn_id": "turn-1",
                "completed_at": 1714828810,
                "duration_ms": 9000
              }
            }
            """.utf8)
        )
        let codexWireRecordsByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.terminalID, [wireRecord]) }
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: snapshots,
            codexWireRecordsByTerminalID: codexWireRecordsByTerminalID
        )

        let entries = snapshots.map { try! #require(plan.entry(for: $0.terminalID)) }
        #expect(entries.dropFirst().allSatisfy { $0.detection == entries.first?.detection })
        #expect(entries.dropFirst().allSatisfy { $0.monitorTarget == entries.first?.monitorTarget })
        #expect(entries.first?.detection?.identity == .codex)
        #expect(entries.first?.detection?.state == .blocked)
        #expect(entries.first?.monitorTarget == .codex(workingDirectory: "/tmp/project"))
    }

    @Test
    func managedManualAndNewTabClaudeIdleStateProduceMatchingMonitorTargetsWhenSurfaceIsGeneric() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-existing",
                windowID: "w1",
                tabID: "t1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-new-tab",
                windowID: "w1",
                tabID: "t2",
                title: "nambouchara@host:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-managed",
                windowID: "w1",
                tabID: "t3",
                title: "Claude",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
        ]
        let claudeWireRecordsByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map {
                (
                    $0.terminalID,
                    [
                        ClaudeSessionState(
                            pid: 12345,
                            sessionId: "session-\($0.terminalID)",
                            cwd: "/tmp/project",
                            status: "idle",
                            updatedAt: 1714828801000,
                            startedAt: 1714828800000,
                            version: "2.1.128",
                            kind: "interactive"
                        ),
                    ]
                )
            }
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: snapshots,
            claudeWireRecordsByTerminalID: claudeWireRecordsByTerminalID
        )

        let entries = snapshots.map { try! #require(plan.entry(for: $0.terminalID)) }
        #expect(entries.dropFirst().allSatisfy { $0.detection == entries.first?.detection })
        #expect(entries.dropFirst().allSatisfy { $0.monitorTarget == entries.first?.monitorTarget })
        #expect(entries.first?.detection?.identity == .claudeCode)
        #expect(entries.first?.detection?.state == .blocked)
        #expect(entries.first?.monitorTarget == .claudeWorkingDirectory("/tmp/project"))
    }

    @Test
    func managedTitleWithoutAgentProcessOrOutputDoesNotCreateMonitorTarget() {
        let codex = TerminalSnapshot.makePreview(
            terminalID: "codex-shell",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: "/tmp/codex",
            isFocused: true,
            visibleText: "nambouchara@host codex % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "zsh",
            cursorIsAtPrompt: true
        )
        let kimi = TerminalSnapshot.makePreview(
            terminalID: "kimi-shell",
            windowID: "w1",
            tabID: "t2",
            title: "Kimi Code",
            cwd: "/tmp/kimi",
            isFocused: false,
            visibleText: "nambouchara@host kimi % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "zsh",
            cursorIsAtPrompt: true
        )
        let claude = TerminalSnapshot.makePreview(
            terminalID: "claude-shell",
            windowID: "w1",
            tabID: "t3",
            title: "Claude Code",
            cwd: "/tmp/claude",
            isFocused: false,
            visibleText: "nambouchara@host claude % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "zsh",
            cursorIsAtPrompt: true
        )

        let plan = AgentRuntimeRefreshPlan(snapshots: [codex, kimi, claude])

        #expect(plan.entry(for: codex.terminalID)?.monitorTarget == nil)
        #expect(plan.entry(for: kimi.terminalID)?.monitorTarget == nil)
        #expect(plan.entry(for: claude.terminalID)?.monitorTarget == nil)
    }

    @Test
    func pathLikeTitleContainingAgentNameDoesNotCreateMonitorTargetWhenProcessIsMissing() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "claude-path-shell",
                windowID: "w1",
                tabID: "t1",
                title: "nambouchara@host:~/claude-hooks",
                cwd: "/tmp/claude-hooks",
                isFocused: true,
                visibleText: "nambouchara@host claude-hooks % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-path-shell",
                windowID: "w1",
                tabID: "t2",
                title: "nambouchara@host:~/codex-playground",
                cwd: "/tmp/codex-playground",
                isFocused: false,
                visibleText: "nambouchara@host codex-playground % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "kimi-path-shell",
                windowID: "w1",
                tabID: "t3",
                title: "nambouchara@host:~/kimi-tools",
                cwd: "/tmp/kimi-tools",
                isFocused: false,
                visibleText: "nambouchara@host kimi-tools % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            ),
        ]

        let plan = AgentRuntimeRefreshPlan(snapshots: snapshots)

        for snapshot in snapshots {
            #expect(plan.entry(for: snapshot.terminalID)?.monitorTarget == nil)
            #expect(plan.entry(for: snapshot.terminalID)?.detection == nil)
        }
    }

    @Test
    func claudeTrustPromptWithoutProcessStillProducesMatchingMonitorTargetsAcrossLaunchPaths() {
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
            windowID: "w1",
            tabID: "t1",
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
            windowID: "w1",
            tabID: "t2",
            title: "nambouchara@host:~",
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
            windowID: "w1",
            tabID: "t3",
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

        let plan = AgentRuntimeRefreshPlan(snapshots: [existingTab, newTab, managed])

        #expect(plan.entry(for: existingTab.terminalID)?.monitorTarget == .claudeWorkingDirectory("/Users/nambouchara"))
        #expect(plan.entry(for: existingTab.terminalID)?.monitorTarget == plan.entry(for: newTab.terminalID)?.monitorTarget)
        #expect(plan.entry(for: existingTab.terminalID)?.monitorTarget == plan.entry(for: managed.terminalID)?.monitorTarget)
    }

    @Test
    func monitorTargetsRequireAttachableKeysInsteadOfUnsafeGlobalScans() {
        let codex = TerminalSnapshot.makePreview(
            terminalID: "codex-no-cwd",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: nil,
            isFocused: true,
            visibleText: "OpenAI Codex\nWhat should I work on next?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 101,
            foregroundProcessName: "codex"
        )
        let kimi = TerminalSnapshot.makePreview(
            terminalID: "kimi-no-cwd",
            windowID: "w1",
            tabID: "t2",
            title: "Kimi Code",
            cwd: nil,
            isFocused: false,
            visibleText: "Welcome to Kimi Code CLI\nWhat do you need help with?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 202,
            foregroundProcessName: "kimi"
        )
        let claude = TerminalSnapshot.makePreview(
            terminalID: "claude-no-keys",
            windowID: "w1",
            tabID: "t3",
            title: "Claude Code",
            cwd: nil,
            isFocused: false,
            visibleText: "Welcome to Claude Code\nWhat would you like to do?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: nil,
            foregroundProcessName: "claude"
        )

        let plan = AgentRuntimeRefreshPlan(snapshots: [codex, kimi, claude])

        #expect(plan.entry(for: codex.terminalID)?.monitorTarget == nil)
        #expect(plan.entry(for: kimi.terminalID)?.monitorTarget == nil)
        #expect(plan.entry(for: claude.terminalID)?.monitorTarget == nil)
    }

    @Test
    func managedLaunchAttachmentHintsSupplyStartupWorkingDirectoriesAcrossAgents() {
        let codex = TerminalSnapshot.makePreview(
            terminalID: "codex-bootstrap",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: nil,
            isFocused: true,
            visibleText: "OpenAI Codex\nWhat should I work on next?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 111,
            foregroundProcessName: "codex"
        )
        let kimi = TerminalSnapshot.makePreview(
            terminalID: "kimi-bootstrap",
            windowID: "w1",
            tabID: "t2",
            title: "Kimi Code",
            cwd: nil,
            isFocused: false,
            visibleText: "Welcome to Kimi Code CLI\nWhat do you need help with?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 222,
            foregroundProcessName: "kimi"
        )
        let claude = TerminalSnapshot.makePreview(
            terminalID: "claude-bootstrap",
            windowID: "w1",
            tabID: "t3",
            title: "Claude Code",
            cwd: nil,
            isFocused: false,
            visibleText: "Welcome to Claude Code\nWhat would you like to do?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 333,
            foregroundProcessName: "claude"
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: [codex, kimi, claude],
            attachmentHintsByTerminalID: [
                codex.terminalID: AgentRuntimeAttachmentHint(identity: .codex, workingDirectory: " /tmp/codex-bootstrap "),
                kimi.terminalID: AgentRuntimeAttachmentHint(identity: .kimi, workingDirectory: "/tmp/kimi-bootstrap"),
                claude.terminalID: AgentRuntimeAttachmentHint(identity: .claudeCode, workingDirectory: "/tmp/claude-bootstrap"),
            ]
        )

        #expect(plan.entry(for: codex.terminalID)?.monitorTarget == .codex(workingDirectory: "/tmp/codex-bootstrap"))
        #expect(plan.entry(for: kimi.terminalID)?.monitorTarget == .kimi(workingDirectory: "/tmp/kimi-bootstrap"))
        #expect(plan.entry(for: claude.terminalID)?.monitorTarget == .claude(pid: 333, workingDirectory: "/tmp/claude-bootstrap"))
    }

    @Test
    func attachmentHintDoesNotOverrideRealWorkingDirectory() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-real-cwd",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: "/tmp/real-project",
            isFocused: true,
            visibleText: "OpenAI Codex\nWhat should I work on next?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 444,
            foregroundProcessName: "codex"
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: [snapshot],
            attachmentHintsByTerminalID: [
                snapshot.terminalID: AgentRuntimeAttachmentHint(identity: .codex, workingDirectory: "/tmp/bootstrap-project"),
            ]
        )

        #expect(plan.entry(for: snapshot.terminalID)?.monitorTarget == .codex(workingDirectory: "/tmp/real-project"))
    }

    @Test
    func attachmentHintIsIgnoredForMismatchedOrMissingIdentity() {
        let mismatched = TerminalSnapshot.makePreview(
            terminalID: "codex-mismatch",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: nil,
            isFocused: true,
            visibleText: "OpenAI Codex\nWhat should I work on next?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 555,
            foregroundProcessName: "codex"
        )
        let unknown = TerminalSnapshot.makePreview(
            terminalID: "unknown-bootstrap",
            windowID: "w1",
            tabID: "t2",
            title: "shell",
            cwd: nil,
            isFocused: false,
            visibleText: "nambouchara@host project % ",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "zsh",
            cursorIsAtPrompt: true
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: [mismatched, unknown],
            attachmentHintsByTerminalID: [
                mismatched.terminalID: AgentRuntimeAttachmentHint(identity: .kimi, workingDirectory: "/tmp/wrong-agent"),
                unknown.terminalID: AgentRuntimeAttachmentHint(identity: .codex, workingDirectory: "/tmp/no-identity"),
            ]
        )

        #expect(plan.entry(for: mismatched.terminalID)?.monitorTarget == nil)
        #expect(plan.entry(for: unknown.terminalID)?.monitorTarget == nil)
    }

    @Test
    func claudeCanStillAttachByPidOrWorkingDirectoryAlone() {
        let pidOnly = TerminalSnapshot.makePreview(
            terminalID: "claude-pid-only",
            windowID: "w1",
            tabID: "t1",
            title: "Claude Code",
            cwd: nil,
            isFocused: true,
            visibleText: "Welcome to Claude Code\nWhat would you like to do?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 12345,
            foregroundProcessName: "claude"
        )
        let cwdOnly = TerminalSnapshot.makePreview(
            terminalID: "claude-cwd-only",
            windowID: "w1",
            tabID: "t2",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "Welcome to Claude Code\nWhat would you like to do?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: nil,
            foregroundProcessName: nil
        )

        let plan = AgentRuntimeRefreshPlan(snapshots: [pidOnly, cwdOnly])

        #expect(plan.entry(for: pidOnly.terminalID)?.monitorTarget == .claude(pid: 12345, workingDirectory: nil))
        #expect(plan.entry(for: cwdOnly.terminalID)?.monitorTarget == .claudeWorkingDirectory("/tmp/project"))
    }

    @Test
    func monitorRestartFollowsFreshTerminalExecutionInsteadOfBackgroundSessionChurn() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "OpenAI Codex\nWhat should I work on next?\n›",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 1001,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "• Working (0s • esc to interrupt)",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 1001,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: [current],
            previousSnapshotsByTerminalID: [current.terminalID: previous]
        )

        #expect(plan.entry(for: current.terminalID)?.shouldRestartMonitor == true)
    }

    @Test
    func managedManualAndNewTabFreshExecutionTransitionsKeepRestartParityForCodex() throws {
        let cases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("codex-restart-existing", "shell", true),
            ("codex-restart-new-tab", "nambouchara@host:~", false),
            ("codex-restart-managed", "OpenAI Codex", false),
        ]

        var entries: [AgentRuntimeRefreshPlan.Entry] = []

        for entry in cases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "w1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: "OpenAI Codex\nWhat should I work on next?\n›",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: 1001,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "w1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: "• Working (0s • esc to interrupt)",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: 1001,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            )

            let plan = AgentRuntimeRefreshPlan(
                snapshots: [current],
                previousSnapshotsByTerminalID: [current.terminalID: previous]
            )
            entries.append(try #require(plan.entry(for: current.terminalID)))
        }

        let first = try #require(entries.first)
        #expect(entries.dropFirst().allSatisfy { $0.detection == first.detection })
        #expect(entries.dropFirst().allSatisfy { $0.monitorTarget == first.monitorTarget })
        #expect(entries.allSatisfy { $0.shouldRestartMonitor })
        #expect(first.monitorTarget == .codex(workingDirectory: "/tmp/project"))
        #expect(first.detection?.identity == .codex)
        #expect(first.detection?.state == .working)
    }

    @Test
    func managedManualAndNewTabResolvedInteractiveSurfaceTransitionsKeepAttachmentParityAcrossCodexAndClaude() throws {
        let codexCases: [(terminalID: String, title: String, isFocused: Bool)] = [
            ("codex-idle-existing", "shell", true),
            ("codex-idle-new-tab", "nambouchara@host:~", false),
            ("codex-idle-managed", "OpenAI Codex", false),
        ]
        let claudeCases: [(terminalID: String, title: String, isFocused: Bool, pid: Int)] = [
            ("claude-idle-existing", "shell", true, 3101),
            ("claude-idle-new-tab", "nambouchara@host:~", false, 3102),
            ("claude-idle-managed", "Claude Code", false, 3103),
        ]

        var codexEntries: [AgentRuntimeRefreshPlan.Entry] = []
        var claudeEntries: [AgentRuntimeRefreshPlan.Entry] = []

        for entry in codexCases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "w1",
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
                foregroundProcessID: 2101,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "w1",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/tmp/project",
                isFocused: entry.isFocused,
                visibleText: "nambouchara@host ghostty % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: 2101,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            )

            let plan = AgentRuntimeRefreshPlan(
                snapshots: [current],
                previousSnapshotsByTerminalID: [current.terminalID: previous]
            )
            codexEntries.append(try #require(plan.entry(for: current.terminalID)))
        }

        for entry in claudeCases {
            let previous = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "w2",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: """
                Accessing workspace:

                /Users/nambouchara

                Quick safety check: Is this a project you created or one you trust?

                Security guide

                 ❯ 1. Yes, I trust this folder
                   2. No, exit

                 Enter to confirm · Esc to cancel
                """,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.pid,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            )
            let current = TerminalSnapshot.makePreview(
                terminalID: entry.terminalID,
                windowID: "w2",
                tabID: "tab-\(entry.terminalID)",
                title: entry.title,
                cwd: "/Users/nambouchara",
                isFocused: entry.isFocused,
                visibleText: "nambouchara@host ghostty % ",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: entry.pid,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: true,
                usingAlternateScreen: false
            )

            let plan = AgentRuntimeRefreshPlan(
                snapshots: [current],
                previousSnapshotsByTerminalID: [current.terminalID: previous]
            )
            claudeEntries.append(try #require(plan.entry(for: current.terminalID)))
        }

        let firstCodex = try #require(codexEntries.first)
        let firstClaude = try #require(claudeEntries.first)
        #expect(codexEntries.dropFirst().allSatisfy { $0.detection == firstCodex.detection })
        #expect(codexEntries.dropFirst().allSatisfy { $0.monitorTarget == firstCodex.monitorTarget })
        #expect(codexEntries.dropFirst().allSatisfy { $0.shouldRestartMonitor == firstCodex.shouldRestartMonitor })
        #expect(firstCodex.detection?.identity == .codex)
        #expect(firstCodex.detection?.state == .idle)
        #expect(firstCodex.monitorTarget == .codex(workingDirectory: "/tmp/project"))
        #expect(firstCodex.shouldRestartMonitor == false)

        #expect(claudeEntries.dropFirst().allSatisfy { $0.detection == firstClaude.detection })
        #expect(claudeEntries.dropFirst().allSatisfy { $0.monitorTarget == firstClaude.monitorTarget })
        #expect(claudeEntries.dropFirst().allSatisfy { $0.shouldRestartMonitor == firstClaude.shouldRestartMonitor })
        #expect(firstClaude.detection?.identity == .claudeCode)
        #expect(firstClaude.detection?.state == .idle)
        #expect(firstClaude.monitorTarget == .claude(pid: 3101, workingDirectory: "/Users/nambouchara"))
        #expect(firstClaude.shouldRestartMonitor == false)
    }

    @Test
    func steadyWaitingStateDoesNotRestartMonitor() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "kimi-term",
            windowID: "w1",
            tabID: "t1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Welcome to Kimi Code CLI\nWhat do you need help with?\n›",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 2001,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "kimi-term",
            windowID: "w1",
            tabID: "t1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Welcome to Kimi Code CLI\nWhat do you need help with?\n›",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 2001,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let plan = AgentRuntimeRefreshPlan(
            snapshots: [current],
            previousSnapshotsByTerminalID: [current.terminalID: previous]
        )

        #expect(plan.entry(for: current.terminalID)?.shouldRestartMonitor == false)
    }
}
