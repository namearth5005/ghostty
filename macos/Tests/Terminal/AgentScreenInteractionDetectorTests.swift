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
}
