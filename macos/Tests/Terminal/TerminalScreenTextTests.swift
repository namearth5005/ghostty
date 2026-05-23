import Foundation
import Testing
@testable import Ghostty

struct TerminalScreenTextTests {
    @Test
    func meaningfulLinesFilterPromptAndInputChrome() {
        let lines = TerminalScreenText.meaningfulLines(
            from: """
            nambouchara@host ghostty %
            What would you like me to do here?
            ---------- input ----------
            agent (Kimi-k2.6) context: project
            """
        )

        #expect(lines == ["What would you like me to do here?"])
    }

    @Test
    func lastMeaningfulEventPrefersNewLineOverRepeatedHistory() {
        let event = TerminalScreenText.lastMeaningfulEvent(
            currentVisibleText: """
            step 1 complete
            step 2 complete
            What should I do next?
            """,
            previousVisibleText: """
            step 1 complete
            step 2 complete
            """
        )

        #expect(event == "What should I do next?")
    }

    @Test
    func lastMeaningfulEventFallsBackToLastCurrentLineWhenNothingIsNew() {
        let event = TerminalScreenText.lastMeaningfulEvent(
            currentVisibleText: """
            step 1 complete
            step 2 complete
            """,
            previousVisibleText: """
            step 1 complete
            step 2 complete
            """
        )

        #expect(event == "step 2 complete")
    }

    @Test
    func questionDetectionRequiresQuestionMark() {
        #expect(TerminalScreenText.looksLikeQuestion("What should I do next?") == true)
        #expect(TerminalScreenText.looksLikeQuestion("Working on the next step") == false)
    }

    @Test
    func lastMeaningfulEventPrefersChoiceMenuQuestionOverFooterAndOptions() {
        let event = TerminalScreenText.lastMeaningfulEvent(
            currentVisibleText: """
            Accessing workspace:

            /Users/nambouchara

            Quick safety check: Is this a project you created or one you trust?

            Security guide

             ❯ 1. Yes, I trust this folder
               2. No, exit

             Enter to confirm · Esc to cancel
            """,
            previousVisibleText: ""
        )

        #expect(event == "Quick safety check: Is this a project you created or one you trust?")
    }

    @Test
    func lastMeaningfulEventPrefersNewOutputOverStaleChoiceMenuHistory() {
        let event = TerminalScreenText.lastMeaningfulEvent(
            currentVisibleText: """
            Accessing workspace:

            /Users/nambouchara

            Quick safety check: Is this a project you created or one you trust?

             ❯ 1. Yes, I trust this folder
               2. No, exit

             Enter to confirm · Esc to cancel

            Reading repository files...
            """,
            previousVisibleText: ""
        )

        #expect(event == "Reading repository files...")
    }

    @Test
    func activeChoiceMenuContextAllowsKimiInputChromeTail() {
        let context = TerminalScreenText.activeChoiceMenuContext(
            from: """
            Kimi is analyzing how this project can work with Claude Code, ChatGPT, and Cursor.

            What do you want to do?

            ❯ 1. Keep the core clinical content as provider-agnostic files
              2. Create different adapters for each platform

            agent (Kimi-k2.6 *) ~/speed2
            """
        )

        #expect(context == .init(
            question: "What do you want to do?",
            options: [
                "Keep the core clinical content as provider-agnostic files",
                "Create different adapters for each platform",
            ]
        ))
    }
}
