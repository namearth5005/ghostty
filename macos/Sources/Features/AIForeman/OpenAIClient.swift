import Foundation

protocol OpenAIResponsesTransport: Sendable {
    func send(_ request: OpenAIClient.Request, apiKey: String) async throws -> String
}

enum OpenAIClientError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case responseFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OPENAI_API_KEY is not configured."
        case .invalidResponse:
            return "The OpenAI response could not be decoded."
        case .responseFailed(let message):
            return message
        case .emptyOutput:
            return "The OpenAI response did not contain any text output."
        }
    }
}

struct OpenAIClient: Sendable {
    struct Request: Encodable, Sendable {
        let model: String
        let instructions: String
        let input: [InputMessage]
        let maxOutputTokens: Int

        enum CodingKeys: String, CodingKey {
            case model
            case instructions
            case input
            case maxOutputTokens = "max_output_tokens"
        }
    }

    struct InputMessage: Encodable, Sendable {
        let role: String
        let content: [InputContent]
    }

    struct InputContent: Encodable, Sendable {
        let type: String
        let text: String

        static func text(_ text: String) -> Self {
            Self(type: "input_text", text: text)
        }
    }

    struct ResponseEnvelope: Decodable {
        struct OutputItem: Decodable {
            struct ContentItem: Decodable {
                let type: String
                let text: String?
            }

            let content: [ContentItem]?
        }

        struct APIError: Decodable {
            let message: String
        }

        let outputText: String?
        let output: [OutputItem]?
        let error: APIError?

        enum CodingKeys: String, CodingKey {
            case outputText = "output_text"
            case output
            case error
        }
    }

    private let apiKey: String
    private let summaryModel: String
    private let plannerModel: String
    private let transport: any OpenAIResponsesTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        apiKey: String = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
        summaryModel: String = ProcessInfo.processInfo.environment["OPENAI_FOREMAN_SUMMARY_MODEL"] ?? "gpt-5.4-mini",
        plannerModel: String = ProcessInfo.processInfo.environment["OPENAI_FOREMAN_PLANNER_MODEL"] ?? "gpt-5.4",
        transport: any OpenAIResponsesTransport = URLSessionResponsesTransport()
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
            instructions: Self.summaryInstructions,
            input: [.user(Self.summaryPrompt(for: snapshot, using: encoder))],
            maxOutputTokens: 500
        )

        let payload = try await perform(request)
        return try decoder.decode(TerminalSummary.self, from: Data(payload.utf8))
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        let request = Request(
            model: plannerModel,
            instructions: Self.plannerInstructions,
            input: [.user(Self.plannerPrompt(instruction: instruction, summaries: summaries, using: encoder))],
            maxOutputTokens: 800
        )

        let payload = try await perform(request)
        return try decoder.decode(DispatchPlan.self, from: Data(payload.utf8))
    }

    private func perform(_ request: Request) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        return try await transport.send(request, apiKey: apiKey)
    }
}

extension OpenAIClient.InputMessage {
    static func user(_ text: String) -> Self {
        Self(role: "user", content: [.text(text)])
    }
}

extension OpenAIClient {
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

struct URLSessionResponsesTransport: OpenAIResponsesTransport {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: OpenAIClient.Request, apiKey: String) async throws -> String {
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)

        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        let envelope = try decoder.decode(OpenAIClient.ResponseEnvelope.self, from: data)
        if let error = envelope.error {
            throw OpenAIClientError.responseFailed(error.message)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAIClientError.responseFailed("OpenAI request failed with status \(httpResponse.statusCode).")
        }

        if let outputText = envelope.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputText.isEmpty {
            return outputText
        }

        let fallback = envelope.output?
            .flatMap { $0.content ?? [] }
            .compactMap { item in
                guard item.type == "output_text" else { return nil }
                return item.text
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let fallback, !fallback.isEmpty else {
            throw OpenAIClientError.emptyOutput
        }

        return fallback
    }
}

struct MockResponsesTransport: OpenAIResponsesTransport {
    let payload: String

    func send(_ request: OpenAIClient.Request, apiKey: String) async throws -> String {
        payload
    }
}
