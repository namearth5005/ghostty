import Foundation
import Testing
@testable import Ghostty

struct ForemanServiceTests {
    @Test
    func plannerBuildsDraftsFromSummaries() async throws {
        let transport = MockResponsesTransport(
            payload: """
            {"plan_summary":"Two terminals need input.","drafts":[{"terminal_id":"term-1","reason":"Blocked test run.","message":"Rerun the failing auth test and explain the failure briefly."}]}
            """
        )
        let service = ForemanService(client: OpenAIClient(apiKey: "test-key", transport: transport))

        let result = try await service.planDispatch(
            instruction: "Ask blocked terminals to rerun the failing tests.",
            summaries: [
                .init(
                    terminalID: "term-1",
                    summary: "Blocked on auth test",
                    state: "blocked",
                    confidence: 0.9,
                    needsUserAttention: true,
                    suggestedNextStep: "rerun auth test"
                )
            ]
        )

        #expect(result.drafts.count == 1)
        #expect(result.drafts[0].terminalID == "term-1")
        #expect(result.planSummary == "Two terminals need input.")
    }

    @Test
    func openAIClientAgentStepExtractsWrappedJSON() async throws {
        let transport = MockResponsesTransport(
            payload: """
            Here is the next action.
            {"thought":"The previous command was mistyped.","action":{"type":"send_command","terminal_id":"term-1","command":"find . -print","reason":"Retry with the correct command."}}
            """
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        await MainActor.run {
            conversation.start(goal: "list all files", mode: .interactive)
        }

        let response = try await client.agentStep(
            conversation: conversation,
            terminals: [
                .makePreview(
                    terminalID: "term-1",
                    windowID: "win-1",
                    tabID: "tab-1",
                    title: "shell",
                    cwd: "/tmp/project",
                    isFocused: true,
                    visibleText: "$ ",
                    recentScrollbackLines: [],
                    lastInputPreview: "hfind . -print"
                ),
            ],
            lastOutcome: nil
        )

        #expect(response.thought == "The previous command was mistyped.")
        #expect(response.action == .sendCommand(
            terminalID: "term-1",
            command: "find . -print",
            reason: "Retry with the correct command."
        ))
    }

    @Test
    func openAIPromptIncludesHiddenReactiveContext() async throws {
        let transport = RecordingResponsesTransport(
            payload: """
            {"thought":"Using hidden context.","action":{"type":"respond","message":"Kimi is waiting for input."}}
            """
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        await MainActor.run {
            conversation.start(goal: "watch Kimi", mode: .interactive)
            conversation.addHiddenContext("Kimi in terminal term-1 is waiting for text input.")
        }

        _ = try await client.agentStep(
            conversation: conversation,
            terminals: sampleSnapshots(),
            understandings: [],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        let request = try #require(await transport.lastRequest)
        let prompt = request.input[0].content[0].text
        #expect(prompt.contains("Hidden reactive context:"))
        #expect(prompt.contains("Kimi in terminal term-1 is waiting for text input."))
    }

    @Test
    func openAIPromptPromotesReactiveContextWhenNoUserGoalExists() async throws {
        let transport = RecordingResponsesTransport(
            payload: """
            {"thought":"Drafting a reply for Kimi.","action":{"type":"send_command","terminal_id":"term-1","command":"Read the README and summarize the project.","reason":"Kimi asked what to do next."}}
            """
        )
        let client = OpenAIClient(apiKey: "test-key", transport: transport)
        let conversation = await MainActor.run { ForemanConversation() }
        await MainActor.run {
            conversation.addHiddenContext(
                "Kimi in terminal term-1 is waiting for text input.\n\nRecent output:\nWhat would you like me to do here?"
            )
        }

        _ = try await client.agentStep(
            conversation: conversation,
            terminals: sampleSnapshots(),
            understandings: [],
            overview: .init(summary: "term-1 waiting", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1"),
            lastOutcome: nil
        )

        let request = try #require(await transport.lastRequest)
        let prompt = request.input[0].content[0].text
        #expect(prompt.contains("Active turn:"))
        #expect(prompt.contains("Kimi in terminal term-1 is waiting for text input."))
        #expect(prompt.contains("If Active turn is a reactive terminal event, handle that event as the current task."))
    }

    @Test
    func serviceForwardsStructuredUnderstandingsToClient() async throws {
        let client = RecordingForemanClient()
        let service = ForemanService(client: client)
        let conversation = await MainActor.run { ForemanConversation() }
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .failed,
            shortExplanation: "The terminal failed.",
            lastMeaningfulEvent: "error: module not found",
            importantDetails: ["module not found"],
            suggestedNextActions: []
        )
        let overview = TerminalOverview(
            summary: "term-1 failed",
            changedTerminalIDs: ["term-1"],
            primaryTerminalID: "term-1"
        )

        _ = try await service.agentStep(
            conversation: conversation,
            terminals: sampleSnapshots(),
            understandings: [understanding],
            overview: overview,
            lastOutcome: nil
        )

        let recorded = await client.lastUnderstandings
        #expect(recorded == [understanding])
    }

    @Test
    func serviceUsesProtocolFallbackForLegacyClients() async throws {
        let client = LegacyRecordingForemanClient()
        let service = ForemanService(client: client)
        let conversation = await MainActor.run { ForemanConversation() }
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .failed,
            shortExplanation: "The terminal failed.",
            lastMeaningfulEvent: "error: module not found",
            importantDetails: ["module not found"],
            suggestedNextActions: []
        )
        let overview = TerminalOverview(
            summary: "term-1 failed",
            changedTerminalIDs: ["term-1"],
            primaryTerminalID: "term-1"
        )

        _ = try await service.agentStep(
            conversation: conversation,
            terminals: sampleSnapshots(),
            understandings: [understanding],
            overview: overview,
            lastOutcome: nil
        )

        let forwarded = await client.didUseLegacyPath()
        #expect(forwarded == true)
    }
}

@MainActor
private func sampleSnapshots() -> [TerminalSnapshot] {
    [
        TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "$ ",
            recentScrollbackLines: [],
            lastInputPreview: "hfind . -print"
        ),
    ]
}

private actor RecordingForemanClient: ForemanLLMClient {
    private(set) var lastUnderstandings: [TerminalUnderstanding] = []

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw RecordingForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw RecordingForemanClientError.unexpectedCall
    }

    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        lastUnderstandings = understandings
        return try makeStepResponse(
            thought: "Answering from structured context.",
            action: .respond(message: overview.summary)
        )
    }

    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        throw RecordingForemanClientError.unexpectedCall
    }
}

private actor LegacyRecordingForemanClient: ForemanLLMClient {
    private var legacyCallCount = 0

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        throw RecordingForemanClientError.unexpectedCall
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        throw RecordingForemanClientError.unexpectedCall
    }

    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        legacyCallCount += 1
        return try makeStepResponse(
            thought: "Falling back to the legacy path.",
            action: .respond(message: "legacy")
        )
    }

    func didUseLegacyPath() -> Bool {
        legacyCallCount == 1
    }
}

private actor RecordingResponsesTransport: OpenAIResponsesTransport {
    let payload: String
    private(set) var lastRequest: OpenAIClient.Request?

    init(payload: String) {
        self.payload = payload
    }

    func send(_ request: OpenAIClient.Request, apiKey: String) async throws -> String {
        lastRequest = request
        return payload
    }
}

private enum RecordingForemanClientError: Error {
    case unexpectedCall
}

private func makeStepResponse(thought: String, action: AgentAction) throws -> AgentStepResponse {
    struct StepEnvelope: Encodable {
        let thought: String
        let action: AgentAction
    }

    let data = try JSONEncoder().encode(StepEnvelope(thought: thought, action: action))
    return try JSONDecoder().decode(AgentStepResponse.self, from: data)
}
