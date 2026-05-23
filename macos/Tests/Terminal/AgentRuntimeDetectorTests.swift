import Foundation
import Testing
@testable import Ghostty

struct AgentRuntimeDetectorTests {
    private let detector = AgentRuntimeDetector()

    @Test
    func processIdentityWinsOverMisleadingVisibleFallbacks() {
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

        let detection = detector.detect(current: snapshot)

        #expect(detection?.identity == .codex)
        #expect(detection?.state == .blocked)
    }

    @Test
    func similarlyNamedProcessesDoNotCreateRuntimeDetectionWithoutSeparateScreenEvidence() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-claude-helper",
                windowID: "win-1",
                tabID: "tab-1",
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
                windowID: "win-1",
                tabID: "tab-2",
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
                windowID: "win-1",
                tabID: "tab-3",
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

        for snapshot in snapshots {
            #expect(detector.identity(for: snapshot) == nil)
            #expect(detector.detect(current: snapshot) == nil)
        }
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

            --- input ---
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: nil,
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let detection = detector.detect(current: snapshot)

        #expect(detection?.identity == .kimi)
        #expect(detection?.state == .blocked)
    }

    @Test
    func codexQuestionPromptMapsToBlocked() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
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

        let detection = detector.detect(current: snapshot)

        #expect(detection?.identity == .codex)
        #expect(detection?.state == .blocked)
    }

    @Test
    func codexWelcomeScreenPermissionsLineDoesNotTriggerApprovalState() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            >_ OpenAI Codex (v0.131.0)

            model: gpt-5.4 xhigh
            directory: ~/speed2/ghostty
            permissions: YOLO mode

            • Hello. What do you want to work on in ghostty?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let detection = detector.detect(current: snapshot)

        #expect(detection?.identity == .codex)
        #expect(detection?.state == .blocked)
        #expect(detection?.evidence.first?.detail != "Detected approval request on screen.")
    }

    @Test
    func codexWorkingHeaderMapsToWorking() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "speed2",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "• Working (0s • esc to interrupt)",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let detection = detector.detect(current: snapshot)

        #expect(detection?.identity == .codex)
        #expect(detection?.state == .working)
    }

    @Test
    func claudePromptMapsToBlocked() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Claude",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            What do you want to do?

            ›
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let detection = detector.detect(current: snapshot)

        #expect(detection?.identity == .claudeCode)
        #expect(detection?.state == .blocked)
    }

    @Test
    func kimiApprovalWireOutranksRunningHeuristicAndMapsToBlocked() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Thinking...",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let wireRecord = KimiWireRecord(
            timestamp: 123,
            message: KimiWireMessage(
                type: "ApprovalRequest",
                payload: KimiWirePayload(
                    user_input: nil,
                    n: nil,
                    context_usage: nil,
                    context_tokens: nil,
                    max_context_tokens: nil,
                    plan_mode: nil,
                    id: "req-1",
                    tool_call_id: nil,
                    sender: "shell",
                    action: "execute",
                    description: "Run shell command",
                    display: nil,
                    questions: nil,
                    name: nil,
                    arguments: nil,
                    content: nil,
                    finish_reason: nil,
                    code: nil,
                    message: nil
                )
            )
        )

        let detection = detector.detect(
            current: snapshot,
            kimiWireRecords: [wireRecord]
        )

        #expect(detection?.identity == .kimi)
        #expect(detection?.state == .blocked)
    }

    @Test
    func manualAndManagedCodexLaunchesShareSameRuntimeDetection() {
        let manual = TerminalSnapshot.makePreview(
            terminalID: "term-manual",
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

        let managed = TerminalSnapshot.makePreview(
            terminalID: "term-managed",
            windowID: "win-1",
            tabID: "tab-2",
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

        let manualDetection = detector.detect(current: manual)
        let managedDetection = detector.detect(current: managed)

        #expect(manualDetection?.identity == managedDetection?.identity)
        #expect(manualDetection?.state == managedDetection?.state)
        #expect(manualDetection?.identity == .codex)
        #expect(manualDetection?.state == .blocked)
    }

    @Test
    func managedAndManualLaunchesShareSameMonitorIdentityAcrossAgents() {
        let manualKimi = TerminalSnapshot.makePreview(
            terminalID: "term-kimi-manual",
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
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managedKimi = TerminalSnapshot.makePreview(
            terminalID: "term-kimi-managed",
            windowID: "win-1",
            tabID: "tab-2",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: manualKimi.visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        let manualClaude = TerminalSnapshot.makePreview(
            terminalID: "term-claude-manual",
            windowID: "win-1",
            tabID: "tab-3",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            Welcome to Claude Code

            What would you like to do?
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let managedClaude = TerminalSnapshot.makePreview(
            terminalID: "term-claude-managed",
            windowID: "win-1",
            tabID: "tab-4",
            title: "Claude Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: manualClaude.visibleText,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )

        #expect(detector.matches(manualKimi, identity: .kimi))
        #expect(detector.matches(managedKimi, identity: .kimi))
        #expect(detector.identity(for: manualKimi) == detector.identity(for: managedKimi))

        #expect(detector.matches(manualClaude, identity: .claudeCode))
        #expect(detector.matches(managedClaude, identity: .claudeCode))
        #expect(detector.identity(for: manualClaude) == detector.identity(for: managedClaude))
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
            visibleText: """
            nambouchara@Nams-MacBook-Pro ghostty %
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "zsh",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
        )

        #expect(detector.identity(for: snapshot) == nil)
        #expect(detector.detect(current: snapshot) == nil)
    }

    @Test
    func pathLikeTitleContainingAgentNameDoesNotCreateRuntimeDetectionWhenProcessIsMissing() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-shell-path",
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
        )

        #expect(detector.identity(for: snapshot) == nil)
        #expect(detector.detect(current: snapshot) == nil)
    }

    @Test
    func claudeTrustPromptWithoutProcessSharesBlockedRuntimeDetectionAcrossLaunchPaths() {
        let visibleText = """
        Accessing workspace:

        /Users/nambouchara

        Quick safety check: Is this a project you created or one you trust?

        Security guide

         ❯ 1. Yes, I trust this folder
           2. No, exit

         Enter to confirm · Esc to cancel
        """

        let snapshots = [
            TerminalSnapshot.makePreview(
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
            ),
            TerminalSnapshot.makePreview(
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
            ),
            TerminalSnapshot.makePreview(
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
            ),
        ]

        let detections = snapshots.map { detector.detect(current: $0) }
        #expect(detections.allSatisfy { $0?.identity == .claudeCode })
        #expect(detections.allSatisfy { $0?.state == .blocked })
    }

    @Test
    func proseMentionsOfAgentNamesDoNotCreateRuntimeDetectionWithoutOtherEvidence() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "claude-prose",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "I compared Claude Code and ChatGPT while writing these notes.",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-prose",
                windowID: "win-1",
                tabID: "tab-2",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "OpenAI Codex is documented in the migration plan below.",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: false,
                usingAlternateScreen: false
            ),
        ]

        for snapshot in snapshots {
            #expect(detector.identity(for: snapshot) == nil)
            #expect(detector.detect(current: snapshot) == nil)
        }
    }
}
