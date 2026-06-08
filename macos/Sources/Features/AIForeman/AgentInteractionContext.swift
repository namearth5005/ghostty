import Foundation

enum AgentInteractionContext: Codable, Equatable, Sendable {
    case none
    case running(stepDescription: String?, sessionID: String?, revision: Int?)
    case waitingApproval(
        description: String,
        tool: String?,
        requestID: String?,
        sessionID: String?,
        revision: Int?,
        isPlanning: Bool
    )
    case waitingChoice(
        question: String,
        options: [String],
        requestID: String?,
        sessionID: String?,
        revision: Int?,
        isPlanning: Bool
    )
    case waitingText(
        question: String?,
        requestID: String?,
        sessionID: String?,
        revision: Int?,
        isPlanning: Bool
    )
    case completed(summary: String?, sessionID: String?, revision: Int?)
    case error(description: String, sessionID: String?, revision: Int?)

    static func running(stepDescription: String?) -> Self {
        .running(stepDescription: stepDescription, sessionID: nil, revision: nil)
    }

    static func waitingApproval(description: String, tool: String?) -> Self {
        .waitingApproval(
            description: description,
            tool: tool,
            requestID: nil,
            sessionID: nil,
            revision: nil,
            isPlanning: false
        )
    }

    static func waitingChoice(question: String, options: [String]) -> Self {
        .waitingChoice(
            question: question,
            options: options,
            requestID: nil,
            sessionID: nil,
            revision: nil,
            isPlanning: false
        )
    }

    static func waitingText(question: String?) -> Self {
        .waitingText(
            question: question,
            requestID: nil,
            sessionID: nil,
            revision: nil,
            isPlanning: false
        )
    }

    static func completed(summary: String?) -> Self {
        .completed(summary: summary, sessionID: nil, revision: nil)
    }

    static func error(description: String) -> Self {
        .error(description: description, sessionID: nil, revision: nil)
    }

    // MARK: - Display helpers

    var typeString: String? {
        switch self {
        case .none: return nil
        case .running: return "running"
        case .waitingApproval: return "waitingApproval"
        case .waitingChoice: return "waitingChoice"
        case .waitingText: return "waitingText"
        case .completed: return "completed"
        case .error: return "error"
        }
    }

    var titleString: String? {
        switch self {
        case .none: return nil
        case .running: return "Working..."
        case .waitingApproval: return "Needs your approval"
        case .waitingChoice: return "Choose an option"
        case .waitingText: return "Waiting for your reply"
        case .completed: return "Done"
        case .error: return "Hit an error"
        }
    }

    var descriptionString: String? {
        switch self {
        case .none: return nil
        case .running(let stepDescription, _, _): return stepDescription
        case .waitingApproval(let description, _, _, _, _, _): return description
        case .waitingChoice(let question, _, _, _, _, _): return question
        case .waitingText(let question, _, _, _, _): return question
        case .completed(let summary, _, _): return summary
        case .error(let description, _, _): return description
        }
    }

    var detailString: String? {
        switch self {
        case .none: return nil
        case .running: return nil
        case .waitingApproval(_, let tool, _, _, _, _): return tool
        case .waitingChoice(_, let options, _, _, _, _): return "\(options.count) options"
        case .waitingText: return nil
        case .completed: return nil
        case .error: return nil
        }
    }

    var optionsArray: [String]? {
        switch self {
        case .waitingChoice(_, let options, _, _, _, _): return options
        default: return nil
        }
    }

    var requestID: String? {
        switch self {
        case .waitingApproval(_, _, let requestID, _, _, _): return requestID
        case .waitingChoice(_, _, let requestID, _, _, _): return requestID
        case .waitingText(_, let requestID, _, _, _): return requestID
        default: return nil
        }
    }

    var sessionID: String? {
        switch self {
        case .none: return nil
        case .running(_, let sessionID, _): return sessionID
        case .waitingApproval(_, _, _, let sessionID, _, _): return sessionID
        case .waitingChoice(_, _, _, let sessionID, _, _): return sessionID
        case .waitingText(_, _, let sessionID, _, _): return sessionID
        case .completed(_, let sessionID, _): return sessionID
        case .error(_, let sessionID, _): return sessionID
        }
    }

    var revision: Int? {
        switch self {
        case .none: return nil
        case .running(_, _, let revision): return revision
        case .waitingApproval(_, _, _, _, let revision, _): return revision
        case .waitingChoice(_, _, _, _, let revision, _): return revision
        case .waitingText(_, _, _, let revision, _): return revision
        case .completed(_, _, let revision): return revision
        case .error(_, _, let revision): return revision
        }
    }

    var isPlanning: Bool {
        switch self {
        case .waitingApproval(_, _, _, _, _, let isPlanning): return isPlanning
        case .waitingChoice(_, _, _, _, _, let isPlanning): return isPlanning
        case .waitingText(_, _, _, _, let isPlanning): return isPlanning
        default: return false
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case kind
        case stepDescription
        case description
        case tool
        case question
        case options
        case summary
        case requestID
        case sessionID
        case revision
        case isPlanning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "none":
            self = .none
        case "running":
            let stepDescription = try container.decodeIfPresent(String.self, forKey: .stepDescription)
            let sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            let revision = try container.decodeIfPresent(Int.self, forKey: .revision)
            self = .running(stepDescription: stepDescription, sessionID: sessionID, revision: revision)
        case "waitingApproval":
            let description = try container.decode(String.self, forKey: .description)
            let tool = try container.decodeIfPresent(String.self, forKey: .tool)
            let requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
            let sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            let revision = try container.decodeIfPresent(Int.self, forKey: .revision)
            let isPlanning = try container.decodeIfPresent(Bool.self, forKey: .isPlanning) ?? false
            self = .waitingApproval(
                description: description,
                tool: tool,
                requestID: requestID,
                sessionID: sessionID,
                revision: revision,
                isPlanning: isPlanning
            )
        case "waitingChoice":
            let question = try container.decode(String.self, forKey: .question)
            let options = try container.decode([String].self, forKey: .options)
            let requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
            let sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            let revision = try container.decodeIfPresent(Int.self, forKey: .revision)
            let isPlanning = try container.decodeIfPresent(Bool.self, forKey: .isPlanning) ?? false
            self = .waitingChoice(
                question: question,
                options: options,
                requestID: requestID,
                sessionID: sessionID,
                revision: revision,
                isPlanning: isPlanning
            )
        case "waitingText":
            let question = try container.decodeIfPresent(String.self, forKey: .question)
            let requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
            let sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            let revision = try container.decodeIfPresent(Int.self, forKey: .revision)
            let isPlanning = try container.decodeIfPresent(Bool.self, forKey: .isPlanning) ?? false
            self = .waitingText(
                question: question,
                requestID: requestID,
                sessionID: sessionID,
                revision: revision,
                isPlanning: isPlanning
            )
        case "completed":
            let summary = try container.decodeIfPresent(String.self, forKey: .summary)
            let sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            let revision = try container.decodeIfPresent(Int.self, forKey: .revision)
            self = .completed(summary: summary, sessionID: sessionID, revision: revision)
        case "error":
            let description = try container.decode(String.self, forKey: .description)
            let sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            let revision = try container.decodeIfPresent(Int.self, forKey: .revision)
            self = .error(description: description, sessionID: sessionID, revision: revision)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .kind)
        case .running(let stepDescription, let sessionID, let revision):
            try container.encode("running", forKey: .kind)
            try container.encodeIfPresent(stepDescription, forKey: .stepDescription)
            try container.encodeIfPresent(sessionID, forKey: .sessionID)
            try container.encodeIfPresent(revision, forKey: .revision)
        case .waitingApproval(let description, let tool, let requestID, let sessionID, let revision, let isPlanning):
            try container.encode("waitingApproval", forKey: .kind)
            try container.encode(description, forKey: .description)
            try container.encodeIfPresent(tool, forKey: .tool)
            try container.encodeIfPresent(requestID, forKey: .requestID)
            try container.encodeIfPresent(sessionID, forKey: .sessionID)
            try container.encodeIfPresent(revision, forKey: .revision)
            try container.encode(isPlanning, forKey: .isPlanning)
        case .waitingChoice(let question, let options, let requestID, let sessionID, let revision, let isPlanning):
            try container.encode("waitingChoice", forKey: .kind)
            try container.encode(question, forKey: .question)
            try container.encode(options, forKey: .options)
            try container.encodeIfPresent(requestID, forKey: .requestID)
            try container.encodeIfPresent(sessionID, forKey: .sessionID)
            try container.encodeIfPresent(revision, forKey: .revision)
            try container.encode(isPlanning, forKey: .isPlanning)
        case .waitingText(let question, let requestID, let sessionID, let revision, let isPlanning):
            try container.encode("waitingText", forKey: .kind)
            try container.encodeIfPresent(question, forKey: .question)
            try container.encodeIfPresent(requestID, forKey: .requestID)
            try container.encodeIfPresent(sessionID, forKey: .sessionID)
            try container.encodeIfPresent(revision, forKey: .revision)
            try container.encode(isPlanning, forKey: .isPlanning)
        case .completed(let summary, let sessionID, let revision):
            try container.encode("completed", forKey: .kind)
            try container.encodeIfPresent(summary, forKey: .summary)
            try container.encodeIfPresent(sessionID, forKey: .sessionID)
            try container.encodeIfPresent(revision, forKey: .revision)
        case .error(let description, let sessionID, let revision):
            try container.encode("error", forKey: .kind)
            try container.encode(description, forKey: .description)
            try container.encodeIfPresent(sessionID, forKey: .sessionID)
            try container.encodeIfPresent(revision, forKey: .revision)
        }
    }
}
