import Foundation

enum AgentInteractionContext: Codable, Equatable, Sendable {
    case none
    case running(stepDescription: String?)
    case waitingApproval(description: String, tool: String?)
    case waitingChoice(question: String, options: [String])
    case waitingText(question: String?)
    case completed(summary: String?)
    case error(description: String)

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
        case .running(let stepDescription): return stepDescription
        case .waitingApproval(let description, _): return description
        case .waitingChoice(let question, _): return question
        case .waitingText(let question): return question
        case .completed(let summary): return summary
        case .error(let description): return description
        }
    }

    var detailString: String? {
        switch self {
        case .none: return nil
        case .running: return nil
        case .waitingApproval(_, let tool): return tool
        case .waitingChoice(_, let options): return "\(options.count) options"
        case .waitingText: return nil
        case .completed: return nil
        case .error: return nil
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "none":
            self = .none
        case "running":
            let stepDescription = try container.decodeIfPresent(String.self, forKey: .stepDescription)
            self = .running(stepDescription: stepDescription)
        case "waitingApproval":
            let description = try container.decode(String.self, forKey: .description)
            let tool = try container.decodeIfPresent(String.self, forKey: .tool)
            self = .waitingApproval(description: description, tool: tool)
        case "waitingChoice":
            let question = try container.decode(String.self, forKey: .question)
            let options = try container.decode([String].self, forKey: .options)
            self = .waitingChoice(question: question, options: options)
        case "waitingText":
            let question = try container.decodeIfPresent(String.self, forKey: .question)
            self = .waitingText(question: question)
        case "completed":
            let summary = try container.decodeIfPresent(String.self, forKey: .summary)
            self = .completed(summary: summary)
        case "error":
            let description = try container.decode(String.self, forKey: .description)
            self = .error(description: description)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .kind)
        case .running(let stepDescription):
            try container.encode("running", forKey: .kind)
            try container.encodeIfPresent(stepDescription, forKey: .stepDescription)
        case .waitingApproval(let description, let tool):
            try container.encode("waitingApproval", forKey: .kind)
            try container.encode(description, forKey: .description)
            try container.encodeIfPresent(tool, forKey: .tool)
        case .waitingChoice(let question, let options):
            try container.encode("waitingChoice", forKey: .kind)
            try container.encode(question, forKey: .question)
            try container.encode(options, forKey: .options)
        case .waitingText(let question):
            try container.encode("waitingText", forKey: .kind)
            try container.encodeIfPresent(question, forKey: .question)
        case .completed(let summary):
            try container.encode("completed", forKey: .kind)
            try container.encodeIfPresent(summary, forKey: .summary)
        case .error(let description):
            try container.encode("error", forKey: .kind)
            try container.encode(description, forKey: .description)
        }
    }
}
