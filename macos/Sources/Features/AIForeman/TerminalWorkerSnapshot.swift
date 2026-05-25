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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case terminalID = "terminal_id"
        case workerSessionID = "worker_session_id"
        case revision
        case observedAt = "observed_at"
        case ttlMilliseconds = "ttl_ms"
        case workerGoal = "worker_goal"
        case agent
        case state
        case request
        case suggestions
    }

    struct AgentDescriptor: Codable, Equatable, Sendable {
        let identity: AgentIdentity
    }

    struct State: Codable, Equatable, Sendable {
        let lifecycle: TerminalWorkerLifecycle
        let attention: TerminalWorkerAttention
        let summary: String
        let details: [String]
        let runtimeFlags: [TerminalWorkerRuntimeFlag]

        private enum CodingKeys: String, CodingKey {
            case lifecycle
            case attention
            case summary
            case details
            case runtimeFlags = "runtime_flags"
        }
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
        let title: String
        let payload: Payload
        let rationale: String
        let recommended: Bool
        let execution: TerminalWorkerSuggestionExecution
        let requestID: String?

        var kind: TerminalWorkerSuggestionKind { payload.suggestionKind }

        init(
            id: String,
            kind: TerminalWorkerSuggestionKind,
            title: String,
            payload: Payload,
            rationale: String,
            recommended: Bool,
            execution: TerminalWorkerSuggestionExecution,
            requestID: String?
        ) {
            precondition(
                kind == payload.suggestionKind,
                "Suggestion kind \(kind) does not match payload kind \(payload.suggestionKind)."
            )
            self.id = id
            self.title = title
            self.payload = payload
            self.rationale = rationale
            self.recommended = recommended
            self.execution = execution
            self.requestID = requestID
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case kind
            case title
            case payload
            case rationale
            case recommended
            case execution
            case requestID = "request_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let id = try container.decode(String.self, forKey: .id)
            let kind = try container.decode(TerminalWorkerSuggestionKind.self, forKey: .kind)
            let title = try container.decode(String.self, forKey: .title)
            let payload = try container.decode(Payload.self, forKey: .payload)
            let rationale = try container.decode(String.self, forKey: .rationale)
            let recommended = try container.decode(Bool.self, forKey: .recommended)
            let execution = try container.decode(TerminalWorkerSuggestionExecution.self, forKey: .execution)
            let requestID = try container.decodeIfPresent(String.self, forKey: .requestID)

            guard kind == payload.suggestionKind else {
                throw DecodingError.dataCorruptedError(
                    forKey: .payload,
                    in: container,
                    debugDescription: "Suggestion kind \(kind) does not match payload kind \(payload.suggestionKind)."
                )
            }

            self.init(
                id: id,
                kind: kind,
                title: title,
                payload: payload,
                rationale: rationale,
                recommended: recommended,
                execution: execution,
                requestID: requestID
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(kind, forKey: .kind)
            try container.encode(title, forKey: .title)
            try container.encode(payload, forKey: .payload)
            try container.encode(rationale, forKey: .rationale)
            try container.encode(recommended, forKey: .recommended)
            try container.encode(execution, forKey: .execution)
            try container.encodeIfPresent(requestID, forKey: .requestID)
        }
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
        case foremanPrompt(String)

        var suggestionKind: TerminalWorkerSuggestionKind {
            switch self {
            case .text:
                return .reply
            case .command:
                return .command
            case .option:
                return .choice
            case .approval:
                return .approval
            case .foremanPrompt:
                return .foremanPrompt
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let object = try container.decode([String: String].self)

            guard object.count == 1, let (key, value) = object.first else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Payload must contain exactly one key."
                )
            }

            switch key {
            case "text":
                self = .text(value)
            case "command":
                self = .command(value)
            case "option":
                self = .option(value)
            case "approval":
                self = .approval(value)
            case "foreman_prompt":
                self = .foremanPrompt(value)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown payload kind: \(key)"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(["text": value])
            case .command(let value):
                try container.encode(["command": value])
            case .option(let value):
                try container.encode(["option": value])
            case .approval(let value):
                try container.encode(["approval": value])
            case .foremanPrompt(let value):
                try container.encode(["foreman_prompt": value])
            }
        }
    }

    var requestSuggestions: [Suggestion] {
        guard let request else {
            return suggestions
        }

        return suggestions.filter { suggestion in
            suggestion.requestID == nil || suggestion.requestID == request.id
        }
    }

    var recommendedSuggestion: Suggestion? {
        requestSuggestions.first(where: \.recommended)
    }

    var preferredSuggestion: Suggestion? {
        recommendedSuggestion ?? requestSuggestions.first
    }

    var attentionFingerprint: String {
        if let request {
            return "\(workerSessionID)|\(revision)|\(request.id)"
        }

        return "\(workerSessionID)|\(revision)"
    }
}
