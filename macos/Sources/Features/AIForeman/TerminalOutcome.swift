import Foundation

enum TerminalOutcome: String, Codable, Sendable, Equatable {
    case unknown
    case success
    case failure
    case hung
    case needsInput
    case stillRunning
}

struct TerminalOutcomeReport: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let terminalID: String
    let sentCommand: String
    let outcome: TerminalOutcome
    let detectedAt: Date
    let summary: String?
    let parsedOutput: ParsedTerminalOutput?

    enum CodingKeys: String, CodingKey {
        case id
        case terminalID = "terminal_id"
        case sentCommand = "sent_command"
        case outcome
        case detectedAt = "detected_at"
        case summary
    }

    init(
        id: UUID = UUID(),
        terminalID: String,
        sentCommand: String,
        outcome: TerminalOutcome,
        detectedAt: Date,
        summary: String? = nil,
        parsedOutput: ParsedTerminalOutput? = nil
    ) {
        self.id = id
        self.terminalID = terminalID
        self.sentCommand = sentCommand
        self.outcome = outcome
        self.detectedAt = detectedAt
        self.summary = summary
        self.parsedOutput = parsedOutput
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.terminalID = try container.decode(String.self, forKey: .terminalID)
        self.sentCommand = try container.decode(String.self, forKey: .sentCommand)
        self.outcome = try container.decode(TerminalOutcome.self, forKey: .outcome)
        self.detectedAt = try container.decode(Date.self, forKey: .detectedAt)
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.parsedOutput = nil
    }

    static func == (lhs: TerminalOutcomeReport, rhs: TerminalOutcomeReport) -> Bool {
        lhs.id == rhs.id &&
        lhs.terminalID == rhs.terminalID &&
        lhs.sentCommand == rhs.sentCommand &&
        lhs.outcome == rhs.outcome &&
        lhs.detectedAt == rhs.detectedAt &&
        lhs.summary == rhs.summary
    }
}

struct SituationOutcomeRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let terminalID: String
    let situationFingerprint: Int
    let cwd: String
    let action: String
    let outcome: TerminalOutcome
    let visibleText: String?
    let timestamp: Date
    let projectPath: String?
}

struct SessionSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let terminalID: String
    let summary: String
    let keywords: [String]
    let projectPath: String?
    let timestamp: Date
}
