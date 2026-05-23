import Foundation
import Testing
@testable import Ghostty

struct AgentScreenInteractionDetectorTests {
    private let detector = AgentScreenInteractionDetector()

    @Test
    func kimiWelcomeScreenDetectsWaitingTextSurface() throws {
        let detection = try #require(
            detector.detect(
                identity: .kimi,
                visibleText: """
                Welcome to Kimi Code CLI!
                Send /help for help information.

                Directory: /tmp/project
                Model: Kimi-k2.6
                """,
                lastEvent: ""
            )
        )

        #expect(detection.reason == .kimiWelcome)
        #expect(detection.context == .waitingText(question: nil))
    }

    @Test
    func kimiInputRegionDetectsWaitingTextSurface() throws {
        let detection = try #require(
            detector.detect(
                identity: .kimi,
                visibleText: """
                ─ input ─────────────────────────────────────────────────────────

                agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
                context: 5.4% (14.3k/262.1k)
                """,
                lastEvent: ""
            )
        )

        #expect(detection.reason == .kimiInputRegion)
        #expect(detection.context == .waitingText(question: nil))
    }

    @Test
    func mixedKimiWelcomeAndInputChromeDetectsWaitingTextSurface() throws {
        let detection = try #require(
            detector.detect(
                identity: .kimi,
                visibleText: """
                Welcome to Kimi Code CLI!
                Send /help for help information.

                Directory: /tmp/project
                Session: abc123
                Model: Kimi-k2.6

                ── input ──────────────────────────────────────────────
                agent (Kimi-k2.6 ●)  /tmp/project
                """,
                lastEvent: ""
            )
        )

        #expect(detection.reason == .kimiWelcome)
        #expect(detection.context == .waitingText(question: nil))
    }

    @Test
    func kimiWelcomeScreenWithTipDetectsWaitingTextSurface() throws {
        let detection = try #require(
            detector.detect(
                identity: .kimi,
                visibleText: """
                Welcome to Kimi Code CLI!
                Send /help for help information.

                Directory: ~
                Session: 3f27d18e-06d3-4610-8074-7cba5f709ffb
                Model: Kimi-k2.6

                Tip: Spot a bug or have feedback? Type /feedback right in this session — every report makes Kimi better.

                --- input ---
                """,
                lastEvent: ""
            )
        )

        #expect(detection.reason == .kimiWelcome)
        #expect(detection.context == .waitingText(question: nil))
    }

    @Test
    func kimiChoicePromptDetectsWaitingChoiceSurface() throws {
        let detection = try #require(
            detector.detect(
                identity: .kimi,
                visibleText: """
                Kimi is analyzing how this project can work with Claude Code, ChatGPT, and Cursor.

                What do you want to do?

                ❯ 1. Keep the core clinical content as provider-agnostic files
                  2. Create different adapters for each platform

                agent (Kimi-k2.6 *) ~/speed2
                """,
                lastEvent: "What do you want to do?"
            )
        )

        let expected: AgentInteractionContext = .waitingChoice(
            question: "What do you want to do?",
            options: [
                "Keep the core clinical content as provider-agnostic files",
                "Create different adapters for each platform",
            ]
        )
        #expect(detection.reason == .choiceMenu)
        #expect(detection.context == expected)
    }

    @Test
    func kimiInputTailAfterPriorOutputDetectsWaitingTextSurface() throws {
        let detection = try #require(
            detector.detect(
                identity: .kimi,
                visibleText: """
                ✨ go to the mend directory please
                • Used Shell (cd /Users/nambouchara/speed2/mend && pwd && ls -la)
                • I'm now in the mend directory at /Users/nambouchara/speed2/mend.
                  The directory contains:
                  • .claude/ – Claude configuration
                  • .git/ – Git repository
                  • docs/ – Documentation

                ── input ─────────────────────────────────────────────────────────────────

                agent (Kimi-k2.6 ●)  ~/speed2  ctrl-v: paste clipboard | @: mention files
                context: 5.4% (14.3k/262.1k)
                """,
                lastEvent: "• docs/ – Documentation"
            )
        )

        #expect(detection.reason == .kimiInputRegion)
        #expect(detection.context == .waitingText(question: nil))
    }

    @Test
    func kimiQuestionAboveInputChromeDetectsWaitingTextSurfaceWithQuestion() throws {
        let detection = try #require(
            detector.detect(
                identity: .kimi,
                visibleText: """
                I'm now in the /Users/nambouchara/speed2/mend directory. Here's what's inside:
                .claude/
                docs/
                hooks/
                install.sh
                journal-skill/
                skill/
                templates/
                LICENSE
                README.md
                .gitignore

                What would you like me to do here?

                ─ input ─────────────────────────────────────────────────────────

                agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
                context: 5.4% (14.3k/262.1k)
                """,
                lastEvent: "What would you like me to do here?"
            )
        )

        #expect(detection.reason == .kimiInputRegion)
        #expect(detection.context == .waitingText(question: "What would you like me to do here?"))
    }

    @Test
    func claudeTrustPromptDetectsWaitingChoiceSurface() throws {
        let detection = try #require(
            detector.detect(
                identity: .claudeCode,
                visibleText: """
                Accessing workspace:

                /Users/nambouchara

                Quick safety check: Is this a project you created or one you trust?

                 ❯ 1. Yes, I trust this folder
                   2. No, exit

                 Enter to confirm · Esc to cancel
                """,
                lastEvent: "Quick safety check: Is this a project you created or one you trust?"
            )
        )

        let expected: AgentInteractionContext = .waitingChoice(
            question: "Quick safety check: Is this a project you created or one you trust?",
            options: ["Yes, I trust this folder", "No, exit"]
        )
        #expect(detection.reason == .choiceMenu)
        #expect(detection.context == expected)
    }

    @Test
    func codexApprovalPromptDetectsWaitingApprovalSurface() throws {
        let detection = try #require(
            detector.detect(
                identity: .codex,
                visibleText: """
                Permission required

                Allow OpenAI Codex to edit auth.ts? [y/n]
                """,
                lastEvent: "Allow OpenAI Codex to edit auth.ts? [y/n]"
            )
        )

        let expected: AgentInteractionContext = .waitingApproval(
            description: "Allow OpenAI Codex to edit auth.ts? [y/n]",
            tool: nil
        )
        #expect(detection.reason == .approvalPrompt)
        #expect(detection.context == expected)
    }

    @Test
    func staleChoiceMenuHistoryDoesNotDetectWaitingChoiceSurface() {
        let detection = detector.detect(
            identity: .claudeCode,
            visibleText: """
            Accessing workspace:

            /Users/nambouchara

            Quick safety check: Is this a project you created or one you trust?

             ❯ 1. Yes, I trust this folder
               2. No, exit

             Enter to confirm · Esc to cancel

            Reading repository files...
            """,
            lastEvent: "Reading repository files..."
        )

        #expect(detection == nil)
    }

    @Test
    func staleKimiChoiceHistoryDoesNotDetectWaitingChoiceSurface() {
        let detection = detector.detect(
            identity: .kimi,
            visibleText: """
            Kimi is analyzing how this project can work with Claude Code, ChatGPT, and Cursor.

            What do you want to do?

            ❯ 1. Keep the core clinical content as provider-agnostic files
              2. Create different adapters for each platform

            agent (Kimi-k2.6 *) ~/speed2

            Reading repository files...
            """,
            lastEvent: "Reading repository files..."
        )

        #expect(detection == nil)
    }

    @Test
    func staleApprovalHistoryDoesNotDetectWaitingApprovalSurface() {
        let detection = detector.detect(
            identity: .codex,
            visibleText: """
            Permission required

            Allow OpenAI Codex to edit auth.ts? [y/n]

            Running repository analysis...
            """,
            lastEvent: "Running repository analysis..."
        )

        #expect(detection == nil)
    }

    @Test
    func staleKimiWelcomeHistoryDoesNotDetectWaitingTextSurface() {
        let detection = detector.detect(
            identity: .kimi,
            visibleText: """
            Welcome to Kimi Code CLI!
            Send /help for help information.

            Directory: /tmp/project
            Model: Kimi-k2.6

            Thinking...
            """,
            lastEvent: "Thinking..."
        )

        #expect(detection == nil)
    }

    @Test
    func staleKimiInputHistoryDoesNotDetectWaitingTextSurface() {
        let detection = detector.detect(
            identity: .kimi,
            visibleText: """
            ─ input ─────────────────────────────────────────────────────────

            agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
            context: 5.4% (14.3k/262.1k)

            Reading repository files...
            """,
            lastEvent: "Reading repository files..."
        )

        #expect(detection == nil)
    }
}
