# Foreman Long-Term Memory — Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Foreman Agent memory that persists across conversations, terminals, and app restarts. Memory is inferred automatically from terminal history — no manual goal-setting required.

**Architecture:** Extend the existing `ForemanMemoryStore` (SQLite + FTS5) with conversation fragments and inferred goals. Wire storage triggers into `ForemanAgent` life-cycle hooks. Feed retrieved memory into the LLM prompt via `ForemanService`. Restructure `AnthropicClient` to native multi-turn messages to unlock Claude's prompt caching API.

**Tech Stack:** Swift, SQLite3 (existing), Anthropic Messages API (with `cache_control`)

---

## Context: What Already Exists

- `ForemanMemoryStore` (`macos/Sources/Features/AIForeman/ForemanMemoryStore.swift`) — SQLite actor with two tables: `situation_outcomes` and `session_summaries`. It is **not wired** into the agent flow today.
- `AnthropicClient` (`AnthropicClient.swift`) — Sends single-turn requests. The full conversation history is embedded as JSON inside one user message. No prompt caching.
- `ForemanAgent` (`ForemanAgent.swift`) — Stateless reactive loop. Each `react(to:)` or `start(goal:)` begins fresh. `previousSnapshotsByTerminalID` and `previousUnderstandings` are in-memory only and reset on `start()`.
- `ForemanConversation` (`ForemanConversation.swift`) — In-memory message array. Lost on app quit.
- `ForemanService` (`ForemanService.swift`) — Thin wrapper around `ForemanLLMClient`. Does not touch memory.

---

## Design Decisions

### 1. What to Store (Memory Schema)

Keep the existing SQLite store. Add two tables. All records are scoped by `project_path` (git root or cwd fallback) so retrieval is project-local.

#### New Table: `conversation_fragments`

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | UUID |
| `terminal_id` | TEXT | Terminal that triggered the conversation |
| `project_path` | TEXT | Git root or cwd |
| `goal` | TEXT | User's original goal text |
| `summary` | TEXT | LLM-generated summary of what happened |
| `messages_json` | TEXT | Serialized `[ConversationMessage]` (last 20 msgs) |
| `keywords` | TEXT | Comma-separated keywords for FTS |
| `timestamp` | REAL | Unix time |
| `was_successful` | INTEGER | 1 if `declareComplete`, 0 otherwise |

Why fragments instead of full transcripts? Claude's context window is 200k, but retrieval should be tight. We store the *last* 20 messages of a conversation (enough for intent + outcome) plus an LLM-generated summary.

#### New Table: `inferred_goals`

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | UUID |
| `project_path` | TEXT | Git root or cwd |
| `goal_text` | TEXT | The inferred goal |
| `confidence` | REAL | 0.0–1.0 |
| `source_fragment_id` | TEXT | FK to conversation_fragments |
| `timestamp` | REAL | Unix time |

Inferred goals are extracted by the LLM itself at the end of each session: "Based on this conversation, what was the user trying to accomplish?" This lets the Foreman recognize recurring tasks without explicit goal setting.

#### Existing Tables (kept, now wired)

- `situation_outcomes` — Already stores action + outcome per terminal state. We will actually populate it now.
- `session_summaries` — Already stores per-terminal summaries. We will populate it at session end.

#### No UserDefaults / JSON files

SQLite with FTS5 is already in place. It gives us structured querying, full-text search, and ACID persistence without adding dependencies.

---

### 2. When to Update Memory (Triggers)

#### Trigger A: After every `agentStep` action → `situation_outcomes`

In `ForemanAgent.executeAction(_:)`, after an action is executed:

```swift
// Pseudocode — see Task 3 for real implementation
let record = SituationOutcomeRecord(
    terminalID: terminalID,
    situationFingerprint: snapshot.hashValue,
    cwd: snapshot.cwd,
    action: command,
    outcome: outcome,
    visibleText: snapshot.visibleText,
    timestamp: Date(),
    projectPath: projectPath(from: snapshot.cwd)
)
Task { try? await ForemanMemoryStore.shared.store(record: record) }
```

#### Trigger B: On conversation terminal state → `conversation_fragments` + `inferred_goals`

In `ForemanAgent.executeAction(_:)`, when the action is:
- `.declareComplete(summary:)`
- `.declareStuck(reason:)`
- `.respond(message:)` after an idle timeout (reactive mode only)

```swift
let fragment = ConversationFragment(
    terminalID: triggeringTerminalID,
    projectPath: projectPath,
    goal: conversation.goal ?? "",
    summary: "",               // filled by LLM in async extraction
    messages: last20Messages,
    keywords: [],              // filled by LLM
    timestamp: Date(),
    wasSuccessful: action.isComplete
)
```

The summary and keywords are extracted by a *lightweight* LLM call (or locally via the same Claude API with a tiny prompt). This is non-blocking — the agent continues while memory writes happen in a background `Task`.

#### Trigger C: Periodic flush during long autonomous runs

Every 10 iterations in `runLoop`, snapshot the current conversation state to `conversation_fragments` with `wasSuccessful = 0` (incomplete). This prevents data loss if the app crashes during a long task.

---

### 3. How to Inject Memory into the LLM Prompt

#### Retrieval Strategy

`ForemanService` gains a new private method:

```swift
private func relevantMemory(
    for terminals: [TerminalSnapshot],
    currentGoal: String,
    visibleText: String
) async -> RelevantMemory {
    let projectPath = projectPath(from: terminals.first?.cwd ?? "")
    let keywords = extractKeywords(from: currentGoal + " " + visibleText)

    async let fragments = memoryStore.queryFragments(projectPath: projectPath, keywords: keywords, limit: 3)
    async let goals = memoryStore.queryInferredGoals(projectPath: projectPath, limit: 2)
    async let outcomes = memoryStore.query(cwd: terminals.first?.cwd ?? "", visibleText: visibleText, limit: 3)

    return RelevantMemory(fragments: await fragments, goals: await goals, outcomes: await outcomes)
}
```

Query order:
1. **Same project path, recency** — most recent fragments from this git repo
2. **Keyword overlap via FTS5** — if fewer than 3 results
3. **Same CWD** — if still fewer than 3
4. **Inferred goals** — top 2 goals for this project

#### Prompt Injection Format

In `AnthropicClient.agentStepPrompt`, add a new section after `Session goal:`:

```
Relevant past context from this project:

Inferred goals:
- "Fix auth bug in login flow" (confidence: 0.92)
- "Refactor user service to use async/await" (confidence: 0.74)

Recent similar situations:
- [2025-05-04] Ran `npm test` in /Users/dev/project → Tests passed
- [2025-05-04] Ran `git rebase origin/main` → Conflict in auth.ts

Past conversation fragments:
- [2025-05-03] "Debugged failing OAuth tests" — Agent ran `pytest tests/auth/`, discovered missing env var, suggested `export AUTH_CLIENT_SECRET=...`
```

This is plain text inside the user prompt. It gives Claude grounding without changing the JSON response contract.

---

### 4. Prompt Caching — Yes, Use It

#### Why

Claude's prompt caching API (`cache_control: { type: "ephemeral" }`) lets us cache the system prompt + large static context blocks across requests. With long-term memory, the "static" part of our prompt (instructions + project memory) can grow to 10k–50k tokens. Caching this:
- Reduces latency by ~80% on subsequent turns
- Cuts costs by ~90% for cached tokens

#### How

The current `AnthropicClient` sends **single-turn** requests with the full conversation history embedded as JSON inside the user message. This cannot use prompt caching because every request is effectively a new conversation.

**Phase 1 (Immediate):** Keep the single-turn architecture. Inject memory inline. This ships the feature today with zero transport-layer changes.

**Phase 2 (Caching):** Restructure `AnthropicClient` to use **native multi-turn messages**:

1. `AnthropicClient.Request.Message` evolves from simple `String` content to content blocks:

```swift
struct Message: Encodable, Sendable {
    let role: String
    let content: [ContentBlock]
}

struct ContentBlock: Encodable, Sendable {
    let type: String        // "text"
    let text: String
    let cacheControl: CacheControl?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case cacheControl = "cache_control"
    }
}

struct CacheControl: Encodable, Sendable {
    let type: String        // "ephemeral"
}
```

2. The request payload changes from:
```json
{ "system": "instructions", "messages": [{"role":"user","content":"<everything here>"}] }
```

To:
```json
{
  "system": [
    { "type": "text", "text": "You are an autonomous terminal foreman..." },
    { "type": "text", "text": "<long_term_memory>", "cache_control": { "type": "ephemeral" } }
  ],
  "messages": [
    { "role": "user", "content": "Goal: fix auth bug" },
    { "role": "assistant", "content": "{\"thought\":\"...\",\"action\":...}" },
    { "role": "user", "content": "<new terminal state>" }
  ]
}
```

3. `ForemanConversation.messages` becomes the canonical message history. On each `agentStep`, we send the full message array as native Anthropic messages, appending only the new user turn. The system prompt + memory block is cached automatically by Anthropic.

4. The transport layer must add the `anthropic-beta: prompt-caching-2024-07-31` header.

**Migration path:** Keep the existing `AnthropicClient` protocol methods. Add a new internal `performMultiTurn` method. The `agentStep` methods build the message array and call it. If the API returns a cache miss warning, log it — graceful degradation.

---

## Implementation Tasks

---

### Task 1: Extend `ForemanMemoryStore` schema

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanMemoryStore.swift`

**Changes:**

Add two new tables to `createSchema()`:

```swift
CREATE TABLE IF NOT EXISTS conversation_fragments (
    id TEXT PRIMARY KEY,
    terminal_id TEXT NOT NULL,
    project_path TEXT,
    goal TEXT NOT NULL,
    summary TEXT NOT NULL,
    messages_json TEXT NOT NULL,
    keywords TEXT NOT NULL,
    timestamp REAL NOT NULL,
    was_successful INTEGER NOT NULL
);

CREATE VIRTUAL TABLE IF NOT EXISTS fragment_fts USING fts5(
    goal,
    summary,
    keywords,
    content='conversation_fragments',
    content_rowid='rowid'
);

CREATE TABLE IF NOT EXISTS inferred_goals (
    id TEXT PRIMARY KEY,
    project_path TEXT,
    goal_text TEXT NOT NULL,
    confidence REAL NOT NULL,
    source_fragment_id TEXT,
    timestamp REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_fragments_project ON conversation_fragments(project_path);
CREATE INDEX IF NOT EXISTS idx_fragments_timestamp ON conversation_fragments(timestamp);
CREATE INDEX IF NOT EXISTS idx_goals_project ON inferred_goals(project_path);
```

Add actor methods:
- `store(fragment: ConversationFragment) async throws`
- `queryFragments(projectPath: String, keywords: [String], limit: Int) async throws -> [ConversationFragment]`
- `store(inferredGoal: InferredGoal) async throws`
- `queryInferredGoals(projectPath: String, limit: Int) async throws -> [InferredGoal]`

**Test:** Run existing memory store tests plus new ones.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild test -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/ForemanMemoryStoreTests 2>&1 | tail -10
```

**Expected:** All tests pass. New schema validates.

---

### Task 2: Add memory models

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalOutcome.swift` (or new file `ForemanMemoryModels.swift`)

**Changes:**

Add `ConversationFragment` and `InferredGoal` structs:

```swift
struct ConversationFragment: Codable, Sendable, Identifiable {
    let id: UUID
    let terminalID: String
    let projectPath: String?
    let goal: String
    let summary: String
    let messages: [ConversationMessage]
    let keywords: [String]
    let timestamp: Date
    let wasSuccessful: Bool
}

struct InferredGoal: Codable, Sendable, Identifiable {
    let id: UUID
    let projectPath: String?
    let goalText: String
    let confidence: Double
    let sourceFragmentID: UUID
    let timestamp: Date
}

struct RelevantMemory: Sendable {
    let fragments: [ConversationFragment]
    let goals: [InferredGoal]
    let outcomes: [SituationOutcomeRecord]

    var isEmpty: Bool { fragments.isEmpty && goals.isEmpty && outcomes.isEmpty }
}
```

**Test:** Build project.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild build -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5
```

**Expected:** `** BUILD SUCCEEDED **`

---

### Task 3: Wire storage triggers into `ForemanAgent`

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanAgent.swift`

**Changes:**

Add a memory store reference:

```swift
private let memoryStore: ForemanMemoryStore

init(
    conversation: ForemanConversation,
    foremanService: ForemanService,
    memoryStore: ForemanMemoryStore = .shared,
    onSendCommand: ...,
    onStatusChange: ...,
    onAction: ...
) {
    self.memoryStore = memoryStore
    // ...
}
```

In `executeAction(_:)`, after handling each action, append a non-blocking memory write:

```swift
private func persistOutcome(for action: AgentAction, response: AgentStepResponse) async {
    guard let captureSnapshots = captureSnapshots else { return }
    let terminals = await captureSnapshots()
    guard let terminal = terminals.first else { return }

    let projectPath = memoryStore.projectPath(from: terminal.cwd)
    let record = SituationOutcomeRecord(
        id: UUID(),
        terminalID: terminal.terminalID,
        situationFingerprint: terminal.visibleText.hashValue,
        cwd: terminal.cwd,
        action: actionDescription(of: action),
        outcome: .unknown,      // refined later by TerminalOutcomeEngine
        visibleText: terminal.visibleText,
        timestamp: Date(),
        projectPath: projectPath
    )
    try? await memoryStore.store(record: record)
}
```

In `executeAction(_:)`, for terminal actions (`declareComplete`, `declareStuck`, `respond` after idle), fire an async fragment extraction:

```swift
private func persistConversationFragment(wasSuccessful: Bool) async {
    let messages = await MainActor.run { Array(conversation.messages.suffix(20)) }
    guard let firstTerminalID = previousSnapshotsByTerminalID.keys.first else { return }
    guard let cwd = previousSnapshotsByTerminalID[firstTerminalID]?.cwd else { return }

    let fragment = ConversationFragment(
        id: UUID(),
        terminalID: firstTerminalID,
        projectPath: memoryStore.projectPath(from: cwd),
        goal: await MainActor.run { conversation.goal ?? "" },
        summary: "",            // populated by async LLM call
        messages: messages,
        keywords: [],
        timestamp: Date(),
        wasSuccessful: wasSuccessful
    )

    try? await memoryStore.store(fragment: fragment)

    // Async goal extraction (lightweight, non-blocking)
    if let inferred = try? await foremanService.inferGoal(from: messages) {
        let goal = InferredGoal(
            id: UUID(),
            projectPath: fragment.projectPath,
            goalText: inferred.goalText,
            confidence: inferred.confidence,
            sourceFragmentID: fragment.id,
            timestamp: Date()
        )
        try? await memoryStore.store(inferredGoal: goal)
    }
}
```

**Test:** Run agent tests.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild test -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/ForemanAgentTests 2>&1 | tail -10
```

**Expected:** All tests pass. Storage is fire-and-forget — failures don't break the agent loop.

---

### Task 4: Add goal inference to `ForemanService` / `ForemanLLMClient`

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanService.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanModels.swift`

**Changes:**

Add a new model:

```swift
struct InferredGoalResult: Codable, Sendable {
    let goalText: String
    let confidence: Double
}
```

Extend `ForemanLLMClient`:

```swift
func inferGoal(from messages: [ConversationMessage]) async throws -> InferredGoalResult
```

Implement in `ForemanService`:

```swift
func inferGoal(from messages: [ConversationMessage]) async throws -> InferredGoalResult {
    try await client.inferGoal(from: messages)
}
```

Implement in `AnthropicClient` with a tiny prompt:

```swift
func inferGoal(from messages: [ConversationMessage]) async throws -> InferredGoalResult {
    let request = Request(
        model: summaryModel,
        system: "Extract the user's underlying goal from this conversation. Return JSON only.",
        maxTokens: 200,
        messages: [.user("Conversation:\n" + messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n"))]
    )
    let payload = try await perform(request)
    return try decoder.decode(InferredGoalResult.self, from: Data(payload.utf8))
}
```

**Test:** Build project.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild build -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5
```

**Expected:** `** BUILD SUCCEEDED **`

---

### Task 5: Wire memory retrieval into `ForemanService.agentStep`

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanService.swift`

**Changes:**

Add memory retrieval and pass it to the client:

```swift
private let memoryStore: ForemanMemoryStore

init(client: any ForemanLLMClient, memoryStore: ForemanMemoryStore = .shared) {
    self.client = client
    self.memoryStore = memoryStore
}

func agentStep(
    conversation: ForemanConversation,
    terminals: [TerminalSnapshot],
    understandings: [TerminalUnderstanding],
    overview: TerminalOverview,
    lastOutcome: TerminalOutcomeReport?
) async throws -> AgentStepResponse {
    let memory = await retrieveRelevantMemory(for: terminals, conversation: conversation)
    return try await client.agentStep(
        conversation: conversation,
        terminals: terminals,
        understandings: understandings,
        overview: overview,
        lastOutcome: lastOutcome,
        relevantMemory: memory
    )
}
```

**Note:** This requires extending the `ForemanLLMClient` protocol with a new `agentStep` overload that accepts `RelevantMemory`. The existing overload remains for backward compatibility during migration.

**Test:** Build project.

---

### Task 6: Inject memory into `AnthropicClient` prompt (Phase 1 — inline)

**Files:**
- Modify: `macos/Sources/Features/AIForeman/AnthropicClient.swift`

**Changes:**

Update `agentStepPrompt` to accept `relevantMemory: RelevantMemory`:

```swift
private static func agentStepPrompt(
    goal: String,
    latestUserMessage: String,
    mode: String,
    iterationCount: Int,
    messages: [ConversationMessage],
    understandings: [TerminalUnderstanding],
    overview: TerminalOverview,
    terminals: [TerminalSnapshot],
    lastOutcome: TerminalOutcomeReport?,
    relevantMemory: RelevantMemory,
    using encoder: JSONEncoder
) -> String {
    var memorySection = ""
    if !relevantMemory.isEmpty {
        memorySection = """

        Relevant past context from this project:
        """
        if !relevantMemory.goals.isEmpty {
            memorySection += "\n\nInferred goals:\n"
            memorySection += relevantMemory.goals.map { "- \"\($0.goalText)\" (confidence: \($0.confidence))" }.joined(separator: "\n")
        }
        if !relevantMemory.outcomes.isEmpty {
            memorySection += "\n\nRecent similar situations:\n"
            memorySection += relevantMemory.outcomes.map { "- [\($0.timestamp)] Ran `\($0.action)` in \($0.cwd) → \($0.outcome.rawValue)" }.joined(separator: "\n")
        }
        if !relevantMemory.fragments.isEmpty {
            memorySection += "\n\nPast conversation fragments:\n"
            memorySection += relevantMemory.fragments.map { "- [\($0.timestamp)] \"\($0.summary)\"" }.joined(separator: "\n")
        }
    }

    return """
    Return one JSON object with this exact shape:
    { ... }

    Session goal: \(goal)
    Latest user message: \(latestUserMessage)
    Mode: \(mode)
    Iteration: \(iterationCount)/20
    \(memorySection)

    Conversation history:
    ...
    """
}
```

**Test:** Build + run agent tests.

---

### Task 7: Restructure `AnthropicClient` for multi-turn + prompt caching (Phase 2)

**Files:**
- Modify: `macos/Sources/Features/AIForeman/AnthropicClient.swift`

**Changes:**

1. Update `Request` to support content blocks:

```swift
struct Request: Encodable, Sendable {
    let model: String
    let system: [SystemBlock]
    let maxTokens: Int
    let messages: [Message]
    // ...
}

struct SystemBlock: Encodable, Sendable {
    let type: String
    let text: String
    let cacheControl: CacheControl?
}
```

2. Update `Message` to use content blocks:

```swift
struct Message: Encodable, Sendable {
    let role: String
    let content: [ContentBlock]
}
```

3. Update `URLSessionAnthropicTransport` to add the beta header:

```swift
urlRequest.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
```

4. Refactor `agentStep` to build native multi-turn history:

```swift
func agentStep(
    conversation: ForemanConversation,
    terminals: [TerminalSnapshot],
    understandings: [TerminalUnderstanding],
    overview: TerminalOverview,
    lastOutcome: TerminalOutcomeReport?,
    relevantMemory: RelevantMemory
) async throws -> AgentStepResponse {
    let (goal, mode, iterationCount, messages) = await MainActor.run {
        (conversation.goal ?? "", conversation.mode.rawValue, conversation.iterationCount, conversation.messages)
    }

    // System prompt split into cacheable chunks
    let systemBlocks: [SystemBlock] = [
        .init(type: "text", text: Self.makeAgentStepInstructions(), cacheControl: nil),
        .init(type: "text", text: formatMemory(relevantMemory), cacheControl: .init(type: "ephemeral"))
    ]

    // Convert conversation messages to Anthropic messages
    var anthropicMessages: [Message] = messages.map { msg in
        Message(role: msg.role == .user ? "user" : "assistant",
                content: [.init(type: "text", text: msg.content, cacheControl: nil)])
    }

    // Append the current turn with fresh terminal context
    let currentTurn = Self.agentStepUserTurn(
        goal: goal,
        mode: mode,
        iterationCount: iterationCount,
        terminals: terminals,
        understandings: understandings,
        overview: overview,
        lastOutcome: lastOutcome,
        using: encoder
    )
    anthropicMessages.append(.user(currentTurn))

    let request = Request(
        model: plannerModel,
        system: systemBlocks,
        maxTokens: 1200,
        messages: anthropicMessages
    )

    let payload = try await perform(request)
    return try Self.decodeJSON(AgentStepResponse.self, from: payload, decoder: decoder)
}
```

**Why this works for caching:** Anthropic caches contiguous prefixes of the prompt. By putting the system instructions + memory block at the start with `cache_control`, every subsequent turn reuses the cached prefix. Only the new user turn + assistant response are processed fresh.

**Test:** Build project + run agent tests with a mocked transport that validates the JSON shape.

---

### Task 8: Persist `ForemanConversation` across app launches

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanMemoryStore.swift`

**Changes:**

Add a `current_conversation` table to SQLite:

```swift
CREATE TABLE IF NOT EXISTS current_conversation (
    id INTEGER PRIMARY KEY CHECK (id = 1),  -- singleton
    messages_json TEXT NOT NULL,
    goal TEXT,
    mode TEXT,
    updated_at REAL NOT NULL
);
```

Add to `ForemanConversation`:

```swift
func save() async {
    let data = try? JSONEncoder().encode(messages)
    let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    try? await ForemanMemoryStore.shared.saveCurrentConversation(
        messagesJSON: json,
        goal: goal,
        mode: mode.rawValue
    )
}

func restore() async {
    guard let record = try? await ForemanMemoryStore.shared.loadCurrentConversation() else { return }
    if let data = record.messagesJSON.data(using: .utf8),
       let msgs = try? JSONDecoder().decode([ConversationMessage].self, from: data) {
        self.messages = msgs
        self.goal = record.goal
        self.mode = AgentMode(rawValue: record.mode) ?? .interactive
    }
}
```

Call `save()` after every `addMessage` and `restore()` on ` ForemanConversation` initialization.

**Test:** Write a test verifying save/restore round-trip.

---

### Task 9: Add memory-aware tests

**Files:**
- New: `macos/Tests/Terminal/ForemanMemoryIntegrationTests.swift`

**Test cases:**

1. `testAgentStoresOutcomeAfterCommandExecution` — Verify `ForemanMemoryStore.query` returns the record after an agent loop.
2. `testMemoryRetrievalMatchesProjectPath` — Two agents in different projects; queries are isolated.
3. `testInferredGoalExtraction` — Mock LLM client returns a goal; verify it lands in `inferred_goals`.
4. `testMemoryInjectionInPrompt` — Mock transport captures the full request; assert it contains "Relevant past context".
5. `testConversationPersistence` — Save conversation, recreate store, restore, assert messages match.

**Test:** Run full Foreman test suite.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild test -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/ForemanAgentTests -only-testing:GhosttyTests/ForemanMemoryStoreTests 2>&1 | tail -10
```

---

## File Summary

| File | Action | Purpose |
|------|--------|---------|
| `ForemanMemoryStore.swift` | Modify | Add `conversation_fragments`, `inferred_goals`, `current_conversation` tables + query methods |
| `TerminalOutcome.swift` | Modify | Add `ConversationFragment`, `InferredGoal`, `RelevantMemory` models |
| `ForemanAgent.swift` | Modify | Fire storage triggers after actions; inject memory store |
| `ForemanService.swift` | Modify | Retrieve relevant memory before LLM calls; add `inferGoal` |
| `ForemanLLMClient` protocol | Modify | Add `inferGoal` + new `agentStep` overload with memory |
| `AnthropicClient.swift` | Modify | Phase 1: inject memory inline. Phase 2: content blocks + caching |
| `ForemanConversation.swift` | Modify | Add `save()` / `restore()` for crash resilience |
| `ForemanMemoryIntegrationTests.swift` | New | End-to-end memory storage + retrieval tests |

---

## Rollback / Safety

- All memory writes are `try?` — failures are silent and do not block the agent.
- The existing `agentStep` overload without `RelevantMemory` remains available. If the new path breaks, `ForemanService` can fall back to the old signature.
- Schema migrations are additive (`CREATE TABLE IF NOT EXISTS`). Old app versions ignore new tables.
- Prompt caching is Phase 2. Phase 1 works with the existing transport layer.

---

## Success Criteria

1. After running the agent on "fix auth bug" and completing, starting a new conversation in the same repo with "run tests" includes "fix auth bug" in the inferred goals section of the prompt.
2. Reactive `react(to:)` events in a project with history include relevant past situation outcomes in the LLM context.
3. App restart preserves the in-flight conversation (if any).
4. Anthropic API costs for multi-turn sessions drop measurably after Phase 2 caching (verified via `usage` field in API responses).
5. All existing Foreman tests pass without modification.
