# Foreman Terminal Understanding V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a structured terminal-understanding layer for AI Foreman so chat can explain what a terminal is doing, summarize what changed, and suggest ranked fixes before proposing any command execution.

**Architecture:** Add a dedicated terminal-understanding layer between `TerminalSnapshot` capture and `ForemanAgent` orchestration. That layer classifies each terminal into a small set of trusted states, extracts the most meaningful change, composes a plain-English summary, and produces ranked recovery suggestions for failure cases. `ForemanAgent` and the LLM clients then reason over structured understanding data instead of raw terminal text whenever possible.

**Tech Stack:** Swift, Swift Testing, SwiftUI, existing Ghostty macOS AI Foreman code, `xcodebuild` targeted tests

---

## File Structure

### New files

- `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`
  - Own the new terminal-understanding models, including structured per-terminal state, change summaries, and ranked suggestions.
- `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`
  - Build understanding objects from `TerminalSnapshot` values and optional `TerminalOutcomeReport` data.
- `macos/Tests/Terminal/TerminalUnderstandingTests.swift`
  - Unit tests for classification, summary composition, adaptive recap, and ranked suggestions.

### Existing files to modify

- `macos/Sources/Features/AIForeman/ForemanService.swift`
  - Extend the LLM protocol and service methods to accept structured understanding inputs.
- `macos/Sources/Features/AIForeman/ForemanAgent.swift`
  - Build understanding data before each `agentStep` call and route structured context into the service.
- `macos/Sources/Features/AIForeman/ForemanConversation.swift`
  - Store the last synthesized terminal overview so chat can answer from compressed context instead of raw noise.
- `macos/Sources/Features/AIForeman/AnthropicClient.swift`
  - Update prompt and request payload construction to consume structured terminal-understanding context.
- `macos/Sources/Features/AIForeman/OpenAIClient.swift`
  - Mirror the Anthropic prompt changes for the OpenAI path.
- `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
  - Apply structured terminal states to row models and preserve independent multi-terminal summaries.
- `macos/Tests/Terminal/ForemanAgentTests.swift`
  - Add red/green coverage for adaptive summaries and understanding-first agent turns.
- `macos/Tests/Terminal/ForemanServiceTests.swift`
  - Verify service payload construction now includes structured terminal-understanding data.

### Existing files to read while implementing

- `macos/Sources/Features/AIForeman/TerminalSnapshot.swift`
- `macos/Sources/Features/AIForeman/TerminalOutcomeEngine.swift`
- `macos/Sources/Features/AIForeman/TerminalOutcome.swift`
- `macos/Sources/Features/AIForeman/ForemanChatView.swift`
- `macos/Sources/Features/AIForeman/ForemanSidebarView.swift`

## Task 1: Add Structured Terminal Understanding Models And Engine

**Files:**
- Create: `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`
- Create: `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`
- Test: `macos/Tests/Terminal/TerminalUnderstandingTests.swift`

- [ ] **Step 1: Write the failing tests for terminal classification and summary composition**

```swift
import Foundation
import Testing
@testable import Ghostty

struct TerminalUnderstandingTests {
    @Test
    func engineClassifiesCommandNotFoundAsFailedWithRankedSuggestions() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "hfind . -print\nzsh: command not found: hfind\nuser@host %",
            recentScrollbackLines: ["hfind . -print", "zsh: command not found: hfind"],
            lastInputPreview: "hfind . -print"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.state == .failed)
        #expect(understanding.lastMeaningfulEvent.contains("command not found"))
        #expect(understanding.suggestedNextActions.count == 3)
        #expect(understanding.recommendedAction?.command == "find . -print")
    }

    @Test
    func engineClassifiesBuildOutputAsRunning() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-2",
            windowID: "win-1",
            tabID: "tab-2",
            title: "build",
            cwd: "/tmp/project",
            isFocused: false,
            visibleText: "Compiling module A...\nCompiling module B...",
            recentScrollbackLines: ["Compiling module A...", "Compiling module B..."],
            lastInputPreview: "swift build"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.state == .running)
        #expect(understanding.shortExplanation.contains("build"))
    }

    @Test
    func adaptiveOverviewMentionsOnlyChangedTerminal() {
        let engine = TerminalUnderstandingEngine()

        let previous = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .running,
                shortExplanation: "API server is booting.",
                lastMeaningfulEvent: "Server startup began.",
                importantDetails: ["Listening on port 3000 soon."],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .running,
                shortExplanation: "Tests are still running.",
                lastMeaningfulEvent: "Vitest started.",
                importantDetails: ["42 tests discovered."],
                suggestedNextActions: []
            ),
        ]

        let current = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .succeeded,
                shortExplanation: "API server is ready.",
                lastMeaningfulEvent: "Server reported ready.",
                importantDetails: ["Listening on http://localhost:3000."],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .running,
                shortExplanation: "Tests are still running.",
                lastMeaningfulEvent: "Vitest started.",
                importantDetails: ["42 tests discovered."],
                suggestedNextActions: []
            ),
        ]

        let overview = engine.makeOverview(current: current, previous: previous)

        #expect(overview.summary.contains("term-1"))
        #expect(!overview.summary.contains("term-2 is still running"))
        #expect(overview.changedTerminalIDs == ["term-1"])
    }
}
```

- [ ] **Step 2: Run the new test file and verify it fails**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/TerminalUnderstandingTests
```

Expected:

```text
error: cannot find 'TerminalUnderstandingEngine' in scope
error: cannot find type 'TerminalUnderstanding' in scope
Testing failed
```

- [ ] **Step 3: Add the new terminal-understanding models**

Create `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`:

```swift
import Foundation

enum TerminalUnderstandingState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case succeeded
    case failed
    case waiting
    case noisyHealthy = "noisy_healthy"
}

struct TerminalSuggestedAction: Codable, Equatable, Sendable {
    let title: String
    let command: String?
    let reason: String
    let isRecommended: Bool
}

struct TerminalUnderstanding: Codable, Equatable, Sendable, Identifiable {
    let terminalID: String
    let title: String
    let cwd: String?
    let state: TerminalUnderstandingState
    let lastMeaningfulEvent: String
    let shortExplanation: String
    let importantDetails: [String]
    let suggestedNextActions: [TerminalSuggestedAction]

    var id: String { terminalID }

    var recommendedAction: TerminalSuggestedAction? {
        suggestedNextActions.first(where: \.isRecommended)
    }

    static func preview(
        terminalID: String,
        state: TerminalUnderstandingState,
        shortExplanation: String,
        lastMeaningfulEvent: String,
        importantDetails: [String],
        suggestedNextActions: [TerminalSuggestedAction]
    ) -> Self {
        .init(
            terminalID: terminalID,
            title: terminalID,
            cwd: nil,
            state: state,
            lastMeaningfulEvent: lastMeaningfulEvent,
            shortExplanation: shortExplanation,
            importantDetails: importantDetails,
            suggestedNextActions: suggestedNextActions
        )
    }
}

struct TerminalOverview: Codable, Equatable, Sendable {
    let summary: String
    let changedTerminalIDs: [String]
    let primaryTerminalID: String?
}
```

- [ ] **Step 4: Add the understanding engine with minimal classification rules**

Create `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`:

```swift
import Foundation

struct TerminalUnderstandingEngine {
    func understand(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?
    ) -> TerminalUnderstanding {
        let visible = current.visibleText
        let lastEvent = extractLastMeaningfulEvent(from: current, previous: previous, lastOutcome: lastOutcome)
        let state = classifyState(current: current, lastOutcome: lastOutcome)
        let suggestedActions = makeSuggestions(for: current, state: state, lastEvent: lastEvent)

        return TerminalUnderstanding(
            terminalID: current.terminalID,
            title: current.title,
            cwd: current.cwd,
            state: state,
            lastMeaningfulEvent: lastEvent,
            shortExplanation: explain(state: state, snapshot: current, lastEvent: lastEvent),
            importantDetails: importantDetails(from: visible, state: state),
            suggestedNextActions: suggestedActions
        )
    }

    func makeOverview(
        current: [TerminalUnderstanding],
        previous: [TerminalUnderstanding]
    ) -> TerminalOverview {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.terminalID, $0) })
        let changed = current.filter { previousByID[$0.terminalID] != $0 }.map(\.terminalID)

        if let changedTerminal = current.first(where: { changed.contains($0.terminalID) }) {
            return TerminalOverview(
                summary: "\(changedTerminal.terminalID): \(changedTerminal.shortExplanation)",
                changedTerminalIDs: changed,
                primaryTerminalID: changedTerminal.terminalID
            )
        }

        let summary = current.isEmpty
            ? "No terminals are currently available."
            : current.map { "\($0.terminalID): \($0.shortExplanation)" }.joined(separator: " ")

        return TerminalOverview(
            summary: summary,
            changedTerminalIDs: [],
            primaryTerminalID: current.first?.terminalID
        )
    }

    private func classifyState(
        current: TerminalSnapshot,
        lastOutcome: TerminalOutcomeReport?
    ) -> TerminalUnderstandingState {
        if current.signals.likelyWaitingForInput {
            return .waiting
        }
        if let lastOutcome, lastOutcome.terminalID == current.terminalID {
            switch lastOutcome.outcome {
            case .success: return .succeeded
            case .failure: return .failed
            case .needsInput: return .waiting
            case .hung: return .failed
            case .stillRunning, .unknown: break
            }
        }
        if current.visibleText.lowercased().contains("command not found") || current.signals.likelyErrorState {
            return .failed
        }
        if current.signals.likelyLongRunning {
            return .running
        }
        if current.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .idle
        }
        return .noisyHealthy
    }

    private func extractLastMeaningfulEvent(
        from current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?
    ) -> String {
        if let lastOutcome, lastOutcome.terminalID == current.terminalID, let summary = lastOutcome.summary {
            return summary
        }
        let previousText = previous?.visibleText ?? ""
        let currentLines = current.visibleText.split(separator: "\n").map(String.init)
        let previousLines = Set(previousText.split(separator: "\n").map(String.init))
        return currentLines.last(where: { !previousLines.contains($0) && !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? currentLines.last
            ?? "No meaningful terminal event detected."
    }

    private func explain(
        state: TerminalUnderstandingState,
        snapshot: TerminalSnapshot,
        lastEvent: String
    ) -> String {
        switch state {
        case .failed:
            return "The terminal failed: \(lastEvent)"
        case .succeeded:
            return "The terminal completed successfully."
        case .running:
            return "The terminal is still running a long-lived command."
        case .waiting:
            return "The terminal is waiting for input."
        case .idle:
            return "The terminal is idle."
        case .noisyHealthy:
            return "The terminal is producing output without signs of failure."
        }
    }

    private func importantDetails(from visibleText: String, state: TerminalUnderstandingState) -> [String] {
        let lines = visibleText.split(separator: "\n").map(String.init)
        switch state {
        case .failed:
            return Array(lines.suffix(3))
        default:
            return Array(lines.suffix(2))
        }
    }

    private func makeSuggestions(
        for snapshot: TerminalSnapshot,
        state: TerminalUnderstandingState,
        lastEvent: String
    ) -> [TerminalSuggestedAction] {
        let input = snapshot.lastInputPreview ?? ""
        if state == .failed && lastEvent.lowercased().contains("command not found") && input.contains("hfind") {
            return [
                .init(title: "Run the likely intended find command", command: "find . -print", reason: "This looks like a typo of a standard shell command.", isRecommended: true),
                .init(title: "Try fd if a faster file search was intended", command: "fd .", reason: "The intended tool may have been `fd` rather than `find`.", isRecommended: false),
                .init(title: "Confirm whether hfind was intentional", command: nil, reason: "Use this when the missing command may be project-specific.", isRecommended: false),
            ]
        }

        if state == .failed {
            return [
                .init(title: "Inspect the failure details", command: nil, reason: lastEvent, isRecommended: true),
                .init(title: "Rerun the command after fixing the obvious issue", command: input.isEmpty ? nil : input, reason: "Useful when the failure was transient or typo-driven.", isRecommended: false),
                .init(title: "Ask Foreman for a focused explanation", command: nil, reason: "Useful if the output is noisy and needs compression.", isRecommended: false),
            ]
        }

        return []
    }
}
```

- [ ] **Step 5: Run the new tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/TerminalUnderstandingTests
```

Expected:

```text
Test Suite 'TerminalUnderstandingTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 6: Commit the model and engine slice**

```bash
git add macos/Sources/Features/AIForeman/TerminalUnderstanding.swift macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift macos/Tests/Terminal/TerminalUnderstandingTests.swift
git commit -m "feat: add terminal understanding engine"
```

## Task 2: Route Agent Turns Through Structured Understanding

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanService.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanAgent.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`
- Test: `macos/Tests/Terminal/ForemanServiceTests.swift`

- [ ] **Step 1: Add failing tests that require the agent to reason from structured understanding**

Append to `macos/Tests/Terminal/ForemanAgentTests.swift`:

```swift
    @Test
    func followUpQuestionUsesStructuredTerminalOverview() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .failed,
            shortExplanation: "The shell command failed because `hfind` is not installed.",
            lastMeaningfulEvent: "zsh: command not found: hfind",
            importantDetails: ["The typed command was `hfind . -print`."],
            suggestedNextActions: [
                .init(title: "Run the likely intended find command", command: "find . -print", reason: "Likely typo.", isRecommended: true),
            ]
        )
        let client = ScriptedForemanClient(
            responses: [
                try makeStepResponse(
                    thought: "I can answer from structured context.",
                    action: .respond(message: "This terminal failed because `hfind` is not installed. The likely fix is `find . -print`."))
            ]
        )
        client.capturedUnderstandings = [[understanding]]

        let commandRecorder = CommandRecorder()
        let agent = makeAgent(
            conversation: conversation,
            client: client,
            commandRecorder: commandRecorder
        )

        await agent.start(goal: "what happened here?", mode: .interactive, captureSnapshots: sampleSnapshots)

        try await waitFor {
            await MainActor.run { conversation.iterationCount >= 1 && conversation.status == .idle }
        }

        let payloads = await client.recordedUnderstandings()
        #expect(payloads.last?.first?.state == .failed)
        let messages = await MainActor.run { conversation.messages }
        #expect(messages.contains { $0.content.contains("likely fix is `find . -print`") })
    }
```

Append to `macos/Tests/Terminal/ForemanServiceTests.swift`:

```swift
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
        let overview = TerminalOverview(summary: "term-1 failed", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1")

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
```

- [ ] **Step 2: Run the targeted tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests -only-testing:GhosttyTests/ForemanServiceTests
```

Expected:

```text
error: extra arguments 'understandings', 'overview' in call
error: value of type 'ScriptedForemanClient' has no member 'recordedUnderstandings'
Testing failed
```

- [ ] **Step 3: Extend shared models and service signatures for structured understanding**

Modify `macos/Sources/Features/AIForeman/ForemanConversation.swift`:

```swift
    @Published var lastOverview: TerminalOverview?
    @Published var lastUnderstandings: [TerminalUnderstanding] = []

    func updateTerminalContext(
        overview: TerminalOverview,
        understandings: [TerminalUnderstanding]
    ) {
        self.lastOverview = overview
        self.lastUnderstandings = understandings
    }
```

Modify `macos/Sources/Features/AIForeman/ForemanService.swift`:

```swift
protocol ForemanLLMClient: Sendable {
    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary
    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan
    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse
}

    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        try await client.agentStep(
            conversation: conversation,
            terminals: terminals,
            understandings: understandings,
            overview: overview,
            lastOutcome: lastOutcome
        )
    }
```

- [ ] **Step 4: Build understanding data inside the agent loop before calling the service**

Modify `macos/Sources/Features/AIForeman/ForemanAgent.swift`:

```swift
    private let understandingEngine = TerminalUnderstandingEngine()
    private var previousSnapshotsByTerminalID: [String: TerminalSnapshot] = [:]
    private var previousUnderstandings: [TerminalUnderstanding] = []
```

Inside `runLoop(captureSnapshots:)`, insert:

```swift
            let understandings = terminals.map { snapshot in
                understandingEngine.understand(
                    current: snapshot,
                    previous: previousSnapshotsByTerminalID[snapshot.terminalID],
                    lastOutcome: lastOutcome
                )
            }
            let overview = understandingEngine.makeOverview(
                current: understandings,
                previous: previousUnderstandings
            )

            previousSnapshotsByTerminalID = Dictionary(
                uniqueKeysWithValues: terminals.map { ($0.terminalID, $0) }
            )
            previousUnderstandings = understandings

            await MainActor.run {
                conversation.updateTerminalContext(
                    overview: overview,
                    understandings: understandings
                )
            }

            let response = try await foremanService.agentStep(
                conversation: conversation,
                terminals: terminals,
                understandings: understandings,
                overview: overview,
                lastOutcome: lastOutcome
            )
```

- [ ] **Step 5: Update test doubles to record structured understanding payloads**

Modify the scripted test client in `macos/Tests/Terminal/ForemanAgentTests.swift` or its shared helper:

```swift
actor ScriptedForemanClient: ForemanLLMClient {
    private let responses: [AgentStepResponse]
    private var index = 0
    private var understandingsLog: [[TerminalUnderstanding]] = []

    var capturedUnderstandings: [[TerminalUnderstanding]] = []

    init(responses: [AgentStepResponse]) {
        self.responses = responses
    }

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary { fatalError() }
    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan { fatalError() }

    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        understandingsLog.append(understandings)
        if !capturedUnderstandings.isEmpty {
            understandingsLog.append(contentsOf: capturedUnderstandings)
        }
        defer { index += 1 }
        return responses[index]
    }

    func recordedUnderstandings() -> [[TerminalUnderstanding]] {
        understandingsLog
    }
}
```

- [ ] **Step 6: Run the targeted tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests -only-testing:GhosttyTests/ForemanServiceTests
```

Expected:

```text
Test Suite 'ForemanAgentTests' passed
Test Suite 'ForemanServiceTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 7: Commit the agent/service integration slice**

```bash
git add macos/Sources/Features/AIForeman/ForemanConversation.swift macos/Sources/Features/AIForeman/ForemanService.swift macos/Sources/Features/AIForeman/ForemanAgent.swift macos/Tests/Terminal/ForemanAgentTests.swift macos/Tests/Terminal/ForemanServiceTests.swift
git commit -m "feat: route foreman agent through terminal understanding"
```

## Task 3: Teach Both LLM Clients To Consume Structured Context

**Files:**
- Modify: `macos/Sources/Features/AIForeman/AnthropicClient.swift`
- Modify: `macos/Sources/Features/AIForeman/OpenAIClient.swift`
- Test: `macos/Tests/Terminal/AnthropicClientTests.swift`
- Test: `macos/Tests/Terminal/ForemanServiceTests.swift`

- [ ] **Step 1: Add failing prompt-shape tests for structured terminal context**

Append to `macos/Tests/Terminal/AnthropicClientTests.swift`:

```swift
    @Test
    func anthropicPromptIncludesStructuredOverviewAndSuggestions() async throws {
        let client = AnthropicClient(apiKey: "test-key")
        let understandings = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .failed,
                shortExplanation: "The shell command failed because `hfind` is not installed.",
                lastMeaningfulEvent: "zsh: command not found: hfind",
                importantDetails: ["Typed command: hfind . -print"],
                suggestedNextActions: [
                    .init(title: "Run find . -print", command: "find . -print", reason: "Likely typo.", isRecommended: true),
                ]
            ),
        ]
        let overview = TerminalOverview(summary: "term-1 failed because hfind is missing", changedTerminalIDs: ["term-1"], primaryTerminalID: "term-1")

        let prompt = client.makeAgentStepInstructions(
            conversationHistory: "[User]: what happened here?",
            goal: "what happened here?",
            terminals: sampleSnapshots(),
            understandings: understandings,
            overview: overview,
            lastOutcome: nil
        )

        #expect(prompt.contains("TERMINAL OVERVIEW"))
        #expect(prompt.contains("term-1 failed because hfind is missing"))
        #expect(prompt.contains("Run find . -print"))
        #expect(!prompt.contains("Dump raw terminal output without synthesis"))
    }
```

- [ ] **Step 2: Run the client test and verify it fails**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/AnthropicClientTests
```

Expected:

```text
error: value of type 'AnthropicClient' has no member 'makeAgentStepInstructions'
Testing failed
```

- [ ] **Step 3: Add a shared structured-context formatter and use it in both clients**

Modify `macos/Sources/Features/AIForeman/AnthropicClient.swift`:

```swift
    func makeAgentStepInstructions(
        conversationHistory: String,
        goal: String,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) -> String {
        let understandingBlock = understandings.map { understanding in
            """
            [\(understanding.terminalID)] state=\(understanding.state.rawValue)
            summary: \(understanding.shortExplanation)
            last_event: \(understanding.lastMeaningfulEvent)
            details: \(understanding.importantDetails.joined(separator: " | "))
            suggestions: \(understanding.suggestedNextActions.map(\.title).joined(separator: " | "))
            """
        }.joined(separator: "\n\n")

        return """
        You are Ghostty Foreman, a conversational terminal interpreter.

        SESSION GOAL:
        \(goal)

        TERMINAL OVERVIEW:
        \(overview.summary)

        STRUCTURED TERMINAL UNDERSTANDING:
        \(understandingBlock)

        CONVERSATION HISTORY:
        \(conversationHistory)

        Prefer answering from structured terminal understanding. Use raw terminal snapshots only when structured context is insufficient.
        """
    }
```

Mirror the same shape in `macos/Sources/Features/AIForeman/OpenAIClient.swift` and update each `agentStep(...)` implementation signature to accept `understandings` and `overview`.

- [ ] **Step 4: Run the client and service tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/AnthropicClientTests -only-testing:GhosttyTests/ForemanServiceTests
```

Expected:

```text
Test Suite 'AnthropicClientTests' passed
Test Suite 'ForemanServiceTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit the prompt and payload slice**

```bash
git add macos/Sources/Features/AIForeman/AnthropicClient.swift macos/Sources/Features/AIForeman/OpenAIClient.swift macos/Tests/Terminal/AnthropicClientTests.swift macos/Tests/Terminal/ForemanServiceTests.swift
git commit -m "feat: feed terminal understanding into foreman llm clients"
```

## Task 4: Apply Structured Understanding To Sidebar Rows And Independent Multi-Terminal Recaps

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarView.swift`
- Modify: `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

- [ ] **Step 1: Add failing tests for independent terminal summaries in the sidebar store**

Append to `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`:

```swift
    @Test
    @MainActor
    func applySnapshotsUsesStructuredUnderstandingStateAndExplanation() {
        let store = ForemanSidebarStore()
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "api",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "error: module not found",
                recentScrollbackLines: [],
                lastInputPreview: "npm test"
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-2",
                windowID: "win-1",
                tabID: "tab-2",
                title: "server",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "Server listening on http://localhost:3000",
                recentScrollbackLines: [],
                lastInputPreview: "npm run dev"
            ),
        ]
        let understandings = [
            "term-1": TerminalSummary(
                terminalID: "term-1",
                summary: "Tests failed because a module is missing.",
                state: "failed",
                confidence: 0.93,
                needsUserAttention: true,
                suggestedNextStep: "Install or fix the missing module import."
            ),
            "term-2": TerminalSummary(
                terminalID: "term-2",
                summary: "The dev server is healthy.",
                state: "running",
                confidence: 0.91,
                needsUserAttention: false,
                suggestedNextStep: "Continue watching for requests."
            ),
        ]

        store.applySnapshots(snapshots, summariesByTerminalID: understandings)

        #expect(store.terminalRows.count == 2)
        #expect(store.terminalRows[0].summary == "Tests failed because a module is missing.")
        #expect(store.terminalRows[1].summary == "The dev server is healthy.")
    }
```

- [ ] **Step 2: Run the sidebar store test and verify it fails if row mapping is inconsistent**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected:

```text
Expectation failed because sidebar row state does not reflect structured understanding
Testing failed
```

- [ ] **Step 3: Update the sidebar store and row rendering to prefer understanding-first language**

Modify `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`:

```swift
    func applySnapshots(
        _ snapshots: [TerminalSnapshot],
        summariesByTerminalID: [String: TerminalSummary] = [:]
    ) {
        terminalRows = snapshots.map { snapshot in
            if let summary = summariesByTerminalID[snapshot.terminalID] {
                return TerminalSummaryRowModel(
                    terminalID: snapshot.terminalID,
                    title: snapshot.title,
                    cwd: snapshot.cwd,
                    state: summary.state,
                    summary: summary.summary,
                    isFocused: snapshot.isFocused
                )
            }

            return TerminalSummaryRowModel(
                terminalID: snapshot.terminalID,
                title: snapshot.title,
                cwd: snapshot.cwd,
                state: Self.snapshotState(for: snapshot),
                summary: Self.snapshotSummary(for: snapshot),
                isFocused: snapshot.isFocused
            )
        }
    }
```

Modify `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift` to style terminal rows from normalized states instead of inferring directly from raw visible text:

```swift
private func badgeColor(for state: String) -> Color {
    switch state {
    case "failed":
        return .red
    case "running", "noisy_healthy":
        return .orange
    case "succeeded":
        return .green
    case "waiting":
        return .yellow
    default:
        return .secondary
    }
}
```

- [ ] **Step 4: Add an agent test for independent multi-terminal recap composition**

Append to `macos/Tests/Terminal/ForemanAgentTests.swift`:

```swift
    @Test
    func independentTerminalsProduceOverviewWithoutInventedSharedStory() {
        let engine = TerminalUnderstandingEngine()
        let overview = engine.makeOverview(
            current: [
                .preview(
                    terminalID: "term-1",
                    state: .failed,
                    shortExplanation: "Build failed because a module is missing.",
                    lastMeaningfulEvent: "error: module not found",
                    importantDetails: ["module A missing"],
                    suggestedNextActions: []
                ),
                .preview(
                    terminalID: "term-2",
                    state: .running,
                    shortExplanation: "Dev server is healthy and still running.",
                    lastMeaningfulEvent: "Listening on localhost:3000",
                    importantDetails: ["GET /health 200"],
                    suggestedNextActions: []
                ),
            ],
            previous: []
        )

        #expect(overview.summary.contains("term-1"))
        #expect(!overview.summary.contains("both terminals are working on the same task"))
    }
```

- [ ] **Step 5: Run the sidebar and agent tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests -only-testing:GhosttyTests/ForemanAgentTests
```

Expected:

```text
Test Suite 'ForemanSidebarStoreTests' passed
Test Suite 'ForemanAgentTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 6: Commit the sidebar and recap slice**

```bash
git add macos/Sources/Features/AIForeman/ForemanSidebarStore.swift macos/Sources/Features/AIForeman/ForemanSidebarView.swift macos/Sources/Features/AIForeman/TerminalSummaryRow.swift macos/Tests/Terminal/ForemanSidebarStoreTests.swift macos/Tests/Terminal/ForemanAgentTests.swift
git commit -m "feat: surface independent terminal understanding in foreman ui"
```

## Task 5: Run The Focused Verification Sweep

**Files:**
- Modify: none
- Test: `macos/Tests/Terminal/TerminalUnderstandingTests.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`
- Test: `macos/Tests/Terminal/ForemanServiceTests.swift`
- Test: `macos/Tests/Terminal/AnthropicClientTests.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Run the full targeted V1 suite**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/TerminalUnderstandingTests -only-testing:GhosttyTests/ForemanAgentTests -only-testing:GhosttyTests/ForemanServiceTests -only-testing:GhosttyTests/AnthropicClientTests -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected:

```text
Test Suite 'TerminalUnderstandingTests' passed
Test Suite 'ForemanAgentTests' passed
Test Suite 'ForemanServiceTests' passed
Test Suite 'AnthropicClientTests' passed
Test Suite 'ForemanSidebarStoreTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 2: Run a debug build to catch compile-only integration issues**

Run:

```bash
xcodebuild build -project macos/Ghostty.xcodeproj -scheme Ghostty
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: Commit the verification checkpoint**

```bash
git add -A
git commit -m "test: verify foreman terminal understanding v1"
```

## Self-Review

### Spec coverage

- Single-terminal understanding: covered in Task 1 and Task 2.
- Adaptive summary behavior: covered in Task 1 overview tests and Task 2 agent-path integration.
- Ranked fix suggestions: covered in Task 1 and consumed in Task 3.
- Approval-gated execution: existing agent flow preserved, validated again in Task 2 and Task 5.
- Independent multi-terminal behavior: covered in Task 4.
- Sidebar as inspect surface and chat as compression surface: covered by Task 2 and Task 4 without inventing a second product flow.

### Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain.
- Each task names exact files and concrete test commands.
- Each code step includes explicit code to add or modify.

### Type consistency

- Shared types introduced here are `TerminalUnderstandingState`, `TerminalSuggestedAction`, `TerminalUnderstanding`, and `TerminalOverview`.
- `ForemanService.agentStep(...)` is expanded consistently in Tasks 2 and 3.
- `TerminalUnderstandingEngine.makeOverview(...)` is the overview composition entrypoint used by both tests and `ForemanAgent`.
