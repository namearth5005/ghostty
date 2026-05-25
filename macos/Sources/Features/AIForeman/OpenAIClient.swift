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

struct OpenAIClient: ForemanLLMClient, Sendable {
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

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        let goal = narrationContext.goal ?? ""
        let mode = narrationContext.mode.rawValue
        let iterationCount = narrationContext.iterationCount
        let messages = narrationContext.messages
        let hiddenContext = narrationContext.hiddenContext
        let latestUserMessage = messages.last(where: { $0.role == .user })?.content ?? goal
        let activeTurn = latestUserMessage.isEmpty ? hiddenContext.last ?? "" : latestUserMessage

        let request = Request(
            model: plannerModel,
            instructions: Self.makeAgentStepInstructions(),
            input: [.user(Self.agentStepPrompt(
                goal: goal,
                latestUserMessage: latestUserMessage,
                activeTurn: activeTurn,
                mode: mode,
                iterationCount: iterationCount,
                messages: messages,
                hiddenContext: hiddenContext,
                understandings: understandings,
                workerSnapshots: workerSnapshots,
                overview: overview,
                terminals: terminals,
                lastOutcome: lastOutcome,
                using: encoder
            ))],
            maxOutputTokens: 1200
        )

        let payload = try await perform(request)
        return try Self.decodeJSON(AgentStepResponse.self, from: payload, decoder: decoder)
    }

    func draftAgentReply(
        narrationContext: ForemanNarrationContext,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse {
        let goal = narrationContext.goal ?? ""
        let messages = narrationContext.messages
        let hiddenContext = narrationContext.hiddenContext

        let request = Request(
            model: plannerModel,
            instructions: Self.replyDraftInstructions,
            input: [.user(Self.replyDraftPrompt(
                goal: goal,
                messages: messages,
                hiddenContext: hiddenContext,
                event: event,
                understandings: understandings,
                workerSnapshots: workerSnapshots,
                overview: overview,
                terminals: terminals,
                lastOutcome: lastOutcome,
                using: encoder
            ))],
            maxOutputTokens: 900
        )

        let payload = try await perform(request)
        return try Self.decodeJSON(AgentReplyDraftResponse.self, from: payload, decoder: decoder)
    }

    func agentStep(
        narrationContext: ForemanNarrationContext,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        return try await agentStep(
            narrationContext: narrationContext,
            terminals: terminals,
            understandings: [],
            workerSnapshots: [:],
            overview: Self.fallbackOverview(for: terminals),
            lastOutcome: lastOutcome
        )
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

    private static func makeAgentStepInstructions() -> String {
        """
        You are a terminal foreman narrator and router. You do not replace an active terminal-local worker's plan.
        Return JSON only. Do not wrap the JSON in markdown code blocks.
        Available action types (use exact snake_case strings): respond, send_command, ask_user, declare_complete, declare_stuck.
        Treat the latest user message as the active turn. Earlier goal text is session context only and may be superseded by a follow-up.
        Use structured terminal understanding as your primary context. Use raw terminal snapshots only as supporting evidence.
        If a terminal-local worker already supplied a structured next-step suggestion, do not invent a competing suggestion.
        Prefer summarizing progress, asking the user to resolve ambiguity, or giving project-level guidance.
        Treat Active turn as the current task. If Active turn is a reactive terminal event, handle that event as the current task.
        Use respond for plain conversational replies that do not require terminal actions or a blocking follow-up.
        Use ask_user only when you genuinely need information from the user before you can continue a task.
        For send_command, terminal_id must exactly match one of the terminal_id values from Terminal snapshots.
        When sending commands, prefer non-interactive flags (e.g., -y, --no-pager, --batch-mode) to avoid hanging.
        IMPORTANT: Some terminals are running AI agents (Kimi, Claude Code, Codex), not shell prompts.
        When an AI agent is waiting for text input (waitingText), send_command sends a raw message to the agent — NOT a shell command.
        Do NOT wrap agent messages in printf, echo, or any shell syntax. Send the raw text only.
        Do NOT echo text you see in the terminal output back to the agent.
        When an AI agent is waiting for text input, read the full terminal output to understand the conversation history and infer the user's goal.
        If the context is clear from the terminal history, generate an appropriate response directly.
        Only ask the user if the terminal history does not provide enough context to determine what to send next.
        """
    }

    private static let replyDraftInstructions = """
    You draft the next interactive reply for a human supervising AI agent terminals.
    Return JSON only. Do not wrap the JSON in markdown code blocks.
    Choose exactly one suggestion type: reply_to_agent, ask_human, or no_action.
    If a structured worker snapshot already includes a matching suggested reply or choice, follow that suggestion instead of inventing a competing one.
    Use reply_to_agent when terminal history gives enough context to send a useful raw message to the AI agent.
    Use ask_human when the AI agent needs a real goal or choice that is absent from terminal history.
    Use no_action only when the waiting text is duplicate, cosmetic, or not actionable.
    For reply_to_agent, terminal_id must exactly match one terminal_id from Terminal snapshots.
    A reply_to_agent message is raw text sent to Kimi, Claude Code, or Codex. Do not use shell syntax, printf, or echo.
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

    private static func agentStepPrompt(
        goal: String,
        latestUserMessage: String,
        activeTurn: String,
        mode: String,
        iterationCount: Int,
        messages: [ConversationMessage],
        hiddenContext: [String],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?,
        using encoder: JSONEncoder
    ) -> String {
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
        Active turn: \(activeTurn.isEmpty ? "none" : activeTurn)
        If Active turn is a reactive terminal event, handle that event as the current task.
        Mode: \(mode)
        Iteration: \(iterationCount)/20

        Conversation history:
        \(encode(messages, using: encoder))

        Hidden reactive context:
        \(encode(hiddenContext, using: encoder))

        Structured terminal overview:
        \(encode(overview, using: encoder))

        Structured terminal understandings:
        \(encode(understandings, using: encoder))

        Structured worker snapshots:
        \(encode(workerSnapshots, using: encoder))

        Terminal snapshots:
        \(encode(terminals, using: encoder))

        Last outcome (if any):
        \(lastOutcome.map { encode($0, using: encoder) } ?? "none")
        """
    }

    private static func replyDraftPrompt(
        goal: String,
        messages: [ConversationMessage],
        hiddenContext: [String],
        event: AgentNeedsAttentionEvent,
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?,
        using encoder: JSONEncoder
    ) -> String {
        """
        Return one JSON object with this exact shape:
        {
          "thought": "string",
          "suggestion": {
            "type": "reply_to_agent|ask_human|no_action",
            "terminal_id": "string (for reply_to_agent and ask_human)",
            "message": "string (raw reply to send, or human-facing question)",
            "reason": "string",
            "confidence": 0.0
          }
        }

        Session goal: \(goal.isEmpty ? "none" : goal)

        Current waiting-text event:
        \(encode(event, using: encoder))

        Conversation history:
        \(encode(messages, using: encoder))

        Hidden reactive context:
        \(encode(hiddenContext, using: encoder))

        Structured terminal overview:
        \(encode(overview, using: encoder))

        Structured terminal understandings:
        \(encode(understandings, using: encoder))

        Structured worker snapshots:
        \(encode(workerSnapshots, using: encoder))

        Terminal snapshots:
        \(encode(terminals, using: encoder))

        Last outcome (if any):
        \(lastOutcome.map { encode($0, using: encoder) } ?? "none")
        """
    }

    private static func fallbackOverview(for terminals: [TerminalSnapshot]) -> TerminalOverview {
        let primaryTerminalID = terminals.first?.terminalID
        let summary: String
        if terminals.isEmpty {
            summary = "No structured terminal overview is available yet."
        } else {
            summary = "Structured terminal understanding is not available yet for \(terminals.count) terminal(s)."
        }

        return TerminalOverview(
            summary: summary,
            changedTerminalIDs: terminals.map(\.terminalID),
            primaryTerminalID: primaryTerminalID
        )
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

        var directDecodeError: Error?
        do {
            return try decode(type, from: cleaned, decoder: decoder)
        } catch {
            directDecodeError = error
        }

        var extractedDecodeError: Error?
        if let extracted = extractJSONObject(from: cleaned) {
            do {
                return try decode(type, from: extracted, decoder: decoder)
            } catch {
                extractedDecodeError = error
            }
        }

        let preview = String(cleaned.prefix(200))
        let details = [directDecodeError, extractedDecodeError]
            .compactMap { $0?.localizedDescription }
            .joined(separator: " | ")
        let suffix = details.isEmpty ? "" : " Details: \(details)"
        throw OpenAIClientError.responseFailed(
            "JSON parse error: The data couldn't be read because it isn't in the correct format. Response preview: \(preview)\(suffix)"
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from text: String, decoder: JSONDecoder) throws -> T {
        guard let data = text.data(using: .utf8) else {
            throw OpenAIClientError.invalidResponse
        }
        return try decoder.decode(type, from: data)
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

struct URLSessionResponsesTransport: OpenAIResponsesTransport {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = URLSession(configuration: URLSessionResponsesTransport.makeConfiguration())) {
        self.session = session
    }

    private static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return config
    }

    func send(_ request: OpenAIClient.Request, apiKey: String) async throws -> String {
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)

        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performWithRetry(request: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        let envelope = try decoder.decode(OpenAIClient.ResponseEnvelope.self, from: data)
        if let error = envelope.error {
            throw OpenAIClientError.responseFailed(error.message)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAIClientError.responseFailed(mapStatusCode(httpResponse.statusCode, provider: "OpenAI"))
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
        throw lastError ?? OpenAIClientError.invalidResponse
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

struct MockResponsesTransport: OpenAIResponsesTransport {
    let payload: String

    func send(_ request: OpenAIClient.Request, apiKey: String) async throws -> String {
        payload
    }
}
