import Foundation
import Testing
@testable import Ghostty

struct ForemanNotifierTests {
    @Test
    func notificationMessagePrefersRollupSummaryOverride() {
        let report = TerminalOutcomeReport(
            terminalID: "term-2",
            sentCommand: "pnpm build",
            outcome: .failure,
            detectedAt: Date(timeIntervalSince1970: 1_748_444_444),
            summary: "Build failed."
        )

        let message = ForemanNotifier.notificationMessage(
            previous: .stillRunning,
            report: report,
            summaryOverride: "2 terminals need attention: term-1 reply required; term-2 build failed."
        )

        #expect(message?.title == "Foreman Update")
        #expect(message?.body == "2 terminals need attention: term-1 reply required; term-2 build failed.")
    }

    @Test
    func notificationMessageFallsBackToTerminalSpecificOutcomeText() {
        let report = TerminalOutcomeReport(
            terminalID: "term-9",
            sentCommand: "npm test",
            outcome: .success,
            detectedAt: Date(timeIntervalSince1970: 1_748_555_555)
        )

        let message = ForemanNotifier.notificationMessage(
            previous: .stillRunning,
            report: report,
            summaryOverride: nil
        )

        #expect(message?.title == "Foreman Update")
        #expect(message?.body == "term-9: npm test completed successfully.")
    }
}
