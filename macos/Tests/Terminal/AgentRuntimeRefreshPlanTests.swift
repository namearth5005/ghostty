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
