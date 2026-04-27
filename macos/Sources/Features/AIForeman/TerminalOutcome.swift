import Foundation

enum TerminalOutcome: String, Codable, Sendable, Equatable {
    case unknown
    case success
    case failure
    case hung
    case needsInput
    case stillRunning
}

struct TerminalOutcomeReport: Identifiable, Sendable {
    let id: UUID
    let terminalID: String
    let sentCommand: String
    let outcome: TerminalOutcome
    let detectedAt: Date
    let summary: String?
    let parsedOutput: ParsedTerminalOutput?
}
