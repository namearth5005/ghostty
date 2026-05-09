# Connected Foreman Terminal Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Foreman's terminal attention cards and bottom chat so typed chat replies target the right waiting terminal, while ambiguous multi-terminal cases ask for a target.

**Architecture:** Add a small input-routing model around existing `PendingAgentAttention` state. Terminal rows remain the compact navigator; the chat view renders the selected pending terminal as the active workspace and sends typed replies through the same AppDelegate send/resolve path as existing card buttons.

**Tech Stack:** Swift, SwiftUI, Swift Testing, macOS Ghostty/Foreman app.

---

## File Structure

- Create `macos/Sources/Features/AIForeman/ForemanInputRouting.swift`
  - Owns routing value types: `ForemanInputIntent`, `ForemanChatTarget`, `ForemanInputResolution`, and `ForemanTargetOption`.
  - Pure data, no AppKit or SwiftUI dependency.

- Modify `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
  - Computes selected pending attention and chat target state.
  - Routes chat text into either terminal reply, Foreman guidance, or ambiguous target selection.
  - Keeps existing `PendingAgentAttention` as the single shared state object.

- Modify `macos/Sources/App/macOS/AppDelegate.swift`
  - Executes routed terminal replies through the existing pending-attention send path.
  - Sends `guideForeman` messages to `ForemanAgent.receiveUserMessage`.

- Modify `macos/Sources/Features/AIForeman/ForemanChatView.swift`
  - Shows the active terminal context in chat.
  - Shows target chips when routing is ambiguous.
  - Changes the input placeholder/target label based on route state.

- Modify `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift`
  - Supports row selection styling and click selection without changing existing action buttons.

- Test in `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`
  - Store routing and target resolution.

- Test in `macos/Tests/Terminal/ForemanInputRoutingTests.swift`
  - Pure routing model edge cases.

---

## Task 1: Add Pure Input Routing Types

**Files:**
- Create: `macos/Sources/Features/AIForeman/ForemanInputRouting.swift`
- Test: `macos/Tests/Terminal/ForemanInputRoutingTests.swift`

- [ ] **Step 1: Write the routing model tests**

Create `macos/Tests/Terminal/ForemanInputRoutingTests.swift`:

```swift
import Testing
@testable import Ghostty

struct ForemanInputRoutingTests {
    @Test
    func targetOptionUsesStableAttentionID() {
        let attention = PendingAgentAttention(
            terminalID: "term-2",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            fingerprint: "fp-1",
            title: "Kimi needs direction",
            description: "Kimi is waiting for input.",
            actions: []
        )

        let option = ForemanTargetOption(attention: attention, terminalTitle: "Kimi worker")

        #expect(option.id == "term-2|fp-1")
        #expect(option.terminalID == "term-2")
        #expect(option.fingerprint == "fp-1")
        #expect(option.label == "Kimi worker")
        #expect(option.agentLabel == "Kimi")
    }

    @Test
    func chatTargetForPendingAttentionNamesAgentAndTerminal() {
        let attention = PendingAgentAttention(
            terminalID: "term-1",
            agentIdentity: .claudeCode,
            interactionState: .waitingText,
            fingerprint: "fp-2",
            title: "Claude needs input",
            description: "Claude is asking what to inspect.",
            actions: []
        )

        let target = ForemanChatTarget.replyToAgent(attention, terminalTitle: "Claude Code")

        #expect(target.title == "Replying to Claude Code")
        #expect(target.subtitle == "Claude Code · Claude Code")
        #expect(target.placeholder == "Reply to Claude Code...")
    }
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanInputRoutingTests
```

Expected: fail because `ForemanInputRoutingTests.swift` or the new routing types do not compile yet.

- [ ] **Step 3: Add the routing model**

Create `macos/Sources/Features/AIForeman/ForemanInputRouting.swift`:

```swift
import Foundation

enum ForemanInputIntent: Equatable, Sendable {
    case startGoal(String)
    case guideForeman(String)
    case replyToWaitingAgent(
        terminalID: String,
        fingerprint: String,
        message: String
    )
    case chooseAgentOption(
        terminalID: String,
        fingerprint: String,
        payload: String
    )
    case approveForemanAction(AgentAction)
}

struct ForemanTargetOption: Identifiable, Equatable, Sendable {
    let id: String
    let terminalID: String
    let fingerprint: String
    let label: String
    let agentLabel: String

    init(attention: PendingAgentAttention, terminalTitle: String) {
        self.id = attention.id
        self.terminalID = attention.terminalID
        self.fingerprint = attention.fingerprint
        self.label = terminalTitle.isEmpty ? attention.terminalID : terminalTitle
        self.agentLabel = Self.agentLabel(for: attention.agentIdentity)
    }

    private static func agentLabel(for identity: AgentIdentity) -> String {
        switch identity {
        case .kimi:
            return "Kimi"
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .none:
            return "Agent"
        }
    }
}

enum ForemanChatTarget: Equatable, Sendable {
    case replyToAgent(PendingAgentAttention, terminalTitle: String)
    case guideForeman
    case startGoal
    case chooseTarget([ForemanTargetOption])

    var title: String {
        switch self {
        case .replyToAgent(let attention, _):
            return "Replying to \(ForemanTargetOption(attention: attention, terminalTitle: "").agentLabel)"
        case .guideForeman:
            return "Guiding Foreman"
        case .startGoal:
            return "Start a Foreman goal"
        case .chooseTarget:
            return "Choose a terminal"
        }
    }

    var subtitle: String? {
        switch self {
        case .replyToAgent(let attention, let terminalTitle):
            let option = ForemanTargetOption(attention: attention, terminalTitle: terminalTitle)
            return "\(option.label) · \(option.agentLabel)"
        case .chooseTarget(let options):
            return "\(options.count) terminals need input"
        case .guideForeman, .startGoal:
            return nil
        }
    }

    var placeholder: String {
        switch self {
        case .replyToAgent(let attention, _):
            let option = ForemanTargetOption(attention: attention, terminalTitle: "")
            return "Reply to \(option.agentLabel)..."
        case .guideForeman:
            return "Guide Foreman..."
        case .startGoal:
            return "What should Foreman do?"
        case .chooseTarget:
            return "Choose a terminal first..."
        }
    }
}

enum ForemanInputResolution: Equatable, Sendable {
    case intent(ForemanInputIntent)
    case needsTarget(message: String, options: [ForemanTargetOption])
    case empty
}
```

- [ ] **Step 4: Run the routing model tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanInputRoutingTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit Task 1**

```bash
git add macos/Sources/Features/AIForeman/ForemanInputRouting.swift macos/Tests/Terminal/ForemanInputRoutingTests.swift
git commit -m "macos: add foreman input routing model"
```

---

## Task 2: Route Chat Text In The Store

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Add failing store tests for selected terminal routing**

Append these tests to `ForemanSidebarStoreTests`:

```swift
@MainActor
@Test
func chatInputRoutesToSelectedPendingTerminal() {
    let store = ForemanSidebarStore()
    let attention = PendingAgentAttention(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingText,
        fingerprint: "fp-1",
        title: "Kimi needs direction",
        description: "Kimi is waiting for input.",
        actions: [
            .init(id: "draft", title: "Send draft", payload: "Inspect the repo.", style: .primary)
        ]
    )
    var routedIntent: ForemanInputIntent?
    store.onRouteInput = { routedIntent = $0 }
    store.upsertPendingAttention(attention)
    store.chatInput = "Focus on the sidebar state."

    store.sendChatMessage(store.chatInput)

    #expect(store.chatInput == "")
    #expect(routedIntent == .replyToWaitingAgent(
        terminalID: "term-1",
        fingerprint: "fp-1",
        message: "Focus on the sidebar state."
    ))
}

@MainActor
@Test
func chatInputAsksForTargetWhenMultipleTerminalsAreWaiting() {
    let store = ForemanSidebarStore()
    store.terminalRows = [
        TerminalSummaryRowModel.makeTestRow(terminalID: "term-1", title: "Kimi"),
        TerminalSummaryRowModel.makeTestRow(terminalID: "term-2", title: "Codex")
    ]
    store.selectedTerminalID = nil
    store.upsertPendingAttention(PendingAgentAttention(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingText,
        fingerprint: "fp-1",
        title: "Kimi needs input",
        description: "Kimi is waiting.",
        actions: []
    ))
    store.upsertPendingAttention(PendingAgentAttention(
        terminalID: "term-2",
        agentIdentity: .codex,
        interactionState: .waitingText,
        fingerprint: "fp-2",
        title: "Codex needs input",
        description: "Codex is waiting.",
        actions: []
    ))
    store.selectedTerminalID = nil
    store.chatInput = "yes continue"

    store.sendChatMessage(store.chatInput)

    #expect(store.chatInput == "yes continue")
    #expect(store.pendingChatTargetOptions.map(\.terminalID) == ["term-1", "term-2"])
}
```

Add this helper at file scope in `ForemanSidebarStoreTests.swift`:

```swift
private extension TerminalSummaryRowModel {
    static func makeTestRow(terminalID: String, title: String) -> TerminalSummaryRowModel {
        TerminalSummaryRowModel(
            terminalID: terminalID,
            title: title,
            cwd: "/tmp/project",
            state: "waiting",
            summary: "\(title) is waiting.",
            agentIdentity: nil,
            agentInteractionState: nil,
            supportLevel: nil,
            evidenceSummary: nil,
            isFocused: false,
            suggestedActions: [],
            pendingAttention: nil,
            agentContextType: nil,
            agentContextTitle: nil,
            agentContextDescription: nil,
            agentContextDetail: nil,
            agentContextOptions: nil
        )
    }
}
```

- [ ] **Step 2: Run store tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: fail because `onRouteInput` and `pendingChatTargetOptions` do not exist.

- [ ] **Step 3: Add routing state and helpers to `ForemanSidebarStore`**

In `ForemanSidebarStore`, add the published target options and routed callback near existing chat properties:

```swift
@Published var pendingChatTargetOptions: [ForemanTargetOption] = []
var onRouteInput: ((ForemanInputIntent) -> Void)?
```

Add these computed helpers inside `ForemanSidebarStore`:

```swift
var selectedPendingAttention: PendingAgentAttention? {
    guard let selectedTerminalID else { return nil }
    return pendingAttentionByTerminalID[selectedTerminalID]
}

var chatTarget: ForemanChatTarget {
    if !pendingChatTargetOptions.isEmpty {
        return .chooseTarget(pendingChatTargetOptions)
    }

    if let attention = selectedPendingAttention {
        return .replyToAgent(
            attention,
            terminalTitle: title(forTerminalID: attention.terminalID)
        )
    }

    let pending = orderedPendingAttentions
    if pending.count == 1, let attention = pending.first {
        return .replyToAgent(
            attention,
            terminalTitle: title(forTerminalID: attention.terminalID)
        )
    }

    if conversation.goal == nil {
        return .startGoal
    }

    return .guideForeman
}

var orderedPendingAttentions: [PendingAgentAttention] {
    let rowOrder = terminalRows.map(\.terminalID)
    return pendingAttentionByTerminalID.values.sorted { lhs, rhs in
        let lhsIndex = rowOrder.firstIndex(of: lhs.terminalID) ?? Int.max
        let rhsIndex = rowOrder.firstIndex(of: rhs.terminalID) ?? Int.max
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        return lhs.terminalID < rhs.terminalID
    }
}

func selectTerminal(_ terminalID: String) {
    guard terminalRows.contains(where: { $0.terminalID == terminalID }) else {
        return
    }
    selectedTerminalID = terminalID
    pendingChatTargetOptions = []
}

func routeChatMessage(_ text: String) -> ForemanInputResolution {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .empty }

    if let attention = selectedPendingAttention {
        return .intent(.replyToWaitingAgent(
            terminalID: attention.terminalID,
            fingerprint: attention.fingerprint,
            message: trimmed
        ))
    }

    let pending = orderedPendingAttentions
    if pending.count == 1, let attention = pending.first {
        selectedTerminalID = attention.terminalID
        return .intent(.replyToWaitingAgent(
            terminalID: attention.terminalID,
            fingerprint: attention.fingerprint,
            message: trimmed
        ))
    }

    if pending.count > 1 {
        let options = pending.map {
            ForemanTargetOption(attention: $0, terminalTitle: title(forTerminalID: $0.terminalID))
        }
        pendingChatTargetOptions = options
        return .needsTarget(message: trimmed, options: options)
    }

    if conversation.goal == nil {
        return .intent(.startGoal(trimmed))
    }

    return .intent(.guideForeman(trimmed))
}

func chooseChatTarget(_ option: ForemanTargetOption) {
    guard pendingAttentionByTerminalID[option.terminalID]?.fingerprint == option.fingerprint else {
        return
    }
    selectedTerminalID = option.terminalID
    pendingChatTargetOptions = []
}

private func title(forTerminalID terminalID: String) -> String {
    terminalRows.first(where: { $0.terminalID == terminalID })?.title ?? terminalID
}
```

- [ ] **Step 4: Update `sendChatMessage` to route instead of blindly forwarding text**

Replace `sendChatMessage(_:)` in `ForemanSidebarStore` with:

```swift
func sendChatMessage(_ text: String) {
    switch routeChatMessage(text) {
    case .intent(let intent):
        chatInput = ""
        pendingChatTargetOptions = []
        onRouteInput?(intent)
    case .needsTarget(let message, _):
        chatInput = message
    case .empty:
        chatInput = ""
    }
}
```

- [ ] **Step 5: Run store tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit Task 2**

```bash
git add macos/Sources/Features/AIForeman/ForemanSidebarStore.swift macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "macos: route foreman chat input by terminal state"
```

---

## Task 3: Execute Routed Input In AppDelegate

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Add a store test proving selected reply supersedes the old suggestion**

Append this test to `ForemanSidebarStoreTests`:

```swift
@MainActor
@Test
func routedCustomReplyClearsChatTargetOptionsBeforeExecution() {
    let store = ForemanSidebarStore()
    let attention = PendingAgentAttention(
        terminalID: "term-1",
        agentIdentity: .kimi,
        interactionState: .waitingText,
        fingerprint: "fp-1",
        title: "Kimi needs direction",
        description: "Kimi is waiting for input.",
        actions: [
            .init(id: "draft", title: "Use draft", payload: "Use the draft.", style: .primary)
        ]
    )
    var routedIntent: ForemanInputIntent?
    store.onRouteInput = { routedIntent = $0 }
    store.upsertPendingAttention(attention)
    store.pendingChatTargetOptions = [
        ForemanTargetOption(attention: attention, terminalTitle: "Kimi")
    ]
    store.chooseChatTarget(store.pendingChatTargetOptions[0])

    store.sendChatMessage("Use my custom reply instead.")

    #expect(store.pendingChatTargetOptions.isEmpty)
    #expect(routedIntent == .replyToWaitingAgent(
        terminalID: "term-1",
        fingerprint: "fp-1",
        message: "Use my custom reply instead."
    ))
}
```

- [ ] **Step 2: Run the focused store test**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: pass if Task 2 was completed correctly.

- [ ] **Step 3: Wire `onRouteInput` where the store callbacks are assigned**

Find the store callback setup in `AppDelegate` where `onSendChatMessage` is assigned. Add:

```swift
store.onRouteInput = { [weak self, weak store] intent in
    guard let self, let store else { return }
    self.handleForemanInputIntent(intent, store: store)
}
```

Keep the existing `onSendChatMessage` assignment only if another view still uses it directly. New chat sends should go through `onRouteInput`.

- [ ] **Step 4: Add `handleForemanInputIntent` to `AppDelegate`**

Add this method near `sendChatMessage(_:store:)`:

```swift
@MainActor
func handleForemanInputIntent(_ intent: ForemanInputIntent, store: ForemanSidebarStore) {
    switch intent {
    case .startGoal(let goal):
        startForemanAgent(goal: goal, mode: .interactive, store: store)

    case .guideForeman(let message):
        sendChatMessage(message, store: store)

    case .replyToWaitingAgent(let terminalID, let fingerprint, let message):
        guard let attention = store.pendingAttentionByTerminalID[terminalID],
              attention.fingerprint == fingerprint else {
            store.errorMessage = "That terminal state changed before the reply could be sent."
            return
        }
        let action = PendingAgentAction(
            id: "custom_reply_\(fingerprint)",
            title: "Send custom reply",
            payload: message,
            style: .primary
        )
        executePendingAttentionAction(attention, action: action, store: store)
        store.conversation.addMessage(
            role: .user,
            content: message,
            terminalID: terminalID
        )

    case .chooseAgentOption(let terminalID, let fingerprint, let payload):
        guard let attention = store.pendingAttentionByTerminalID[terminalID],
              attention.fingerprint == fingerprint else {
            store.errorMessage = "That terminal option is no longer available."
            return
        }
        let action = PendingAgentAction(
            id: "chat_option_\(fingerprint)",
            title: "Send option",
            payload: payload,
            style: .primary
        )
        executePendingAttentionAction(attention, action: action, store: store)

    case .approveForemanAction:
        approveForemanAction()
    }
}
```

- [ ] **Step 5: Keep the old chat callback as a Foreman guidance fallback**

Leave `sendChatMessage(_ text:store:)` as:

```swift
@MainActor
func sendChatMessage(_ text: String, store: ForemanSidebarStore) {
    Task {
        await foremanAgent?.receiveUserMessage(text)
    }
}
```

This makes `guideForeman` preserve existing behavior.

- [ ] **Step 6: Run Foreman agent and store tests**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 7: Commit Task 3**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift macos/Sources/Features/AIForeman/ForemanSidebarStore.swift macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "macos: execute routed foreman chat replies"
```

---

## Task 4: Render Selected Terminal Context In Chat

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanChatView.swift`
- Modify: `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift`

- [ ] **Step 1: Add row selection callback support**

In `TerminalSummaryRow`, add new properties:

```swift
let isSelected: Bool
var onSelect: (() -> Void)?
```

Update the initializer usage by relying on Swift's memberwise initializer. Every call site must pass `isSelected` and `onSelect`.

Update the background/overlay to reflect selection:

```swift
.fill(isSelected ? Color.accentColor.opacity(0.16) : row.isFocused ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.05))
```

Add this modifier at the end of `body`:

```swift
.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
.onTapGesture {
    onSelect?()
}
```

- [ ] **Step 2: Update terminal row call sites**

In `ForemanChatView`, pass:

```swift
isSelected: store.selectedTerminalID == row.terminalID,
onSelect: {
    store.selectTerminal(row.terminalID)
},
```

In `ForemanSidebarView`, pass the same arguments:

```swift
isSelected: store.selectedTerminalID == row.terminalID,
onSelect: {
    store.selectTerminal(row.terminalID)
},
```

- [ ] **Step 3: Add active terminal context card in chat**

In `ForemanChatView`, add this view above the chat messages `ScrollViewReader`:

```swift
if case .replyToAgent(let attention, let terminalTitle) = store.chatTarget {
    ActiveTerminalAttentionCard(
        attention: attention,
        terminalTitle: terminalTitle,
        onAction: { action in
            store.executePendingAttentionAction(attention, action: action)
        }
    )
    .padding(.horizontal, 16)
    .padding(.vertical, 10)

    Divider()
}
```

Add this SwiftUI view in `ForemanChatView.swift` below `ChatBubble`:

```swift
struct ActiveTerminalAttentionCard: View {
    let attention: PendingAgentAttention
    let terminalTitle: String
    let onAction: (PendingAgentAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attention.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(terminalTitle) · \(attention.agentIdentity.rawValue.replacingOccurrences(of: "_", with: " "))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(attention.description)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            if let detail = attention.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if !attention.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(attention.actions.prefix(3)) { action in
                        Button(action.title) {
                            onAction(action)
                        }
                        .buttonStyle(PendingAgentActionButtonStyle(style: action.style))
                        .controlSize(.small)
                        .disabled(attention.status == .sending)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}
```

- [ ] **Step 4: Show target chips for ambiguous routing**

In `ForemanChatView`, add this above the input `HStack` for `.awaitingReply, .chatting`:

```swift
if case .chooseTarget(let options) = store.chatTarget {
    VStack(alignment: .leading, spacing: 6) {
        Text("Choose where this goes")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button("\(option.agentLabel) · \(option.label)") {
                    store.chooseChatTarget(option)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button("Guide Foreman") {
                store.pendingChatTargetOptions = []
                store.selectedTerminalID = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
```

- [ ] **Step 5: Update chat placeholder and target label**

In the `.awaitingReply, .chatting` input block, add:

```swift
VStack(alignment: .leading, spacing: 2) {
    Text(store.chatTarget.title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    if let subtitle = store.chatTarget.subtitle {
        Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
}
```

Change the text field placeholder from:

```swift
TextField("Message...", text: $store.chatInput, axis: .vertical)
```

to:

```swift
TextField(store.chatTarget.placeholder, text: $store.chatInput, axis: .vertical)
```

- [ ] **Step 6: Build the app**

Run:

```bash
macos/build.nu
```

Expected: build succeeds and produces `macos/build/Debug/Foreman.app`.

- [ ] **Step 7: Commit Task 4**

```bash
git add macos/Sources/Features/AIForeman/ForemanChatView.swift macos/Sources/Features/AIForeman/TerminalSummaryRow.swift
git commit -m "macos: show terminal attention in foreman chat"
```

---

## Task 5: Verify Integrated Behavior And Relaunch

**Files:**
- No planned source edits unless verification finds a defect.

- [ ] **Step 1: Run focused test suite**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanInputRoutingTests -only-testing:GhosttyTests/ForemanSidebarStoreTests -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: Build app bundle**

Run:

```bash
macos/build.nu
```

Expected: build succeeds and `macos/build/Debug/Foreman.app` exists.

- [ ] **Step 3: Relaunch the debug Foreman app**

Run:

```bash
pgrep -fl Foreman
```

If an old debug Foreman process is running, stop it with the already approved `kill` command using the exact PID.

Launch:

```bash
open /Users/nambouchara/speed2/ghostty/macos/build/Debug/Foreman.app
```

Verify:

```bash
pgrep -fl Foreman
```

Expected: one current Foreman app process is running.

- [ ] **Step 4: Manual behavior checks**

Use the running app and verify:

- With one waiting Kimi terminal, typing in chat sends to Kimi and clears the old pending suggestion.
- With two waiting terminals, typing in chat shows target chips and does not send.
- Clicking a terminal row changes the active chat card and input label.
- Clicking the existing terminal-row action still sends and resolves the card.
- `Guide Foreman` leaves terminal attention intact and sends the text to the Foreman conversation.

- [ ] **Step 5: Commit verification fixes if needed**

If Step 4 reveals a defect, make the smallest fix, rerun the focused tests and `macos/build.nu`, then commit:

```bash
git add macos/Sources/Features/AIForeman macos/Tests/Terminal
git commit -m "macos: polish connected foreman chat routing"
```

If Step 4 passes without edits, do not create an empty commit.

---

## Self-Review

Spec coverage:

- Shared terminal/chat state is covered by Tasks 2 and 4.
- Target selection and ambiguous multi-terminal behavior are covered by Task 2 tests and Task 4 chips.
- Typed replies superseding stale suggestions is covered by Tasks 2 and 3.
- Existing terminal-card click flow is preserved by Task 4 using existing `executePendingAttentionAction`.
- Stale fingerprint protection is covered by Task 3 guards.

Placeholder scan:

- The plan contains no placeholder markers and no open-ended deferred steps.

Type consistency:

- `ForemanInputIntent`, `ForemanChatTarget`, `ForemanTargetOption`, and `ForemanInputResolution` are introduced in Task 1 and used consistently by later tasks.
- Existing `PendingAgentAttention`, `PendingAgentAction`, `ForemanSidebarStore`, and `AppDelegate` APIs are reused instead of creating a parallel suggestion store.
