import Foundation

protocol AnthropicMessagesTransport: Sendable {
    func send(_ request: AnthropicClient.Request, apiKey: String) async throws -> String
}

enum AnthropicClientError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case responseFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "ANTHROPIC_API_KEY is not configured."
        case .invalidResponse:
            return "The Anthropic response could not be decoded."
        case .responseFailed(let message):
            return message
        case .emptyOutput:
            return "The Anthropic response did not contain any text output."
        }
    }
}

struct AnthropicClient: ForemanLLMClient, Sendable {
    struct Request: Encodable, Sendable {
        let model: String
        let system: String
        let maxTokens: Int
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model
            case system
            case maxTokens = "max_tokens"
            case messages
        }
    }

    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }

    struct ResponseEnvelope: Decodable {
        struct ContentItem: Decodable {
            let type: String
            let text: String?
        }

        struct APIError: Decodable {
            let message: String
        }

        let content: [ContentItem]?
        let error: APIError?
    }

    private let apiKey: String
    private let summaryModel: String
    private let plannerModel: String
    private let transport: any AnthropicMessagesTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        apiKey: String = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "",
        summaryModel: String = ProcessInfo.processInfo.environment["ANTHROPIC_FOREMAN_SUMMARY_MODEL"] ?? "claude-sonnet-4-20250514",
        plannerModel: String = ProcessInfo.processInfo.environment["ANTHROPIC_FOREMAN_PLANNER_MODEL"] ?? "claude-sonnet-4-20250514",
        transport: any AnthropicMessagesTransport = URLSessionAnthropicTransport()
    ) {
        self.apiKey = apiKey
        self.summaryModel = summaryModel
        self.plannerModel = plannerModel
        self.transport = transport

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        let request = Request(
            model: summaryModel,
            system: Self.summaryInstructions,
            maxTokens: 500,
            messages: [.user(Self.summaryPrompt(for: snapshot, using: encoder))]
        )

        let payload = try await perform(request)
        return try decoder.decode(TerminalSummary.self, from: Data(payload.utf8))
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        let request = Request(
            model: plannerModel,
            system: Self.plannerInstructions,
            maxTokens: 800,
            messages: [.user(Self.plannerPrompt(instruction: instruction, summaries: summaries, using: encoder))]
        )

        let payload = try await perform(request)
        return try decoder.decode(DispatchPlan.self, from: Data(payload.utf8))
    }

    private func perform(_ request: Request) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AnthropicClientError.missingAPIKey
        }

        return try await transport.send(request, apiKey: apiKey)
    }
}

extension AnthropicClient.Message {
    static func user(_ text: String) -> Self {
        Self(role: "user", content: text)
    }
}

extension AnthropicClient {
    private static let summaryInstructions = """
    You summarize terminal state for a human coordinating multiple terminal sessions.
    Return JSON only. Do not wrap the JSON in markdown.
    """

    private static let plannerInstructions = """
    You coordinate multiple terminal sessions from their summaries.
    Return JSON only. Only draft messages for terminals that need a next step.
    """

    private static func summaryPrompt(for snapshot: TerminalSnapshot, using encoder: JSONEncoder) -> String {
        """
        Return one JSON object with this exact shape:
        {
          "terminal_id": "string",
          "summary": "string",
          "state": "active|blocked|waiting|idle|unsupported",
          "confidence": 0.0,
          "needs_user_attention": true,
          "suggested_next_step": "string"
        }

        Snapshot JSON:
        \(encode(snapshot, using: encoder))
        """
    }

    private static func plannerPrompt(
        instruction: String,
        summaries: [TerminalSummary],
        using encoder: JSONEncoder
    ) -> String {
        """
        Return one JSON object with this exact shape:
        {
          "plan_summary": "string",
          "drafts": [
            {
              "terminal_id": "string",
              "reason": "string",
              "message": "string"
            }
          ]
        }

        User instruction:
        \(instruction)

        Terminal summaries JSON:
        \(encode(summaries, using: encoder))
        """
    }

    private static func encode<T: Encodable>(_ value: T, using encoder: JSONEncoder) -> String {
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return string
    }
}

struct URLSessionAnthropicTransport: AnthropicMessagesTransport {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: AnthropicClient.Request, apiKey: String) async throws -> String {
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)

        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicClientError.invalidResponse
        }

        let envelope = try decoder.decode(AnthropicClient.ResponseEnvelope.self, from: data)
        if let error = envelope.error {
            throw AnthropicClientError.responseFailed(error.message)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AnthropicClientError.responseFailed("Anthropic request failed with status \(httpResponse.statusCode).")
        }

        let text = envelope.content?
            .compactMap { item in
                guard item.type == "text" else { return nil }
                return item.text
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            throw AnthropicClientError.emptyOutput
        }

        return text
    }
}

struct MockAnthropicTransport: AnthropicMessagesTransport {
    let payload: String

    func send(_ request: AnthropicClient.Request, apiKey: String) async throws -> String {
        payload
    }
}
