import Foundation

// MARK: - Top-level Wire Record

/// A single line from `wire.jsonl`: `{"timestamp": 123.456, "message": {"type": "TurnBegin", "payload": {...}}}`
struct KimiWireRecord: Codable, Equatable, Sendable {
    let timestamp: Double?
    let message: KimiWireMessage
}

// MARK: - Wire Message

struct KimiWireMessage: Codable, Equatable, Sendable {
    let type: String
    let payload: KimiWirePayload
}

// MARK: - Wire Payload

struct KimiWirePayload: Codable, Equatable, Sendable {
    // Event payloads
    let user_input: [ContentPart]?
    let n: Int?                          // StepBegin
    let context_usage: Double?
    let context_tokens: Int?
    let max_context_tokens: Int?
    let plan_mode: Bool?

    // Request payloads
    let id: String?
    let tool_call_id: String?
    let sender: String?
    let action: String?
    let description: String?
    let display: [DisplayBlock]?
    let questions: [QuestionItem]?
    let name: String?
    let arguments: String?

    // Completion
    let content: String?
    let finish_reason: String?

    // Error
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case user_input
        case n
        case context_usage
        case context_tokens
        case max_context_tokens
        case plan_mode
        case id
        case tool_call_id
        case sender
        case action
        case description
        case display
        case questions
        case name
        case arguments
        case content
        case finish_reason
        case code
        case message
    }
}

// MARK: - Display Block

struct DisplayBlock: Codable, Equatable, Sendable {
    let type: String?
    let text: String?
    let language: String?
    let path: String?
    let content: String?
}

// MARK: - Question Item

struct QuestionItem: Codable, Equatable, Sendable {
    let question: String
    let header: String?
    let options: [QuestionOption]?
    let multi_select: Bool?
}

// MARK: - Question Option

struct QuestionOption: Codable, Equatable, Sendable {
    let label: String
    let description: String?
}

// MARK: - Content Part

struct ContentPart: Codable, Equatable, Sendable {
    let type: String
    let text: String?
}

// MARK: - Convenience for context building

extension KimiWireRecord {
    /// Maps a wire record to an agent interaction context.
    /// Returns `nil` if the record type does not carry actionable state.
    var asAgentInteractionContext: AgentInteractionContext? {
        switch message.type {
        case "ApprovalRequest":
            let desc = message.payload.description ?? "Approval requested"
            let tool = message.payload.sender ?? message.payload.tool_call_id
            return .waitingApproval(description: desc, tool: tool)

        case "QuestionRequest":
            guard let firstQuestion = message.payload.questions?.first else {
                return nil
            }
            let questionText = firstQuestion.question
            if let options = firstQuestion.options, !options.isEmpty {
                return .waitingChoice(
                    question: questionText,
                    options: options.map(\.label)
                )
            }
            return .waitingText(question: questionText)

        case "TurnBegin":
            return .running(stepDescription: nil)

        case "TurnEnd":
            return .waitingText(question: nil)

        case "StepBegin":
            let step = message.payload.n.map { "Step \($0)" }
            return .running(stepDescription: step)

        case "Error":
            let err = message.payload.message ?? message.payload.code ?? "Unknown error"
            return .error(description: err)

        default:
            return nil
        }
    }
}
