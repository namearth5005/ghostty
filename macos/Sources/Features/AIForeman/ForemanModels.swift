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

// MARK: - Agent Models

enum AgentMode: String, Codable, Sendable, Equatable {
    case interactive   // asks user before each action
    case autonomous    // loops until goal complete
}

enum AgentStatus: String, Codable, Sendable, Equatable {
    case idle
    case observing
    case planning
    case executing
    case waitingForUser
    case complete
    case stuck
}

struct AgentReplyDraftResponse: Codable, Equatable, Sendable {
    let thought: String
    let suggestion: AgentReplyDraftSuggestion
}

enum AgentReplyDraftSuggestion: Codable, Equatable, Sendable {
    case replyToAgent(terminalID: String, message: String, reason: String, confidence: Double)
    case askHuman(terminalID: String, message: String, reason: String, confidence: Double)
    case noAction(reason: String, confidence: Double)

    enum CodingKeys: String, CodingKey {
        case type
        case terminalID = "terminal_id"
        case message
        case reason
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        let reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        let confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1.0

        switch type {
        case "reply_to_agent", "replyToAgent":
            let terminalID = try Self.decodeFlexibleString(from: container, forKey: .terminalID)
            self = .replyToAgent(
                terminalID: terminalID,
                message: message,
                reason: reason,
                confidence: confidence
            )
        case "ask_human", "askHuman":
            let terminalID = try Self.decodeFlexibleString(from: container, forKey: .terminalID)
            self = .askHuman(
                terminalID: terminalID,
                message: message,
                reason: reason,
                confidence: confidence
            )
        case "no_action", "noAction":
            self = .noAction(reason: reason.isEmpty ? message : reason, confidence: confidence)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown reply draft suggestion type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .replyToAgent(let terminalID, let message, let reason, let confidence):
            try container.encode("reply_to_agent", forKey: .type)
            try container.encode(terminalID, forKey: .terminalID)
            try container.encode(message, forKey: .message)
            try container.encode(reason, forKey: .reason)
            try container.encode(confidence, forKey: .confidence)
        case .askHuman(let terminalID, let message, let reason, let confidence):
            try container.encode("ask_human", forKey: .type)
            try container.encode(terminalID, forKey: .terminalID)
            try container.encode(message, forKey: .message)
            try container.encode(reason, forKey: .reason)
            try container.encode(confidence, forKey: .confidence)
        case .noAction(let reason, let confidence):
            try container.encode("no_action", forKey: .type)
            try container.encode(reason, forKey: .reason)
            try container.encode(confidence, forKey: .confidence)
        }
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String {
        if let string = try? container.decode(String.self, forKey: key) {
            return string
        }
        if let int = try? container.decode(Int.self, forKey: key) {
            return String(int)
        }
        if let double = try? container.decode(Double.self, forKey: key) {
            return String(double)
        }
        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: container.codingPath + [key], debugDescription: "Expected string-like value")
        )
    }
}

enum AgentAction: Codable, Equatable, Sendable {
    case respond(message: String)
    case sendCommand(terminalID: String, command: String, reason: String)
    case askUser(question: String)
    case declareComplete(summary: String)
    case declareStuck(reason: String)

    enum CodingKeys: String, CodingKey {
        case type
        case message
        case terminalID = "terminal_id"
        case command
        case reason
        case reasonStuck = "reason_stuck"
        case question
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "respond":
            let message = try container.decode(String.self, forKey: .message)
            self = .respond(message: message)
        case "send_command", "sendCommand":
            let terminalID = try Self.decodeFlexibleString(from: container, forKey: .terminalID)
            let command = try container.decode(String.self, forKey: .command)
            let reason = try container.decode(String.self, forKey: .reason)
            self = .sendCommand(terminalID: terminalID, command: command, reason: reason)
        case "ask_user", "askUser":
            let question = try container.decode(String.self, forKey: .question)
            self = .askUser(question: question)
        case "declare_complete", "declareComplete":
            let summary = try container.decode(String.self, forKey: .summary)
            self = .declareComplete(summary: summary)
        case "declare_stuck", "declareStuck":
            let reason = try Self.decodeReasonStuck(from: container)
            self = .declareStuck(reason: reason)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown action type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .respond(let message):
            try container.encode("respond", forKey: .type)
            try container.encode(message, forKey: .message)
        case .sendCommand(let terminalID, let command, let reason):
            try container.encode("send_command", forKey: .type)
            try container.encode(terminalID, forKey: .terminalID)
            try container.encode(command, forKey: .command)
            try container.encode(reason, forKey: .reason)
        case .askUser(let question):
            try container.encode("ask_user", forKey: .type)
            try container.encode(question, forKey: .question)
        case .declareComplete(let summary):
            try container.encode("declare_complete", forKey: .type)
            try container.encode(summary, forKey: .summary)
        case .declareStuck(let reason):
            try container.encode("declare_stuck", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String {
        if let string = try? container.decode(String.self, forKey: key) {
            return string
        }
        if let int = try? container.decode(Int.self, forKey: key) {
            return String(int)
        }
        if let double = try? container.decode(Double.self, forKey: key) {
            return String(double)
        }
        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: container.codingPath + [key], debugDescription: "Expected string-like value")
        )
    }

    private static func decodeReasonStuck(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        if let reason = try? container.decode(String.self, forKey: .reason) {
            return reason
        }
        return try container.decode(String.self, forKey: .reasonStuck)
    }
}

enum ConversationUIPhase: Equatable {
    case readyToStart
    case processing
    case awaitingApproval(command: String)
    case awaitingReply
    case choosingTarget(options: [ForemanTargetOption])
    case goalCompleted
    case chatting

    static func resolve(
        goal: String?,
        isRunning: Bool,
        status: AgentStatus,
        lastAction: AgentAction?,
        resolvedTarget: ForemanSidebarTarget? = nil
    ) -> Self {
        if case .completedGoal = resolvedTarget {
            return .goalCompleted
        }

        if case .ambiguous(let options) = resolvedTarget {
            return .choosingTarget(options: options)
        }

        if status == .waitingForUser {
            if case .sendCommand(_, let command, _) = lastAction {
                return .awaitingApproval(command: command)
            }
            return .awaitingReply
        }

        if case .terminalReply = resolvedTarget {
            return .awaitingReply
        }

        guard goal != nil else { return .readyToStart }

        if isRunning {
            switch status {
            case .observing, .planning, .executing:
                return .processing
            default:
                break
            }
        }

        return .chatting
    }
}

enum ConversationStatusDisplay: Equatable {
    case idle
    case observing
    case planning
    case executing
    case awaitingApproval
    case awaitingReply
    case chatting
    case complete
    case stuck

    static func resolve(status: AgentStatus, phase: ConversationUIPhase) -> Self {
        switch phase {
        case .awaitingApproval:
            return .awaitingApproval
        case .choosingTarget:
            return .awaitingReply
        case .awaitingReply:
            return .awaitingReply
        case .goalCompleted:
            return .complete
        case .chatting:
            return .chatting
        case .readyToStart:
            return .idle
        case .processing:
            switch status {
            case .observing:
                return .observing
            case .planning:
                return .planning
            case .executing:
                return .executing
            case .complete:
                return .complete
            case .stuck:
                return .stuck
            case .waitingForUser:
                return .awaitingReply
            case .idle:
                return .idle
            }
        }
    }

    var showsIterationCount: Bool {
        switch self {
        case .observing, .planning, .executing:
            return true
        default:
            return false
        }
    }
}

struct AgentStepResponse: Codable, Equatable, Sendable {
    let thought: String
    let action: AgentAction

    enum CodingKeys: String, CodingKey {
        case thought
        case action
    }

    init(thought: String, action: AgentAction) {
        self.thought = thought
        self.action = action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.thought = try container.decode(String.self, forKey: .thought)

        // Try nested action first
        if let action = try? container.decode(AgentAction.self, forKey: .action) {
            self.action = action
            return
        }

        // Fallback: action fields might be at top level
        self.action = try AgentAction(from: decoder)
    }
}
