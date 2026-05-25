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
    // ContentPart payloads
    let type: String?
    let text: String?

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
        case type
        case text
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

    init(
        user_input: [ContentPart]? = nil,
        n: Int? = nil,
        context_usage: Double? = nil,
        context_tokens: Int? = nil,
        max_context_tokens: Int? = nil,
        plan_mode: Bool? = nil,
        id: String? = nil,
        tool_call_id: String? = nil,
        sender: String? = nil,
        action: String? = nil,
        description: String? = nil,
        display: [DisplayBlock]? = nil,
        questions: [QuestionItem]? = nil,
        name: String? = nil,
        arguments: String? = nil,
        content: String? = nil,
        finish_reason: String? = nil,
        code: String? = nil,
        message: String? = nil,
        type: String? = nil,
        text: String? = nil
    ) {
        self.user_input = user_input
        self.n = n
        self.context_usage = context_usage
        self.context_tokens = context_tokens
        self.max_context_tokens = max_context_tokens
        self.plan_mode = plan_mode
        self.id = id
        self.tool_call_id = tool_call_id
        self.sender = sender
        self.action = action
        self.description = description
        self.display = display
        self.questions = questions
        self.name = name
        self.arguments = arguments
        self.content = content
        self.finish_reason = finish_reason
        self.code = code
        self.message = message
        self.type = type
        self.text = text
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
            return .waitingApproval(
                description: desc,
                tool: tool,
                requestID: message.payload.id,
                sessionID: nil,
                revision: nil,
                isPlanning: message.payload.plan_mode ?? false
            )

        case "QuestionRequest":
            guard let firstQuestion = message.payload.questions?.first else {
                return nil
            }
            let questionText = firstQuestion.question
            if let options = firstQuestion.options, !options.isEmpty {
                return .waitingChoice(
                    question: questionText,
                    options: options.map(\.label),
                    requestID: message.payload.id,
                    sessionID: nil,
                    revision: nil,
                    isPlanning: message.payload.plan_mode ?? false
                )
            }
            return .waitingText(
                question: questionText,
                requestID: message.payload.id,
                sessionID: nil,
                revision: nil,
                isPlanning: message.payload.plan_mode ?? false
            )

        case "TurnBegin":
            return .running(stepDescription: nil, sessionID: nil, revision: nil)

        case "TurnEnd":
            return .waitingText(
                question: nil,
                requestID: nil,
                sessionID: nil,
                revision: nil,
                isPlanning: message.payload.plan_mode ?? false
            )

        case "StepBegin":
            let step = message.payload.n.map { "Step \($0)" }
            return .running(stepDescription: step, sessionID: nil, revision: message.payload.n)

        case "Error":
            let err = message.payload.message ?? message.payload.code ?? "Unknown error"
            return .error(description: err, sessionID: nil, revision: nil)

        default:
            return nil
        }
    }
}
