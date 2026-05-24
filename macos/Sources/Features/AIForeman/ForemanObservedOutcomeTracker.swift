import Foundation

struct ForemanObservedOutcomeTracker: Sendable {
    private(set) var reportsByTerminalID: [String: TerminalOutcomeReport] = [:]

    mutating func registerPendingCommand(terminalID: String) {
        reportsByTerminalID.removeValue(forKey: terminalID)
    }

    mutating func observe(_ report: TerminalOutcomeReport) {
        reportsByTerminalID[report.terminalID] = report
    }

    mutating func prune(activeTerminalIDs: Set<String>) {
        reportsByTerminalID = reportsByTerminalID.filter { activeTerminalIDs.contains($0.key) }
    }
}
