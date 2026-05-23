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
}
