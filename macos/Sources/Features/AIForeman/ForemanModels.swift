import Foundation

struct TerminalSummary: Codable, Equatable, Sendable {
    let terminalID: String
    let summary: String
    let state: String
    let confidence: Double
    let needsUserAttention: Bool
    let suggestedNextStep: String

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case summary
        case state
        case confidence
        case needsUserAttention = "needs_user_attention"
        case suggestedNextStep = "suggested_next_step"
    }
}

struct DispatchDraft: Codable, Equatable, Sendable {
    let terminalID: String
    let reason: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case reason
        case message
    }
}

struct DispatchPlan: Codable, Equatable, Sendable {
    let planSummary: String
    let drafts: [DispatchDraft]

    enum CodingKeys: String, CodingKey {
        case planSummary = "plan_summary"
        case drafts
    }
}
