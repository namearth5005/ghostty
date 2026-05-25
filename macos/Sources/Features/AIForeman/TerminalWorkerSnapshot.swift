import Foundation

enum TerminalWorkerLifecycle: String, Codable, Equatable, Sendable {
    case idle
    case running
    case blocked
    case completed
    case failed
}

enum TerminalWorkerAttention: String, Codable, Equatable, Sendable {
    case none
    case replyRequired = "reply_required"
    case choiceRequired = "choice_required"
    case approvalRequired = "approval_required"
    case error
}

enum TerminalWorkerRuntimeFlag: String, Codable, Equatable, Sendable {
    case planning
}

enum TerminalWorkerSuggestionKind: String, Codable, Equatable, Sendable {
    case reply
    case command
    case choice
    case approval
    case foremanPrompt = "foreman_prompt"
}

enum TerminalWorkerSuggestionExecution: String, Codable, Equatable, Sendable {
    case manualOnly = "manual_only"
    case autonomousOK = "autonomous_ok"
}

struct TerminalWorkerSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let terminalID: String
    let workerSessionID: String
    let revision: Int
    let observedAt: Date
    let ttlMilliseconds: Int
    let workerGoal: String?
    let agent: AgentDescriptor
    let state: State
    let request: Request?
    let suggestions: [Suggestion]

    struct AgentDescriptor: Codable, Equatable, Sendable {
        let identity: AgentIdentity
    }

    struct State: Codable, Equatable, Sendable {
        let lifecycle: TerminalWorkerLifecycle
        let attention: TerminalWorkerAttention
        let summary: String
        let details: [String]
        let runtimeFlags: [TerminalWorkerRuntimeFlag]
    }

    struct Request: Codable, Equatable, Sendable {
        let id: String
        let kind: Kind
        let prompt: String
        let options: [Option]
    }

    struct Option: Codable, Equatable, Sendable {
        let id: String
        let label: String
        let recommended: Bool
    }

    struct Suggestion: Codable, Equatable, Sendable {
        let id: String
        let kind: TerminalWorkerSuggestionKind
        let title: String
        let payload: Payload
        let rationale: String
        let recommended: Bool
        let execution: TerminalWorkerSuggestionExecution
        let requestID: String?
    }

    enum Kind: String, Codable, Equatable, Sendable {
        case reply
        case choice
        case approval
        case command
    }

    enum Payload: Codable, Equatable, Sendable {
        case text(String)
        case command(String)
        case option(String)
        case approval(String)

        private enum CodingKeys: String, CodingKey {
            case kind
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            let value = try container.decode(String.self, forKey: .value)

            switch kind {
            case "text":
                self = .text(value)
            case "command":
                self = .command(value)
            case "option":
                self = .option(value)
            case "approval":
                self = .approval(value)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Unknown payload kind: \(kind)"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .text(let value):
                try container.encode("text", forKey: .kind)
                try container.encode(value, forKey: .value)
            case .command(let value):
                try container.encode("command", forKey: .kind)
                try container.encode(value, forKey: .value)
            case .option(let value):
                try container.encode("option", forKey: .kind)
                try container.encode(value, forKey: .value)
            case .approval(let value):
                try container.encode("approval", forKey: .kind)
                try container.encode(value, forKey: .value)
            }
        }
    }

    var recommendedSuggestion: Suggestion? {
        suggestions.first(where: \.recommended)
    }

    var attentionFingerprint: String {
        if let request {
            return "\(workerSessionID)|\(revision)|\(request.id)"
        }

        return "\(workerSessionID)|\(revision)"
    }
}
