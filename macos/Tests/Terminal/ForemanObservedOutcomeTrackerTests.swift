import Foundation
import Testing
@testable import Ghostty

struct ForemanObservedOutcomeTrackerTests {
    @Test
    func registerPendingCommandClearsStaleOutcomeForTerminal() {
        var tracker = ForemanObservedOutcomeTracker()
        let staleOutcome = TerminalOutcomeReport(
            terminalID: "term-1",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: Date(timeIntervalSince1970: 1),
            summary: "Tests finished successfully."
        )

        tracker.observe(staleOutcome)
        tracker.registerPendingCommand(terminalID: "term-1")

        #expect(tracker.reportsByTerminalID["term-1"] == nil)
    }

    @Test
    func observeStoresLatestReportPerTerminal() {
        var tracker = ForemanObservedOutcomeTracker()
        let first = TerminalOutcomeReport(
            terminalID: "term-1",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: Date(timeIntervalSince1970: 1),
            summary: "Tests finished successfully."
        )
        let second = TerminalOutcomeReport(
            terminalID: "term-1",
            sentCommand: "npm test",
            outcome: .failure,
            detectedAt: Date(timeIntervalSince1970: 2),
            summary: "Tests failed."
        )

        tracker.observe(first)
        tracker.observe(second)

        #expect(tracker.reportsByTerminalID["term-1"] == second)
    }

    @Test
    func pruneRemovesInactiveTerminalOutcomes() {
        var tracker = ForemanObservedOutcomeTracker()
        tracker.observe(
            TerminalOutcomeReport(
                terminalID: "term-1",
                sentCommand: "npm test",
                outcome: .success,
                detectedAt: Date(timeIntervalSince1970: 1),
                summary: "Tests finished successfully."
            )
        )
        tracker.observe(
            TerminalOutcomeReport(
                terminalID: "term-2",
                sentCommand: "swift build",
                outcome: .failure,
                detectedAt: Date(timeIntervalSince1970: 2),
                summary: "Build failed."
            )
        )

        tracker.prune(activeTerminalIDs: ["term-2"])

        #expect(tracker.reportsByTerminalID["term-1"] == nil)
        #expect(tracker.reportsByTerminalID["term-2"]?.summary == "Build failed.")
    }
}
