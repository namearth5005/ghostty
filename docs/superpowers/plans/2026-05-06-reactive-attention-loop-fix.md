# Reactive Attention Loop Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current reactive approval loop with a stable pending-attention workflow that shows one deterministic terminal-card action and does not call the LLM for approval/choice prompts.

**Architecture:** `AgentStateMonitor` fingerprints actionable requests and emits only new unresolved fingerprints. `ForemanSidebarStore` owns pending attention state keyed by terminal ID, and `TerminalSummaryRow` renders that state. `AppDelegate` routes deterministic approval/choice events into pending attention instead of `ForemanAgent.react(to:)`; semantic events can still call the LLM with hidden context.

**Tech Stack:** Swift, SwiftUI, Swift Testing, existing Foreman AIForeman models and Xcode test runner.

---

## File Structure

- Modify `macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift`: add a stable request fingerprint and display fields carried from the monitor.
- Modify `macos/Sources/Features/AIForeman/AgentStateMonitor.swift`: replace one-refresh suppression with unresolved fingerprint suppression.
- Modify `macos/Tests/Terminal/AgentStateMonitorTests.swift`: cover unchanged approval suppression, changed-fingerprint re-fire, and explicit resolution.
- Modify `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`: add `PendingAgentAttention` state and lifecycle helpers.
- Modify `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift`: render pending attention actions before generic suggested actions.
- Modify `macos/Sources/App/macOS/AppDelegate.swift`: route deterministic events to pending attention, resolve on click, and only invoke `ForemanAgent` for semantic states.
- Modify `macos/Sources/Features/AIForeman/ForemanConversation.swift`: support hidden context messages that are used for LLM prompt context but not rendered in chat.
- Modify `macos/Sources/Features/AIForeman/ForemanAgent.swift`: use hidden context for reactive LLM calls instead of visible `.user` messages.
- Modify `macos/Sources/Features/AIForeman/AnthropicClient.swift` and `macos/Sources/Features/AIForeman/OpenAIClient.swift`: include hidden context in prompts without changing visible message history.
- Modify `macos/Tests/Terminal/ForemanAgentTests.swift`: cover no visible context message and reactive UI phase behavior.

---

## Task 1: Fingerprint Agent Attention Events

**Files:**
- Modify: `macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift`
- Modify: `macos/Sources/Features/AIForeman/AgentStateMonitor.swift`
- Test: `macos/Tests/Terminal/AgentStateMonitorTests.swift`

- [ ] **Step 1: Write failing tests for stable suppression**

Add these tests to `AgentStateMonitorTests`:

```swift
@Test
func unchangedApprovalFingerprintFiresOnlyOnceUntilResolved() {
    let monitor = AgentStateMonitor()
    var capturedEvents: [AgentNeedsAttentionEvent] = []
    monitor.onEvent = { capturedEvents.append($0) }

    monitor.observe(understandings: [
        makeUnderstanding(
            terminalID: "term-1",
            state: .waiting,
            interactionState: .waitingApproval,
            identity: .kimi,
            details: ["Shell is requesting approval to run command: ls -la"]
        )
    ])
    monitor.observe(understandings: [
        makeUnderstanding(
            terminalID: "term-1",
            state: .waiting,
            interactionState: .waitingApproval,
            identity: .kimi,
            details: ["Shell is requesting approval to run command: ls -la"]
        )
    ])
    monitor.observe(understandings: [
        makeUnderstanding(
            terminalID: "term-1",
            state: .waiting,
            interactionState: .waitingApproval,
            identity: .kimi,
            details: ["Shell is requesting approval to run command: ls -la"]
        )
    ])

    #expect(capturedEvents.count == 1)
    #expect(capturedEvents.first?.fingerprint.contains("ls -la") == true)
}

@Test
func changedApprovalFingerprintFiresAgain() {
    let monitor = AgentStateMonitor()
    var capturedEvents: [AgentNeedsAttentionEvent] = []
    monitor.onEvent = { capturedEvents.append($0) }

    monitor.observe(understandings: [
        makeUnderstanding(
            terminalID: "term-1",
            state: .waiting,
            interactionState: .waitingApproval,
            identity: .kimi,
            details: ["Shell is requesting approval to run command: ls -la"]
        )
    ])
    monitor.observe(understandings: [
        makeUnderstanding(
            terminalID: "term-1",
            state: .waiting,
            interactionState: .waitingApproval,
            identity: .kimi,
            details: ["Shell is requesting approval to run command: git status"]
        )
    ])

    #expect(capturedEvents.count == 2)
    #expect(capturedEvents[0].fingerprint != capturedEvents[1].fingerprint)
}

@Test
func resolvedFingerprintCanFireAgain() {
    let monitor = AgentStateMonitor()
    var capturedEvents: [AgentNeedsAttentionEvent] = []
    monitor.onEvent = { capturedEvents.append($0) }

    monitor.observe(understandings: [
        makeUnderstanding(
            terminalID: "term-1",
            state: .waiting,
            interactionState: .waitingApproval,
            identity: .kimi,
            details: ["Shell is requesting approval to run command: ls -la"]
        )
    ])
    let fingerprint = capturedEvents[0].fingerprint
    monitor.resolve(terminalID: "term-1", fingerprint: fingerprint)
    monitor.observe(understandings: [
        makeUnderstanding(
            terminalID: "term-1",
            state: .waiting,
            interactionState: .waitingApproval,
            identity: .kimi,
            details: ["Shell is requesting approval to run command: ls -la"]
        )
    ])

    #expect(capturedEvents.count == 2)
}
```

Update the local helper signature:

```swift
private func makeUnderstanding(
    terminalID: String,
    state: TerminalUnderstandingState,
    interactionState: AgentInteractionState,
    identity: AgentIdentity = .kimi,
    details: [String] = ["Test detail"]
) -> TerminalUnderstanding {
    TerminalUnderstanding.preview(
        terminalID: terminalID,
        state: state,
        shortExplanation: "Test understanding",
        lastMeaningfulEvent: details.first ?? "Test event",
        importantDetails: details,
        suggestedNextActions: [],
        agentIdentity: identity,
        agentInteractionState: interactionState
    )
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/AgentStateMonitorTests
```

Expected: compile failure because `AgentNeedsAttentionEvent.fingerprint` and `AgentStateMonitor.resolve` do not exist.

- [ ] **Step 3: Add fingerprint to the event**

Update `AgentNeedsAttentionEvent`:

```swift
struct AgentNeedsAttentionEvent: Sendable {
    let terminalID: String
    let agentIdentity: AgentIdentity
    let interactionState: AgentInteractionState
    let deltaText: String
    let fingerprint: String
    let timestamp: Date
}
```

- [ ] **Step 4: Implement unresolved fingerprint suppression**

Replace the current `foremanReactedToState` dictionary in `AgentStateMonitor` with:

```swift
private var activeFingerprintByTerminalID: [String: String] = [:]
```

Add:

```swift
func resolve(terminalID: String, fingerprint: String) {
    guard activeFingerprintByTerminalID[terminalID] == fingerprint else { return }
    activeFingerprintByTerminalID.removeValue(forKey: terminalID)
    lastEventByTerminalID.removeValue(forKey: terminalID)
    DebugLogger.log("[AgentStateMonitor] Resolved terminal \(terminalID.prefix(8)) fingerprint \(fingerprint)")
}

private func fingerprint(for understanding: TerminalUnderstanding) -> String {
    let details = understanding.importantDetails
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return [
        understanding.terminalID,
        understanding.agentIdentity.rawValue,
        understanding.agentInteractionState.rawValue,
        details
    ].joined(separator: "|")
}
```

In `observe(understandings:)`, compute the fingerprint after `current`:

```swift
let currentFingerprint = fingerprint(for: understanding)
```

Before firing, suppress unchanged waiting fingerprints:

```swift
if let activeFingerprint = activeFingerprintByTerminalID[id],
   activeFingerprint == currentFingerprint {
    DebugLogger.log("[AgentStateMonitor] Skipping unchanged fingerprint: terminal=\(id.prefix(8)) state=\(current)")
    previousAgentStateByTerminalID[id] = current
    continue
}
```

When firing an event, include and store the fingerprint:

```swift
let event = AgentNeedsAttentionEvent(
    terminalID: id,
    agentIdentity: understanding.agentIdentity,
    interactionState: current,
    deltaText: understanding.importantDetails.joined(separator: "\n"),
    fingerprint: currentFingerprint,
    timestamp: now
)
onEvent?(event)
lastEventByTerminalID[id] = now
activeFingerprintByTerminalID[id] = currentFingerprint
```

When a terminal leaves waiting states, clear active suppression:

```swift
if current != .waitingApproval && current != .waitingChoice && current != .waitingText && current != .error {
    activeFingerprintByTerminalID.removeValue(forKey: id)
}
```

Remove `notifyForemanReacted(terminalID:state:)` call sites after Task 4 updates `AppDelegate`.

- [ ] **Step 5: Run monitor tests**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/AgentStateMonitorTests
```

Expected: all `AgentStateMonitorTests` pass.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift macos/Sources/Features/AIForeman/AgentStateMonitor.swift macos/Tests/Terminal/AgentStateMonitorTests.swift
git commit -m "fix: suppress repeated agent attention fingerprints"
```

---

## Task 2: Add Pending Attention State To Sidebar Store

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Add tests to `ForemanSidebarStoreTests`:

```swift
@MainActor
func testPendingAttentionIsAppliedToTerminalRow() {
    let store = ForemanSidebarStore()
    let snapshot = TerminalSnapshot.preview(terminalID: "term-1", title: "Kimi Code")
    let attention = PendingAgentAttention(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingApproval,
        fingerprint: "term-1|kimi|waitingApproval|ls",
        title: "Needs your approval",
        description: "Shell is requesting approval to run command: ls -la",
        detail: "Shell",
        actions: [
            .init(title: "Approve once", command: "1", role: .primary),
            .init(title: "Reject", command: "3", role: .destructive)
        ],
        errorMessage: nil,
        createdAt: Date(timeIntervalSince1970: 1)
    )

    store.upsertPendingAttention(attention)
    store.applySnapshots([snapshot])

    XCTAssertEqual(store.terminalRows.first?.pendingAttention, attention)
}

@MainActor
func testResolvingPendingAttentionRemovesItFromRows() {
    let store = ForemanSidebarStore()
    let snapshot = TerminalSnapshot.preview(terminalID: "term-1", title: "Kimi Code")
    let attention = PendingAgentAttention(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingApproval,
        fingerprint: "term-1|kimi|waitingApproval|ls",
        title: "Needs your approval",
        description: "Shell is requesting approval to run command: ls -la",
        detail: "Shell",
        actions: [.init(title: "Approve once", command: "1", role: .primary)],
        errorMessage: nil,
        createdAt: Date(timeIntervalSince1970: 1)
    )

    store.upsertPendingAttention(attention)
    store.resolvePendingAttention(terminalID: "term-1", fingerprint: attention.fingerprint)
    store.applySnapshots([snapshot])

    XCTAssertNil(store.terminalRows.first?.pendingAttention)
}
```

If `TerminalSnapshot.preview(terminalID:title:)` does not exist, use the preview initializer pattern already used in this test file and keep the same `terminalID`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: compile failure because `PendingAgentAttention`, `pendingAttention`, and store helper methods do not exist.

- [ ] **Step 3: Add pending attention models**

Add these models near `TerminalSummaryRowModel`:

```swift
struct PendingAgentAttention: Equatable, Sendable {
    let terminalID: String
    let agentIdentity: AgentIdentity
    let interactionState: AgentInteractionState
    let fingerprint: String
    let title: String
    let description: String
    let detail: String?
    let actions: [PendingAgentAction]
    var errorMessage: String?
    let createdAt: Date
}

struct PendingAgentAction: Identifiable, Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case primary
        case secondary
        case destructive
    }

    let id: String
    let title: String
    let command: String
    let role: Role

    init(title: String, command: String, role: Role) {
        self.id = "\(title)|\(command)|\(role.rawValue)"
        self.title = title
        self.command = command
        self.role = role
    }
}
```

Add to `TerminalSummaryRowModel`:

```swift
var pendingAttention: PendingAgentAttention?
```

- [ ] **Step 4: Add store state and lifecycle helpers**

Add to `ForemanSidebarStore`:

```swift
@Published var pendingAttentionByTerminalID: [String: PendingAgentAttention] = [:]
```

Add methods:

```swift
func upsertPendingAttention(_ attention: PendingAgentAttention) {
    pendingAttentionByTerminalID[attention.terminalID] = attention
}

func resolvePendingAttention(terminalID: String, fingerprint: String) {
    guard pendingAttentionByTerminalID[terminalID]?.fingerprint == fingerprint else { return }
    pendingAttentionByTerminalID.removeValue(forKey: terminalID)
}

func failPendingAttention(terminalID: String, fingerprint: String, message: String) {
    guard var attention = pendingAttentionByTerminalID[terminalID],
          attention.fingerprint == fingerprint else { return }
    attention.errorMessage = message
    pendingAttentionByTerminalID[terminalID] = attention
}
```

When constructing every `TerminalSummaryRowModel` in `applySnapshots`, set:

```swift
pendingAttention: pendingAttentionByTerminalID[snapshot.terminalID]
```

When cleaning closed terminals at the start of `applySnapshots`, add:

```swift
let activeTerminalIDs = Set(snapshots.map(\.terminalID))
pendingAttentionByTerminalID = pendingAttentionByTerminalID.filter { activeTerminalIDs.contains($0.key) }
```

- [ ] **Step 5: Run store tests**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: all `ForemanSidebarStoreTests` pass.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/AIForeman/ForemanSidebarStore.swift macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "feat: store pending agent attention"
```

---

## Task 3: Render Pending Attention In Terminal Cards

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift`

- [ ] **Step 1: Replace generic approval buttons with pending attention rendering**

In `TerminalSummaryRow.body`, render pending attention before `agentContextType` actions:

```swift
if let pendingAttention = row.pendingAttention {
    pendingAttentionView(pendingAttention)
        .padding(.top, 4)
} else if let contextType = row.agentContextType {
    agentActionButtons(for: contextType, row: row)
        .padding(.top, 4)
}
```

Add:

```swift
@ViewBuilder
private func pendingAttentionView(_ attention: PendingAgentAttention) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
            Text(attention.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text(attention.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = attention.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }

        HStack(spacing: 8) {
            ForEach(attention.actions) { action in
                Button {
                    onExecuteSuggestion?(attention.terminalID, action.command)
                } label: {
                    Text(action.title)
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(action.role == .primary ? .borderedProminent : .bordered)
                .controlSize(.small)
                .tint(tint(for: action.role))
            }
        }

        if let errorMessage = attention.errorMessage, !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func tint(for role: PendingAgentAction.Role) -> Color {
    switch role {
    case .primary: return .green
    case .secondary: return .blue
    case .destructive: return .red
    }
}
```

- [ ] **Step 2: Keep old generic buttons temporarily**

Do not delete `agentActionButtons(for:row:)` in this task. It remains a fallback for states without pending attention until `AppDelegate` routes all deterministic attention through the store.

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/AIForeman/TerminalSummaryRow.swift
git commit -m "feat: render pending agent attention actions"
```

---

## Task 4: Route Deterministic Events Without Calling The LLM

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

- [ ] **Step 1: Add a routing unit test by extracting deterministic mapping**

Create a small pure helper in `AppDelegate.swift` extension scope:

```swift
enum AgentAttentionRouter {
    static func pendingAttention(for event: AgentNeedsAttentionEvent) -> PendingAgentAttention? {
        switch event.interactionState {
        case .waitingApproval:
            return PendingAgentAttention(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                fingerprint: event.fingerprint,
                title: "Needs your approval",
                description: event.deltaText.isEmpty ? "The agent is waiting for approval." : event.deltaText,
                detail: nil,
                actions: approvalActions(for: event.agentIdentity),
                errorMessage: nil,
                createdAt: event.timestamp
            )
        case .waitingChoice:
            let options = event.deltaText
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !options.isEmpty else { return nil }
            return PendingAgentAttention(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                fingerprint: event.fingerprint,
                title: "Choose an option",
                description: "The agent is waiting for a choice.",
                detail: nil,
                actions: options.prefix(4).map {
                    PendingAgentAction(title: $0, command: $0, role: .secondary)
                },
                errorMessage: nil,
                createdAt: event.timestamp
            )
        default:
            return nil
        }
    }

    private static func approvalActions(for identity: AgentIdentity) -> [PendingAgentAction] {
        switch identity {
        case .kimi:
            return [
                .init(title: "Approve once", command: "1", role: .primary),
                .init(title: "Approve session", command: "2", role: .secondary),
                .init(title: "Reject", command: "3", role: .destructive),
                .init(title: "Tell model...", command: "4", role: .secondary)
            ]
        default:
            return [
                .init(title: "Approve", command: "y", role: .primary),
                .init(title: "Reject", command: "n", role: .destructive)
            ]
        }
    }
}
```

Add tests to `ForemanAgentTests`:

```swift
@Test
func kimiApprovalEventMapsToDeterministicPendingAttention() {
    let event = AgentNeedsAttentionEvent(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingApproval,
        deltaText: "Shell is requesting approval to run command: ls -la",
        fingerprint: "term-1|kimi|waitingApproval|ls",
        timestamp: Date(timeIntervalSince1970: 1)
    )

    let attention = AgentAttentionRouter.pendingAttention(for: event)

    #expect(attention?.actions.map(\.command) == ["1", "2", "3", "4"])
    #expect(attention?.title == "Needs your approval")
}

@Test
func waitingTextEventDoesNotMapToDeterministicPendingAttention() {
    let event = AgentNeedsAttentionEvent(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingText,
        deltaText: "What should I do next?",
        fingerprint: "term-1|kimi|waitingText|next",
        timestamp: Date(timeIntervalSince1970: 1)
    )

    #expect(AgentAttentionRouter.pendingAttention(for: event) == nil)
}
```

- [ ] **Step 2: Run tests**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: new tests pass after helper is added.

- [ ] **Step 3: Route deterministic events in `agentStateMonitor.onEvent`**

In `AppDelegate.applicationDidFinishLaunching`, replace the current unconditional create-agent-and-react block with:

```swift
agentStateMonitor.onEvent = { [weak self] event in
    Task { @MainActor [weak self] in
        guard let self else { return }

        if let attention = AgentAttentionRouter.pendingAttention(for: event),
           let store = self.foremanStore(for: event.terminalID) {
            store.upsertPendingAttention(attention)
            return
        }

        await self.reactSemantically(to: event)
    }
}
```

Add helpers to `AppDelegate`:

```swift
@MainActor
private func foremanStore(for terminalID: String) -> ForemanSidebarStore? {
    terminalController(for: terminalID)?.foremanSidebarStore
}

@MainActor
private func reactSemantically(to event: AgentNeedsAttentionEvent) async {
    guard let foremanService else { return }
    guard FeatureGate.canUseBasicAI() else { return }
    FeatureGate.recordBasicAIUsage()

    if foremanAgent == nil {
        guard let store = foremanStore(for: event.terminalID)
            ?? TerminalController.all.first?.foremanSidebarStore else { return }
        foremanAgent = ForemanAgent(
            conversation: store.conversation,
            foremanService: foremanService,
            onSendCommand: { [weak self] terminalID, command in
                guard let self else { return false }
                guard let controller = self.terminalController(for: terminalID) else { return false }
                let item = DispatchQueueItem(terminalID: terminalID, message: command)
                guard self.dispatchQueueCoordinator.send(item, through: controller) else { return false }
                self.terminalOutcomeEngine.register(terminalID: terminalID, sentCommand: command)
                return true
            },
            onStatusChange: { _ in },
            onAction: { _, _ in }
        )
    }

    await foremanAgent?.react(to: event, captureSnapshots: { [weak self] in
        guard let self else { return [] }
        var allSnapshots: [TerminalSnapshot] = []
        for controller in TerminalController.all {
            allSnapshots.append(contentsOf: controller.captureTerminalSnapshots())
        }
        return allSnapshots
    })
}
```

Remove the old `agentStateMonitor.notifyForemanReacted(...)` call.

- [ ] **Step 4: Resolve pending attention when user clicks a pending action**

Change `ForemanSidebarStore.onExecuteSuggestion` to include the fingerprint:

```swift
var onExecuteSuggestion: ((String, String, String?) -> Void)?
```

Update `executeSuggestion`:

```swift
func executeSuggestion(terminalID: String, command: String, fingerprint: String? = nil) {
    onExecuteSuggestion?(terminalID, command, fingerprint)
}
```

Update callers from terminal rows so pending attention passes `attention.fingerprint` and legacy suggestions pass `nil`.

Update `BaseTerminalController` callback:

```swift
foremanSidebarStore.onExecuteSuggestion = { [weak self] terminalID, command, fingerprint in
    guard let self else { return }
    (NSApp.delegate as? AppDelegate)?.executeSuggestedAction(
        terminalID: terminalID,
        command: command,
        fingerprint: fingerprint,
        store: self.foremanSidebarStore
    )
}
```

Update `AppDelegate.executeSuggestedAction`:

```swift
@MainActor
func executeSuggestedAction(
    terminalID: String,
    command: String,
    fingerprint: String? = nil,
    store: ForemanSidebarStore? = nil
) {
    guard let controller = terminalController(for: terminalID) else {
        if let fingerprint {
            store?.failPendingAttention(terminalID: terminalID, fingerprint: fingerprint, message: "Terminal is no longer available.")
        }
        return
    }
    let item = DispatchQueueItem(terminalID: terminalID, message: command)
    guard dispatchQueueCoordinator.send(item, through: controller) else {
        if let fingerprint {
            store?.failPendingAttention(terminalID: terminalID, fingerprint: fingerprint, message: "Unable to send action.")
        }
        return
    }
    terminalOutcomeEngine.register(terminalID: terminalID, sentCommand: command)
    if let fingerprint {
        store?.resolvePendingAttention(terminalID: terminalID, fingerprint: fingerprint)
        agentStateMonitor.resolve(terminalID: terminalID, fingerprint: fingerprint)
    }
}
```

- [ ] **Step 5: Run targeted tests**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/AgentStateMonitorTests -only-testing:GhosttyTests/ForemanAgentTests -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: all targeted tests pass.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift macos/Sources/Features/Terminal/BaseTerminalController.swift macos/Sources/Features/AIForeman/ForemanSidebarStore.swift macos/Sources/Features/AIForeman/ForemanChatView.swift macos/Sources/Features/AIForeman/TerminalSummaryRow.swift macos/Tests/Terminal/ForemanAgentTests.swift
git commit -m "fix: route deterministic agent attention to cards"
```

---

## Task 5: Hide Reactive Context From Chat

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanAgent.swift`
- Modify: `macos/Sources/Features/AIForeman/AnthropicClient.swift`
- Modify: `macos/Sources/Features/AIForeman/OpenAIClient.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

- [ ] **Step 1: Write failing hidden-context test**

Replace the current expectation in `reactToEventRunsOneIterationAndStops` that looks for a visible Kimi user message with:

```swift
#expect(!messages.contains { $0.role == .user && $0.content.contains("Recent output:") })
#expect(messages.contains { $0.role == .agent && $0.content == "Kimi is waiting for approval." })
```

Add a dedicated test:

```swift
@Test
func reactToEventStoresContextAsHiddenPromptContext() async throws {
    let conversation = await MainActor.run { ForemanConversation() }
    let client = ScriptedForemanClient(responses: [
        try makeStepResponse(
            thought: "Kimi needs a reply.",
            action: AgentAction.respond(message: "I can handle that.")
        ),
    ])
    let agent = makeAgent(
        conversation: conversation,
        client: client,
        commandRecorder: CommandRecorder()
    )

    let event = AgentNeedsAttentionEvent(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingText,
        deltaText: "User asked for a concise answer.",
        fingerprint: "term-1|kimi|waitingText|concise",
        timestamp: Date(timeIntervalSince1970: 1)
    )

    await agent.react(to: event, captureSnapshots: sampleSnapshots)

    let visibleMessages = await MainActor.run { conversation.messages }
    let hiddenContext = await MainActor.run { conversation.hiddenContext }
    #expect(!visibleMessages.contains { $0.content.contains("User asked for a concise answer.") })
    #expect(hiddenContext.contains { $0.contains("User asked for a concise answer.") })
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: compile failure because `hiddenContext` does not exist.

- [ ] **Step 3: Add hidden context to conversation**

In `ForemanConversation`, add:

```swift
@Published private(set) var hiddenContext: [String] = []
```

Add:

```swift
func addHiddenContext(_ content: String) {
    hiddenContext.append(content)
    if hiddenContext.count > 20 {
        hiddenContext.removeFirst(hiddenContext.count - 20)
    }
}
```

In `start(goal:mode:)` and `stop()`, clear it:

```swift
self.hiddenContext = []
```

- [ ] **Step 4: Store reactive context as hidden context**

In `ForemanAgent.react(to:)`, replace:

```swift
conversation.addMessage(role: .user, content: contextMessage)
```

with:

```swift
conversation.addHiddenContext(contextMessage)
```

- [ ] **Step 5: Include hidden context in LLM prompts**

In both clients, read hidden context next to messages:

```swift
let hiddenContext = await MainActor.run { conversation.hiddenContext }
```

Add `hiddenContext: hiddenContext` to `agentStepPrompt(...)`.

Update each `agentStepPrompt` signature:

```swift
hiddenContext: [String],
```

Insert this prompt section before conversation history:

```swift
Hidden reactive context:
\(encode(hiddenContext, using: encoder))
```

- [ ] **Step 6: Run Foreman agent tests**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: all `ForemanAgentTests` pass.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/AIForeman/ForemanConversation.swift macos/Sources/Features/AIForeman/ForemanAgent.swift macos/Sources/Features/AIForeman/AnthropicClient.swift macos/Sources/Features/AIForeman/OpenAIClient.swift macos/Tests/Terminal/ForemanAgentTests.swift
git commit -m "fix: keep reactive context out of visible chat"
```

---

## Task 6: Fix Reactive Waiting UI Phase

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanModels.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

- [ ] **Step 1: Write failing UI phase test**

Add to `ForemanAgentTests`:

```swift
@Test
func uiPhaseShowsApprovalForReactiveSessionWithoutGoal() {
    let phase = ConversationUIPhase.resolve(
        goal: nil,
        isRunning: true,
        status: .waitingForUser,
        lastAction: .sendCommand(terminalID: "term-1", command: "yes", reason: "Approve")
    )

    #expect(phase == .awaitingApproval(command: "yes"))
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests/uiPhaseShowsApprovalForReactiveSessionWithoutGoal
```

Expected: fails because `goal == nil` currently resolves to `.readyToStart`.

- [ ] **Step 3: Make waiting status take precedence over goal**

In `ConversationUIPhase.resolve`, move the `status == .waitingForUser` block above the `goal` guard:

```swift
if status == .waitingForUser {
    if case .sendCommand(_, let command, _) = lastAction {
        return .awaitingApproval(command: command)
    }
    return .awaitingReply
}

guard goal != nil else { return .readyToStart }
```

- [ ] **Step 4: Run Foreman agent tests**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: all `ForemanAgentTests` pass.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/AIForeman/ForemanModels.swift macos/Tests/Terminal/ForemanAgentTests.swift
git commit -m "fix: show reactive approval controls without goal"
```

---

## Task 7: Final Verification

**Files:**
- Verify all changed files from Tasks 1-6.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/AgentStateMonitorTests -only-testing:GhosttyTests/ForemanAgentTests -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: all targeted tests pass.

- [ ] **Step 2: Build the app**

Run:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug
```

Expected: build succeeds.

- [ ] **Step 3: Manual verification**

Launch the app:

```bash
open /Users/nambouchara/Library/Developer/Xcode/DerivedData/Ghostty-gbgqgpplpmuptgbhinobncpfzleh/Build/Products/Debug/Foreman.app
```

Manual checks:

- Open Kimi at the welcome screen and wait 10 seconds. Expected: no reactive card and no chat message.
- Ask Kimi to run a shell command that requires approval. Expected: one card appears with `Approve once`, `Approve session`, `Reject`, `Tell model...`.
- Wait 30 seconds without clicking. Expected: no duplicated card and no new chat messages.
- Click `Approve once`. Expected: Kimi receives `1`; pending card disappears after send.
- Trigger a second different approval. Expected: one new card appears.
- Trigger a text-input wait. Expected: if Foreman suggests a reply, no raw "Recent output" context appears in chat.

- [ ] **Step 4: Inspect diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: no whitespace errors, and the diff only touches files in this plan.

- [ ] **Step 5: Commit final cleanup if needed**

If Step 4 reveals only small formatting or test-cleanup changes, commit them:

```bash
git add macos/Sources/Features/AIForeman macos/Sources/App/macOS/AppDelegate.swift macos/Sources/Features/Terminal/BaseTerminalController.swift macos/Tests/Terminal
git commit -m "test: verify reactive attention workflow"
```

If there are no cleanup changes, do not create an empty commit.

---

## Self-Review

Spec coverage:

- Deterministic approval and choice states avoid LLM calls: Task 4.
- Stable event suppression until resolution or fingerprint change: Task 1.
- Pending terminal-card source of truth: Tasks 2 and 3.
- Hidden context instead of visible chat pollution: Task 5.
- Reactive waiting UI without manual goal: Task 6.
- Error handling for failed sends: Task 4.
- Final build/manual verification: Task 7.

Placeholder scan:

- No task uses deferred markers or vague steps.
- Every code-changing step includes concrete code or exact replacement instructions.

Type consistency:

- `PendingAgentAttention`, `PendingAgentAction`, and `fingerprint` names are consistent across tasks.
- `executeSuggestion(terminalID:command:fingerprint:)` callback signature is consistent across store, row, base controller, and app delegate steps.
