import Foundation
import Testing
@testable import Ghostty

struct SuggestedActionButtonTests {

    @MainActor
    @Test
    func executeSuggestionCallbackFiresWithCorrectArgs() {
        let store = ForemanSidebarStore()

        var capturedTerminalID: String?
        var capturedCommand: String?

        store.onExecuteSuggestion = { terminalID, command in
            capturedTerminalID = terminalID
            capturedCommand = command
        }

        store.executeSuggestion(terminalID: "test-terminal-123", command: "ls -la")

        #expect(capturedTerminalID == "test-terminal-123")
        #expect(capturedCommand == "ls -la")
    }

    @MainActor
    @Test
    func executeSuggestionNoOpWhenCallbackNil() {
        let store = ForemanSidebarStore()
        // onExecuteSuggestion is nil by default
        store.executeSuggestion(terminalID: "t1", command: "cmd")
        // Should not crash; test passes if we get here
        #expect(true)
    }
}
