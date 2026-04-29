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

    func agentStep(conversation: ForemanConversation, terminals: [TerminalSnapshot], lastOutcome: TerminalOutcomeReport?) async throws -> AgentStepResponse {
        let goal = await MainActor.run { conversation.goal ?? "" }
        let mode = await MainActor.run { conversation.mode.rawValue }
        let iterationCount = await MainActor.run { conversation.iterationCount }
        let messages = await MainActor.run { conversation.messages }
        let latestUserMessage = messages.last(where: { $0.role == .user })?.content ?? goal

        let request = Request(
            model: plannerModel,
            system: Self.agentStepInstructions,
            maxTokens: 1200,
            messages: [.user(Self.agentStepPrompt(
                goal: goal,
                latestUserMessage: latestUserMessage,
                mode: mode,
                iterationCount: iterationCount,
                messages: messages,
                terminals: terminals,
                lastOutcome: lastOutcome,
                using: encoder
            ))]
        )

        let payload = try await perform(request)
        return try Self.decodeJSON(AgentStepResponse.self, from: payload, decoder: decoder)
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

    private static let agentStepInstructions = """
    You are an autonomous terminal foreman. You observe terminal state, think step by step, and choose exactly ONE action.
    Return JSON only. Do not wrap the JSON in markdown code blocks.
    Available action types (use exact snake_case strings): respond, send_command, ask_user, declare_complete, declare_stuck.
    Treat the latest user message as the active turn. Earlier goal text is session context only and may be superseded by a follow-up.
    Use respond for plain conversational replies that do not require terminal actions or a blocking follow-up.
    Use ask_user only when you genuinely need information from the user before you can continue a task.
    For send_command, terminal_id must exactly match one of the terminal_id values from Terminal snapshots.
    When sending commands, prefer non-interactive flags (e.g., -y, --no-pager, --batch-mode) to avoid hanging.
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

    private static func agentStepPrompt(goal: String, latestUserMessage: String, mode: String, iterationCount: Int, messages: [ConversationMessage], terminals: [TerminalSnapshot], lastOutcome: TerminalOutcomeReport?, using encoder: JSONEncoder) -> String {
        """
        Return one JSON object with this exact shape:
        {
          "thought": "string",
          "action": {
            "type": "respond|send_command|ask_user|declare_complete|declare_stuck",
            "message": "string (for respond)",
            "terminal_id": "string (for send_command)",
            "command": "string (for send_command)",
            "reason": "string (for send_command)",
            "question": "string (for ask_user)",
            "summary": "string (for declare_complete)",
            "reason_stuck": "string (for declare_stuck)"
          }
        }

        Session goal: \(goal)
        Latest user message: \(latestUserMessage)
        Mode: \(mode)
        Iteration: \(iterationCount)/20

        Conversation history:
        \(encode(messages, using: encoder))

        Terminal snapshots:
        \(encode(terminals, using: encoder))

        Last outcome (if any):
        \(lastOutcome.map { encode($0, using: encoder) } ?? "none")
        """
    }

    private static func encode<T: Encodable>(_ value: T, using encoder: JSONEncoder) -> String {
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return string
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from payload: String, decoder: JSONDecoder) throws -> T {
        var cleaned = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code block wrappers
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[firstNewline...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let decoded: T = decode(type, from: cleaned, decoder: decoder) {
            return decoded
        }

        if let extracted = extractJSONObject(from: cleaned),
           let decoded: T = decode(type, from: extracted, decoder: decoder) {
            return decoded
        }

        let preview = String(cleaned.prefix(200))
        throw AnthropicClientError.responseFailed("JSON parse error: The data couldn't be read because it isn't in the correct format. Response preview: \(preview)")
    }

    private static func decode<T: Decodable>(_ type: T.Type, from text: String, decoder: JSONDecoder) -> T? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in text[start...].indices {
            let char = text[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if char == "\\" {
                isEscaped = true
                continue
            }

            if char == "\"" {
                isInsideString.toggle()
                continue
            }

            if isInsideString { continue }

            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }

        return nil
    }
}

struct URLSessionAnthropicTransport: AnthropicMessagesTransport {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = URLSession(configuration: URLSessionAnthropicTransport.makeConfiguration())) {
        self.session = session
    }

    private static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return config
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

        let (data, response) = try await performWithRetry(request: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicClientError.invalidResponse
        }

        let envelope = try decoder.decode(AnthropicClient.ResponseEnvelope.self, from: data)
        if let error = envelope.error {
            throw AnthropicClientError.responseFailed(error.message)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AnthropicClientError.responseFailed(mapStatusCode(httpResponse.statusCode, provider: "Anthropic"))
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

    private func performWithRetry(request: URLRequest, attempts: Int = 2) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        throw lastError ?? AnthropicClientError.invalidResponse
    }

    private func mapStatusCode(_ code: Int, provider: String) -> String {
        switch code {
        case 401: return "\(provider) API key is invalid or expired."
        case 429: return "\(provider) rate limit reached. Please wait a moment."
        case 500...599: return "\(provider) server error (status \(code)). Try again shortly."
        default: return "\(provider) request failed with status \(code)."
        }
    }
}

struct MockAnthropicTransport: AnthropicMessagesTransport {
    let payload: String

    func send(_ request: AnthropicClient.Request, apiKey: String) async throws -> String {
        payload
    }
}
