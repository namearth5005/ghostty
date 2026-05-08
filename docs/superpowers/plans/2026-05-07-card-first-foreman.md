# Card-First Foreman Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Foreman's reactive AI-agent flow into a card-first pending-attention workflow where deterministic approvals and choices render as direct terminal-card actions without calling the LLM.

**Architecture:** Add fingerprinted agent attention events, a pending-attention store in `ForemanSidebarStore`, and terminal-card rendering for typed actions. Route deterministic events in `AppDelegate` directly into pending attention; keep `ForemanAgent` only for semantic suggestions and hidden-context LLM work.

**Tech Stack:** Swift, SwiftUI, Swift Testing, existing Ghostty macOS AIForeman code, `xcodebuild`/`macos/build.nu`

---

## File Structure

- Modify `macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift`
  - Add `fingerprint`.
  - Add display fields only if already available from `TerminalUnderstanding`.
- Modify `macos/Sources/Features/AIForeman/AgentStateMonitor.swift`
  - Replace state/cooldown-only suppression with unresolved fingerprint suppression.
  - Add `resolve(terminalID:fingerprint:)`.
- Modify `macos/Tests/Terminal/AgentStateMonitorTests.swift`
  - Keep and complete the existing fingerprint tests.
- Modify `macos/Sources/Features/AIForeman/ForemanConversation.swift`
  - Add hidden prompt context storage that is not rendered by chat.
- Modify `macos/Sources/Features/AIForeman/ForemanAgent.swift`
  - Store reactive context as hidden context.
  - Stop appending internal event messages to visible chat.
- Modify `macos/Sources/Features/AIForeman/ForemanService.swift`
  - Keep current API for this slice unless tests require a hidden-context prompt.
- Modify `macos/Sources/Features/AIForeman/AnthropicClient.swift`
  - Include hidden context in prompt input.
- Modify `macos/Sources/Features/AIForeman/OpenAIClient.swift`
  - Mirror Anthropic hidden context behavior.
- Modify `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
  - Add `PendingAgentAttention`, `PendingAgentAction`, resolution state, and lifecycle helpers.
  - Project pending attention into `TerminalSummaryRowModel`.
- Modify `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift`
  - Render pending attention above generic suggested actions.
- Modify `macos/Sources/Features/Terminal/BaseTerminalController.swift`
  - Wire terminal-card pending actions to the app delegate dispatcher.
- Modify `macos/Sources/App/macOS/AppDelegate.swift`
  - Route `waitingApproval` and `waitingChoice` events to pending attention.
  - Resolve pending attention when actions are sent.
  - Call the LLM only for semantic `waitingText` and unclear errors.
- Modify `macos/Sources/Features/AIForeman/ForemanModels.swift`
  - Decouple reactive waiting UI from `goal == nil` where needed.
- Modify `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`
  - Add pending attention store tests.
- Modify `macos/Tests/Terminal/ForemanAgentTests.swift`
  - Keep hidden-context tests.
  - Add reactive no-visible-context assertions.

## Verification Commands

Before Swift test work, run:

```bash
zig build -Demit-macos-app=false
```

For focused AIForeman verification after compile blockers are fixed:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/AgentStateMonitorTests \
  -only-testing:GhosttyTests/ForemanAgentTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests \
  -only-testing:GhosttyTests/TerminalUnderstandingTests \
  test
```

Full documented test pass:

```bash
macos/build.nu --scheme Ghostty --configuration Debug --action test
```

---

## Task 1: Fingerprinted Agent Attention Events

**Files:**
- Modify: `macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift`
- Modify: `macos/Sources/Features/AIForeman/AgentStateMonitor.swift`
- Test: `macos/Tests/Terminal/AgentStateMonitorTests.swift`

- [ ] **Step 1: Confirm failing tests**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/AgentStateMonitorTests \
  test
```

Expected before implementation:

```text
Value of type 'AgentNeedsAttentionEvent' has no member 'fingerprint'
Value of type 'AgentStateMonitor' has no member 'resolve'
```

- [ ] **Step 2: Add fingerprint to `AgentNeedsAttentionEvent`**

Update `macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift`:

```swift
import Foundation

/// Fired when an AI agent (Kimi, Claude Code, Codex) transitions from
/// actively working to a state where it needs user input or approval.
struct AgentNeedsAttentionEvent: Sendable {
    let terminalID: String
    let agentIdentity: AgentIdentity
    let interactionState: AgentInteractionState
    let deltaText: String
    let timestamp: Date
    let fingerprint: String

    init(
        terminalID: String,
        agentIdentity: AgentIdentity,
        interactionState: AgentInteractionState,
        deltaText: String,
        timestamp: Date,
        fingerprint: String
    ) {
        self.terminalID = terminalID
        self.agentIdentity = agentIdentity
        self.interactionState = interactionState
        self.deltaText = deltaText
        self.timestamp = timestamp
        self.fingerprint = fingerprint
    }
}
```

- [ ] **Step 3: Replace coarse monitor suppression with active fingerprints**

Update `macos/Sources/Features/AIForeman/AgentStateMonitor.swift`:

```swift
import Foundation

/// Watches AI agent terminals and fires an event when an agent reaches
/// a new actionable request that needs user attention.
final class AgentStateMonitor {
    var onEvent: ((AgentNeedsAttentionEvent) -> Void)?

    private var previousAgentStateByTerminalID: [String: AgentInteractionState] = [:]
    private var activeFingerprintByTerminalID: [String: String] = [:]

    func resolve(terminalID: String, fingerprint: String) {
        guard activeFingerprintByTerminalID[terminalID] == fingerprint else { return }
        activeFingerprintByTerminalID.removeValue(forKey: terminalID)
        DebugLogger.log("[AgentStateMonitor] Resolved terminal \(terminalID.prefix(8)) fingerprint \(fingerprint)")
    }

    func observe(understandings: [TerminalUnderstanding]) {
        let now = Date()
        let activeIDs = Set(understandings.map(\.terminalID))

        for understanding in understandings {
            let id = understanding.terminalID

            guard understanding.agentIdentity != .none else {
                previousAgentStateByTerminalID.removeValue(forKey: id)
                activeFingerprintByTerminalID.removeValue(forKey: id)
                continue
            }

            let previous = previousAgentStateByTerminalID[id] ?? .unknown
            let current = understanding.agentInteractionState

            if !Self.isActionable(current) {
                activeFingerprintByTerminalID.removeValue(forKey: id)
                previousAgentStateByTerminalID[id] = current
                continue
            }

            let currentFingerprint = fingerprint(for: understanding)

            if activeFingerprintByTerminalID[id] == currentFingerprint {
                previousAgentStateByTerminalID[id] = current
                DebugLogger.log("[AgentStateMonitor] Skipping unchanged fingerprint: terminal=\(id.prefix(8)) state=\(current)")
                continue
            }

            let isTransitionFromRunning = previous == .running
            let isFirstDetection = previous == .unknown
            let isUrgentFirstDetection = isFirstDetection && Self.isUrgent(current)
            let requestChanged = activeFingerprintByTerminalID[id] != nil &&
                activeFingerprintByTerminalID[id] != currentFingerprint

            if isTransitionFromRunning || isUrgentFirstDetection || requestChanged {
                let event = AgentNeedsAttentionEvent(
                    terminalID: id,
                    agentIdentity: understanding.agentIdentity,
                    interactionState: current,
                    deltaText: understanding.importantDetails.joined(separator: "\n"),
                    timestamp: now,
                    fingerprint: currentFingerprint
                )
                activeFingerprintByTerminalID[id] = currentFingerprint
                DebugLogger.log("[AgentStateMonitor] Firing event: terminal=\(id.prefix(8)) agent=\(understanding.agentIdentity) state=\(current)")
                onEvent?(event)
            }

            previousAgentStateByTerminalID[id] = current
        }

        for id in previousAgentStateByTerminalID.keys where !activeIDs.contains(id) {
            previousAgentStateByTerminalID.removeValue(forKey: id)
            activeFingerprintByTerminalID.removeValue(forKey: id)
        }
    }

    private static func isActionable(_ state: AgentInteractionState) -> Bool {
        state == .waitingApproval ||
            state == .waitingChoice ||
            state == .waitingText ||
            state == .error
    }

    private static func isUrgent(_ state: AgentInteractionState) -> Bool {
        state == .waitingApproval ||
            state == .waitingChoice ||
            state == .error
    }

    private func fingerprint(for understanding: TerminalUnderstanding) -> String {
        let details = understanding.importantDetails
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let options = understanding.agentInteractionContext.optionsArray?
            .joined(separator: "\n") ?? ""

        return [
            understanding.terminalID,
            understanding.agentIdentity.rawValue,
            understanding.agentInteractionState.rawValue,
            details,
            options,
        ].joined(separator: "|")
    }
}
```

- [ ] **Step 4: Update old event call sites**

Search:

```bash
rg -n "AgentNeedsAttentionEvent\\(" macos/Sources macos/Tests
```

Every call must include `fingerprint:`. In tests where the exact fingerprint does
not matter, use:

```swift
fingerprint: "term-1|kimi|waitingApproval|test"
```

- [ ] **Step 5: Run monitor tests**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/AgentStateMonitorTests \
  test
```

Expected after implementation:

```text
Test Suite 'AgentStateMonitorTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift \
  macos/Sources/Features/AIForeman/AgentStateMonitor.swift \
  macos/Tests/Terminal/AgentStateMonitorTests.swift
git commit -m "fix: fingerprint agent attention events"
```

---

## Task 2: Hidden Reactive Context

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanAgent.swift`
- Modify: `macos/Sources/Features/AIForeman/AnthropicClient.swift`
- Modify: `macos/Sources/Features/AIForeman/OpenAIClient.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

- [ ] **Step 1: Confirm failing hidden-context test**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/ForemanAgentTests \
  test
```

Expected before implementation:

```text
Value of type 'ForemanConversation' has no member 'hiddenContext'
```

- [ ] **Step 2: Add hidden context to `ForemanConversation`**

Add to `ForemanConversation`:

```swift
@Published private(set) var hiddenContext: [String] = []
```

Update `start` and `stop`:

```swift
func start(goal: String, mode: AgentMode = .interactive) {
    self.goal = goal
    self.mode = mode
    self.isRunning = true
    self.status = .observing
    self.iterationCount = 0
    self.errorMessage = nil
    self.lastOverview = nil
    self.lastUnderstandings = []
    self.hiddenContext = []
    addMessage(role: .user, content: goal)
}

func stop() {
    isRunning = false
    status = .idle
    lastOverview = nil
    lastUnderstandings = []
}
```

Add helper:

```swift
func addHiddenContext(_ content: String) {
    hiddenContext.append(content)
    if hiddenContext.count > 20 {
        hiddenContext.removeFirst(hiddenContext.count - 20)
    }
}
```

- [ ] **Step 3: Store reactive context as hidden context**

Replace this block in `ForemanAgent.react(to:captureSnapshots:)`:

```swift
await MainActor.run {
    conversation.addMessage(
        role: .user,
        content: contextMessage
    )
}
```

with:

```swift
await MainActor.run {
    conversation.addHiddenContext(contextMessage)
}
```

- [ ] **Step 4: Include hidden context in Anthropic prompt**

In `AnthropicClient.agentStep(...)`, read:

```swift
let hiddenContext = await MainActor.run { conversation.hiddenContext }
```

Pass it into `agentStepPrompt` by adding a parameter:

```swift
hiddenContext: hiddenContext,
```

Update `agentStepPrompt` signature:

```swift
private static func agentStepPrompt(
    goal: String,
    latestUserMessage: String,
    mode: String,
    iterationCount: Int,
    messages: [ConversationMessage],
    hiddenContext: [String],
    understandings: [TerminalUnderstanding],
    overview: TerminalOverview,
    terminals: [TerminalSnapshot],
    lastOutcome: TerminalOutcomeReport?,
    using encoder: JSONEncoder
) -> String
```

Add this prompt section after conversation history:

```swift
        Hidden runtime context:
        \(encode(hiddenContext, using: encoder))
```

- [ ] **Step 5: Mirror hidden context in OpenAI prompt**

Apply the same `hiddenContext` parameter/read/prompt-section changes to
`OpenAIClient.agentStep(...)` and `OpenAIClient.agentStepPrompt(...)`.

- [ ] **Step 6: Run Foreman agent tests**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/ForemanAgentTests \
  test
```

Expected:

```text
Test Suite 'ForemanAgentTests' passed
```

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/AIForeman/ForemanConversation.swift \
  macos/Sources/Features/AIForeman/ForemanAgent.swift \
  macos/Sources/Features/AIForeman/AnthropicClient.swift \
  macos/Sources/Features/AIForeman/OpenAIClient.swift \
  macos/Tests/Terminal/ForemanAgentTests.swift
git commit -m "fix: keep reactive context out of visible chat"
```

---

## Task 3: Pending Attention Store

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Add failing pending-attention tests**

Append to `ForemanSidebarStoreTests`:

```swift
@Test
@MainActor
func upsertPendingAttentionProjectsOntoTerminalRow() {
    let store = ForemanSidebarStore()
    let snapshot = TerminalSnapshot.makePreview(
        terminalID: "term-1",
        windowID: "window-1",
        tabID: "tab-1",
        title: "Kimi",
        cwd: "/tmp/project",
        isFocused: false,
        visibleText: "Shell is requesting approval to run command",
        recentScrollbackLines: [],
        lastInputPreview: nil
    )

    store.applySnapshots([snapshot])
    let attention = PendingAgentAttention(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingApproval,
        fingerprint: "term-1|kimi|waitingApproval|ls",
        title: "Needs your approval",
        description: "Shell is requesting approval to run command",
        detail: "ls -la",
        actions: [
            .init(id: "approve_once", title: "Approve once", payload: "1", style: .primary),
            .init(id: "reject", title: "Reject", payload: "3", style: .destructive),
        ]
    )

    store.upsertPendingAttention(attention)

    #expect(store.terminalRows.first?.pendingAttention == attention)
    #expect(store.pendingAttentionByTerminalID["term-1"] == attention)
}

@Test
@MainActor
func resolvingPendingAttentionRemovesItFromRows() {
    let store = ForemanSidebarStore()
    let snapshot = TerminalSnapshot.makePreview(
        terminalID: "term-1",
        windowID: "window-1",
        tabID: "tab-1",
        title: "Kimi",
        cwd: "/tmp/project",
        isFocused: false,
        visibleText: "Shell is requesting approval to run command",
        recentScrollbackLines: [],
        lastInputPreview: nil
    )
    let attention = PendingAgentAttention(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingApproval,
        fingerprint: "fp-1",
        title: "Needs your approval",
        description: "Run command?",
        detail: nil,
        actions: [.init(id: "approve_once", title: "Approve once", payload: "1", style: .primary)]
    )

    store.applySnapshots([snapshot])
    store.upsertPendingAttention(attention)
    store.resolvePendingAttention(terminalID: "term-1", fingerprint: "fp-1")

    #expect(store.pendingAttentionByTerminalID["term-1"] == nil)
    #expect(store.terminalRows.first?.pendingAttention == nil)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests \
  test
```

Expected before implementation:

```text
Cannot find 'PendingAgentAttention' in scope
```

- [ ] **Step 3: Add pending-attention models**

Add near the top of `ForemanSidebarStore.swift`:

```swift
enum PendingAgentActionStyle: String, Codable, Equatable, Sendable {
    case primary
    case secondary
    case destructive
}

struct PendingAgentAction: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let payload: String
    let style: PendingAgentActionStyle
}

struct PendingAgentAttention: Identifiable, Codable, Equatable, Sendable {
    enum ResolutionState: String, Codable, Equatable, Sendable {
        case unresolved
        case sending
        case resolved
    }

    let terminalID: String
    let agentIdentity: AgentIdentity
    let interactionState: AgentInteractionState
    let fingerprint: String
    let title: String
    let description: String
    let detail: String?
    let actions: [PendingAgentAction]
    var resolutionState: ResolutionState
    var errorMessage: String?
    let createdAt: Date

    var id: String { terminalID }

    init(
        terminalID: String,
        agentIdentity: AgentIdentity,
        interactionState: AgentInteractionState,
        fingerprint: String,
        title: String,
        description: String,
        detail: String?,
        actions: [PendingAgentAction],
        resolutionState: ResolutionState = .unresolved,
        errorMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.terminalID = terminalID
        self.agentIdentity = agentIdentity
        self.interactionState = interactionState
        self.fingerprint = fingerprint
        self.title = title
        self.description = description
        self.detail = detail
        self.actions = actions
        self.resolutionState = resolutionState
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Project pending attention onto rows**

Add to `TerminalSummaryRowModel`:

```swift
var pendingAttention: PendingAgentAttention?
```

Add to `ForemanSidebarStore`:

```swift
@Published private(set) var pendingAttentionByTerminalID: [String: PendingAgentAttention] = [:]
```

In every `TerminalSummaryRowModel(...)` initializer inside
`ForemanSidebarStore`, pass:

```swift
pendingAttention: pendingAttentionByTerminalID[snapshot.terminalID],
```

- [ ] **Step 5: Add pending-attention lifecycle helpers**

Add to `ForemanSidebarStore`:

```swift
func upsertPendingAttention(_ attention: PendingAgentAttention) {
    pendingAttentionByTerminalID[attention.terminalID] = attention
    applyPendingAttentionToRows()
    selectedTerminalID = attention.terminalID
    showSidebar()
}

func resolvePendingAttention(terminalID: String, fingerprint: String) {
    guard pendingAttentionByTerminalID[terminalID]?.fingerprint == fingerprint else { return }
    pendingAttentionByTerminalID.removeValue(forKey: terminalID)
    applyPendingAttentionToRows()
}

func markPendingAttentionSending(terminalID: String, fingerprint: String) {
    guard pendingAttentionByTerminalID[terminalID]?.fingerprint == fingerprint else { return }
    pendingAttentionByTerminalID[terminalID]?.resolutionState = .sending
    pendingAttentionByTerminalID[terminalID]?.errorMessage = nil
    applyPendingAttentionToRows()
}

func markPendingAttentionFailed(terminalID: String, fingerprint: String, message: String) {
    guard pendingAttentionByTerminalID[terminalID]?.fingerprint == fingerprint else { return }
    pendingAttentionByTerminalID[terminalID]?.resolutionState = .unresolved
    pendingAttentionByTerminalID[terminalID]?.errorMessage = message
    applyPendingAttentionToRows()
}

private func applyPendingAttentionToRows() {
    terminalRows = terminalRows.map { row in
        var next = row
        next.pendingAttention = pendingAttentionByTerminalID[row.terminalID]
        return next
    }
}
```

At the end of `applySnapshots`, remove pending attention for closed terminals:

```swift
let activeTerminalIDs = Set(snapshots.map(\.terminalID))
pendingAttentionByTerminalID = pendingAttentionByTerminalID.filter { activeTerminalIDs.contains($0.key) }
applyPendingAttentionToRows()
```

- [ ] **Step 6: Run store tests**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests \
  test
```

Expected:

```text
Test Suite 'ForemanSidebarStoreTests' passed
```

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/AIForeman/ForemanSidebarStore.swift \
  macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "feat: add pending agent attention store"
```

---

## Task 4: Terminal Card Pending-Attention Actions

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Test: `macos/Tests/Terminal/SuggestedActionButtonTests.swift` or `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Add action callback to store**

Add to `ForemanSidebarStore`:

```swift
var onExecutePendingAttentionAction: ((PendingAgentAttention, PendingAgentAction) -> Void)?

func executePendingAttentionAction(_ attention: PendingAgentAttention, action: PendingAgentAction) {
    onExecutePendingAttentionAction?(attention, action)
}
```

- [ ] **Step 2: Render pending attention before suggested actions**

In `TerminalSummaryRow.body`, before the existing suggested-actions block, add:

```swift
if let attention = row.pendingAttention {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
            Image(systemName: iconForContextType(attention.agentInteractionState.rawValue))
                .font(.system(size: 11))
                .foregroundStyle(colorForContextType(attention.agentInteractionState.rawValue))

            Text(attention.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colorForContextType(attention.agentInteractionState.rawValue))
        }

        Text(attention.description)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

        if let detail = attention.detail, !detail.isEmpty {
            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }

        HStack(spacing: 6) {
            ForEach(attention.actions.prefix(4)) { action in
                Button(action.title) {
                    onExecutePendingAttentionAction?(attention, action)
                }
                .buttonStyle(PendingAgentActionButtonStyle(style: action.style))
                .controlSize(.small)
                .disabled(attention.resolutionState == .sending)
            }
        }

        if let errorMessage = attention.errorMessage, !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    .padding(.top, 6)
}
```

Update `TerminalSummaryRow` properties:

```swift
var onExecutePendingAttentionAction: ((PendingAgentAttention, PendingAgentAction) -> Void)?
```

Add button style:

```swift
struct PendingAgentActionButtonStyle: ButtonStyle {
    let style: PendingAgentActionStyle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return .white
        case .secondary:
            return .primary
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch style {
        case .primary:
            return isPressed ? Color.blue.opacity(0.75) : Color.blue
        case .secondary:
            return isPressed ? Color.secondary.opacity(0.25) : Color.secondary.opacity(0.12)
        case .destructive:
            return isPressed ? Color.red.opacity(0.75) : Color.red
        }
    }
}
```

- [ ] **Step 3: Wire callback from `ForemanChatView`**

Where `TerminalSummaryRow` is created in `ForemanChatView`, pass:

```swift
onExecutePendingAttentionAction: { attention, action in
    store.executePendingAttentionAction(attention, action: action)
}
```

- [ ] **Step 4: Build UI target**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/AIForeman/TerminalSummaryRow.swift \
  macos/Sources/Features/AIForeman/ForemanSidebarStore.swift \
  macos/Sources/Features/AIForeman/ForemanChatView.swift
git commit -m "feat: render pending agent actions on terminal cards"
```

---

## Task 5: Deterministic Event Routing in AppDelegate

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Modify: `macos/Sources/Features/Terminal/BaseTerminalController.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Add deterministic attention builder**

Add private helper to `AppDelegate`:

```swift
@MainActor
private func makePendingAttention(
    from event: AgentNeedsAttentionEvent,
    understanding: TerminalUnderstanding?
) -> PendingAgentAttention? {
    switch event.interactionState {
    case .waitingApproval:
        let actions: [PendingAgentAction]
        if event.agentIdentity == .kimi {
            actions = [
                .init(id: "approve_once", title: "Approve once", payload: "1", style: .primary),
                .init(id: "approve_session", title: "Approve session", payload: "2", style: .secondary),
                .init(id: "reject", title: "Reject", payload: "3", style: .destructive),
            ]
        } else {
            actions = [
                .init(id: "approve", title: "Approve", payload: "y", style: .primary),
                .init(id: "reject", title: "Reject", payload: "n", style: .destructive),
            ]
        }

        return PendingAgentAttention(
            terminalID: event.terminalID,
            agentIdentity: event.agentIdentity,
            interactionState: event.interactionState,
            fingerprint: event.fingerprint,
            title: "Needs your approval",
            description: understanding?.agentInteractionContext.descriptionString ?? event.deltaText,
            detail: understanding?.agentInteractionContext.detailString,
            actions: actions
        )

    case .waitingChoice:
        let options = understanding?.agentInteractionContext.optionsArray ?? []
        guard !options.isEmpty else { return nil }
        let actions = options.prefix(4).enumerated().map { index, option in
            PendingAgentAction(
                id: "choice_\(index + 1)",
                title: option,
                payload: "\(index + 1)",
                style: index == 0 ? .primary : .secondary
            )
        }

        return PendingAgentAttention(
            terminalID: event.terminalID,
            agentIdentity: event.agentIdentity,
            interactionState: event.interactionState,
            fingerprint: event.fingerprint,
            title: "Choose an option",
            description: understanding?.agentInteractionContext.descriptionString ?? event.deltaText,
            detail: nil,
            actions: actions
        )

    default:
        return nil
    }
}
```

- [ ] **Step 2: Route deterministic monitor events to pending attention**

In `refreshAIForemanSidebar`, assign the latest understandings before invoking
the monitor so event routing can resolve the event against current terminal
state:

```swift
aiForemanPreviousUnderstandings = Dictionary(
    uniqueKeysWithValues: understandings.map { ($0.terminalID, $0) }
)

agentStateMonitor.observe(understandings: understandings)
```

Remove any later duplicate assignment in the same method.

In `agentStateMonitor.onEvent`, before calling `ForemanAgent.react`, find the
matching store and current understanding:

```swift
let allControllers = TerminalController.all
let targetController = allControllers.first { controller in
    controller.surfaceTree.contains { $0.id.uuidString == event.terminalID }
}
guard let targetController else { return }
let store = targetController.foremanSidebarStore
let understanding = self.aiForemanPreviousUnderstandings[event.terminalID]
```

Then route deterministic events:

```swift
if let attention = self.makePendingAttention(from: event, understanding: understanding) {
    store.upsertPendingAttention(attention)
    return
}
```

Only after that should the code call `ForemanAgent.react` for semantic events.

- [ ] **Step 3: Wire pending action execution**

In `BaseTerminalController` store setup, add:

```swift
foremanSidebarStore.onExecutePendingAttentionAction = { [weak self] attention, action in
    guard let self else { return }
    (NSApp.delegate as? AppDelegate)?.executePendingAttentionAction(
        attention,
        action: action,
        store: self.foremanSidebarStore
    )
}
```

Add to `AppDelegate`:

```swift
@MainActor
func executePendingAttentionAction(
    _ attention: PendingAgentAttention,
    action: PendingAgentAction,
    store: ForemanSidebarStore
) {
    store.markPendingAttentionSending(
        terminalID: attention.terminalID,
        fingerprint: attention.fingerprint
    )

    guard let controller = terminalController(for: attention.terminalID) else {
        store.markPendingAttentionFailed(
            terminalID: attention.terminalID,
            fingerprint: attention.fingerprint,
            message: "This terminal is no longer available."
        )
        return
    }

    let item = DispatchQueueItem(terminalID: attention.terminalID, message: action.payload)
    guard dispatchQueueCoordinator.send(item, through: controller) else {
        store.markPendingAttentionFailed(
            terminalID: attention.terminalID,
            fingerprint: attention.fingerprint,
            message: "Unable to send this action."
        )
        return
    }

    agentStateMonitor.resolve(
        terminalID: attention.terminalID,
        fingerprint: attention.fingerprint
    )
    store.resolvePendingAttention(
        terminalID: attention.terminalID,
        fingerprint: attention.fingerprint
    )
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/AgentStateMonitorTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests \
  -only-testing:GhosttyTests/ForemanAgentTests \
  test
```

Expected:

```text
Test Suite 'AgentStateMonitorTests' passed
Test Suite 'ForemanSidebarStoreTests' passed
Test Suite 'ForemanAgentTests' passed
```

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift \
  macos/Sources/Features/Terminal/BaseTerminalController.swift \
  macos/Sources/Features/AIForeman/ForemanSidebarStore.swift
git commit -m "feat: route deterministic agent attention to cards"
```

---

## Task 6: Reactive UI Phase Without Goal

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanModels.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

- [ ] **Step 1: Add failing UI phase test**

Append to `ForemanAgentTests`:

```swift
@Test
func uiPhaseCanAwaitApprovalWithoutGoal() {
    let phase = ConversationUIPhase.resolve(
        goal: nil,
        isRunning: true,
        status: .waitingForUser,
        lastAction: .sendCommand(
            terminalID: "term-1",
            command: "1",
            reason: "Approve once"
        )
    )

    #expect(phase == .awaitingApproval(command: "1"))
}
```

- [ ] **Step 2: Change phase resolution order**

Update `ConversationUIPhase.resolve`:

```swift
static func resolve(
    goal: String?,
    isRunning: Bool,
    status: AgentStatus,
    lastAction: AgentAction?
) -> Self {
    if status == .waitingForUser {
        if case .sendCommand(_, let command, _) = lastAction {
            return .awaitingApproval(command: command)
        }
        return .awaitingReply
    }

    guard goal != nil else { return .readyToStart }

    if isRunning {
        switch status {
        case .observing, .planning, .executing:
            return .processing
        default:
            break
        }
    }

    return .chatting
}
```

- [ ] **Step 3: Run Foreman agent tests**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/ForemanAgentTests \
  test
```

Expected:

```text
Test Suite 'ForemanAgentTests' passed
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/AIForeman/ForemanModels.swift \
  macos/Tests/Terminal/ForemanAgentTests.swift
git commit -m "fix: allow reactive approval without a goal"
```

---

## Task 7: Final Verification

**Files:**
- No source changes unless verification exposes a bug.

- [ ] **Step 1: Run focused AIForeman tests**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" \
  -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/AgentStateMonitorTests \
  -only-testing:GhosttyTests/ForemanAgentTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests \
  -only-testing:GhosttyTests/ForemanServiceTests \
  -only-testing:GhosttyTests/AnthropicClientTests \
  -only-testing:GhosttyTests/TerminalUnderstandingTests \
  -only-testing:GhosttyTests/ForemanAgentDeltaIntegrationTests \
  test
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 2: Run full macOS tests**

Run:

```bash
macos/build.nu --scheme Ghostty --configuration Debug --action test
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 3: Manual Kimi checklist**

Run the built app and verify:

```bash
open /Users/nambouchara/speed2/ghostty/macos/build/Debug/Foreman.app
```

Manual checks:

- Start Kimi in a terminal.
- Kimi welcome screen does not trigger a Foreman card.
- Ask Kimi to run a shell command requiring approval.
- One terminal card appears with approval actions.
- No raw "Kimi in terminal..." context appears in chat.
- Clicking "Approve once" sends `1`.
- The pending card clears after send.
- Trigger a different approval and verify a new card appears.

- [ ] **Step 4: Commit verification fixes if any**

If verification required fixes:

```bash
git add macos/Sources/App/macOS/AppDelegate.swift \
  macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift \
  macos/Sources/Features/AIForeman/AgentStateMonitor.swift \
  macos/Sources/Features/AIForeman/ForemanAgent.swift \
  macos/Sources/Features/AIForeman/ForemanConversation.swift \
  macos/Sources/Features/AIForeman/ForemanModels.swift \
  macos/Sources/Features/AIForeman/ForemanSidebarStore.swift \
  macos/Sources/Features/AIForeman/TerminalSummaryRow.swift \
  macos/Sources/Features/Terminal/BaseTerminalController.swift \
  macos/Tests/Terminal/AgentStateMonitorTests.swift \
  macos/Tests/Terminal/ForemanAgentTests.swift \
  macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "fix: polish card-first Foreman attention flow"
```

If no fixes were required, do not create an empty commit.
