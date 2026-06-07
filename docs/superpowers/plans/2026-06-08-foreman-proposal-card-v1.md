# Foreman Proposal Card — v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a "personal assistant" surface where, when one terminal's agent needs attention, the Foreman shows a single proposal card (plain summary + one suggested action + Yes/No/Edit) and a macOS notification — replacing the chat-first sidebar.

**Architecture:** Keep the existing detection/LLM "engine" (clean leaf files, audited) unchanged and build a small fresh shell on top: a `ForemanProposer` (turns the already-computed `TerminalUnderstanding` + an optional LLM summary into a `TerminalProposal`), a `ProposalStore` (`ObservableObject` holding the current proposal), and a `ProposalCardView`. Drive them from the existing snapshot-capture hook in `AppDelegate` (which already produces understandings), mount the card in place of the old chat view, and route "Yes" through the existing terminal-send mechanism.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing (`import Testing`, target `GhosttyTests`). Tests under `macos/Tests/Terminal/`. New source files under `macos/Sources/Features/AIForeman/` (Xcode synchronized groups — no `.pbxproj` edits needed).

**Spec:** `docs/superpowers/specs/2026-06-07-foreman-proposal-card-v1-design.md`

**Notes / deliberate deviations from the spec:**
- The spec named a `TerminalWatcher` component. During planning we found the existing capture hook (`refreshAIForemanSidebar`, `AppDelegate` ~line 2038) *already computes* `TerminalUnderstanding` for every terminal. Re-running detection in a separate watcher would duplicate work, so the watcher is dropped; we reuse the existing understandings and put the attention policy on `ForemanProposer.needsAttention`.
- v1 is the single-terminal approve loop. The old shell's *views* are retired in the final task; deleting the load-bearing `ForemanSidebarStore`/`ForemanAgent`/`ForemanSidebarRouting` (still wired into ~600 lines of `AppDelegate`) is an explicit deferred follow-up to keep v1 low-risk.

---

## File Structure

### Create (new shell — all under `macos/Sources/Features/AIForeman/`)
- `TerminalProposal.swift` — the proposal value type (one terminal's pending decision).
- `ProposalStore.swift` — `@MainActor ObservableObject` holding the current proposal; approve/reject/edit + callbacks.
- `ForemanProposer.swift` — builds a `TerminalProposal` from a `TerminalUnderstanding` (+ injected async summary source); attention policy.
- `ProposalCardView.swift` — SwiftUI card: summary + suggested action + `[Yes] [No] [Edit]`.

### Create (tests — under `macos/Tests/Terminal/`)
- `TerminalProposalTests.swift`
- `ProposalStoreTests.swift`
- `ForemanProposerTests.swift`

### Modify
- `macos/Sources/Features/AIForeman/ForemanNotifier.swift` — add `notifyProposal(terminalID:summary:)`.
- `macos/Sources/Features/Terminal/TerminalView.swift` — add a `proposalStore` requirement to the view-model protocol; mount `ProposalCardView` at the existing sidebar slot (~line 151).
- `macos/Sources/Features/Terminal/BaseTerminalController.swift` — own a `ProposalStore` (next to `foremanSidebarStore`, line ~57).
- `macos/Sources/App/macOS/AppDelegate.swift` — in `refreshAIForemanSidebar()` (~line 2032) drive proposer→store; add the send + notify helpers.

### Delete (final task)
- `macos/Sources/Features/AIForeman/ForemanChatView.swift` (only mounted at `TerminalView.swift:151`).
- `macos/Sources/Features/AIForeman/ForemanSidebarView.swift` (already unmounted).

---

## Task 1: The `TerminalProposal` value type

**Files:**
- Create: `macos/Sources/Features/AIForeman/TerminalProposal.swift`
- Test: `macos/Tests/Terminal/TerminalProposalTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// macos/Tests/Terminal/TerminalProposalTests.swift
import Testing
@testable import Ghostty

struct TerminalProposalTests {
    @Test
    func idCombinesTerminalAndFingerprint() {
        let proposal = TerminalProposal(
            terminalID: "t1",
            fingerprint: "fp1",
            summary: "Kimi wants to push to main.",
            actionTitle: "Approve the push",
            payload: "y",
            kind: .waitingApproval
        )

        #expect(proposal.id == "t1|fp1")
        #expect(proposal.canSend)
    }

    @Test
    func proposalWithoutPayloadCannotSend() {
        let proposal = TerminalProposal(
            terminalID: "t1",
            fingerprint: "fp1",
            summary: "Codex hit an error.",
            actionTitle: "Review the error",
            payload: nil,
            kind: .error
        )

        #expect(!proposal.canSend)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalProposalTests 2>&1 | tail -20
```
Expected: FAIL — compile error, `TerminalProposal` is not defined.

- [ ] **Step 3: Create the type**

```swift
// macos/Sources/Features/AIForeman/TerminalProposal.swift
import Foundation

/// One terminal's pending decision, pre-chewed into a summary + one suggested action.
/// The unit the user approves. `payload` is what gets sent to the terminal on "Yes".
struct TerminalProposal: Identifiable, Equatable, Sendable {
    let terminalID: String
    let fingerprint: String
    let summary: String
    let actionTitle: String
    let payload: String?
    let kind: AgentInteractionState

    var id: String { "\(terminalID)|\(fingerprint)" }

    /// True when there is a one-tap action to send. When false, the card offers only Edit/No.
    var canSend: Bool { (payload?.isEmpty == false) }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalProposalTests 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/AIForeman/TerminalProposal.swift \
        macos/Tests/Terminal/TerminalProposalTests.swift
git commit -m "feat: add TerminalProposal value type"
```

---

## Task 2: The `ProposalStore`

**Files:**
- Create: `macos/Sources/Features/AIForeman/ProposalStore.swift`
- Test: `macos/Tests/Terminal/ProposalStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// macos/Tests/Terminal/ProposalStoreTests.swift
import Testing
@testable import Ghostty

@MainActor
struct ProposalStoreTests {
    private func proposal(_ fingerprint: String, payload: String? = "y") -> TerminalProposal {
        TerminalProposal(
            terminalID: "t1",
            fingerprint: fingerprint,
            summary: "Kimi wants to push to main.",
            actionTitle: "Approve",
            payload: payload,
            kind: .waitingApproval
        )
    }

    @Test
    func approveSendsPayloadAndClears() {
        let store = ProposalStore()
        var sent: [(terminalID: String, payload: String)] = []
        store.onApprove = { proposal, payload in sent.append((proposal.terminalID, payload)) }

        store.present(proposal("fp1"))
        store.approve()

        #expect(sent.count == 1)
        #expect(sent[0].payload == "y")
        #expect(store.current == nil)
    }

    @Test
    func rejectClearsWithoutSending() {
        let store = ProposalStore()
        var approved = false
        var rejectedTerminalID: String?
        store.onApprove = { _, _ in approved = true }
        store.onReject = { proposal in rejectedTerminalID = proposal.terminalID }

        store.present(proposal("fp1"))
        store.reject()

        #expect(!approved)
        #expect(rejectedTerminalID == "t1")
        #expect(store.current == nil)
    }

    @Test
    func editedApprovalSendsDraftText() {
        let store = ProposalStore()
        var sent: String?
        store.onApprove = { _, payload in sent = payload }

        store.present(proposal("fp1"))
        store.beginEdit()
        store.draft = "no, stop"
        store.approveEdited()

        #expect(sent == "no, stop")
        #expect(store.current == nil)
    }

    @Test
    func newFingerprintReplacesStaleProposal() {
        let store = ProposalStore()
        store.present(proposal("fp1", payload: "old"))
        store.present(proposal("fp2", payload: "new"))

        #expect(store.current?.fingerprint == "fp2")
        #expect(store.draft == "new")
    }

    @Test
    func sameProposalDoesNotResetInProgressEdit() {
        let store = ProposalStore()
        store.present(proposal("fp1", payload: "y"))
        store.beginEdit()
        store.draft = "half-typed reply"
        store.present(proposal("fp1", payload: "y"))

        #expect(store.isEditing)
        #expect(store.draft == "half-typed reply")
    }

    @Test
    func clearForMatchingTerminalRemovesCard() {
        let store = ProposalStore()
        store.present(proposal("fp1"))
        store.clear(terminalID: "t1")

        #expect(store.current == nil)
    }

    @Test
    func clearForOtherTerminalLeavesCard() {
        let store = ProposalStore()
        store.present(proposal("fp1"))
        store.clear(terminalID: "other")

        #expect(store.current?.fingerprint == "fp1")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ProposalStoreTests 2>&1 | tail -20
```
Expected: FAIL — compile error, `ProposalStore` is not defined.

- [ ] **Step 3: Create the store**

```swift
// macos/Sources/Features/AIForeman/ProposalStore.swift
import Foundation
import SwiftUI

/// Holds the single current proposal for a terminal sidebar and exposes the
/// approve / reject / edit interactions. All decisions leave via the callbacks.
@MainActor
final class ProposalStore: ObservableObject {
    @Published private(set) var current: TerminalProposal?
    @Published var draft: String = ""
    @Published private(set) var isEditing: Bool = false
    @Published var errorMessage: String?

    /// Called when the user approves: send `payload` to `proposal.terminalID`.
    var onApprove: ((_ proposal: TerminalProposal, _ payload: String) -> Void)?
    /// Called when the user rejects: dismiss without sending.
    var onReject: ((_ proposal: TerminalProposal) -> Void)?

    /// Replace the current proposal. A proposal with the same `id` is treated as a
    /// no-op so a repeated capture tick does not disrupt an in-progress edit.
    func present(_ proposal: TerminalProposal) {
        if current?.id == proposal.id {
            return
        }
        current = proposal
        draft = proposal.payload ?? ""
        isEditing = false
        errorMessage = nil
    }

    /// Drop the proposal if it belongs to `terminalID` (the terminal moved on).
    func clear(terminalID: String) {
        guard current?.terminalID == terminalID else { return }
        reset()
    }

    func beginEdit() {
        guard let current else { return }
        draft = current.payload ?? ""
        isEditing = true
    }

    func cancelEdit() {
        isEditing = false
        draft = current?.payload ?? ""
    }

    func approve() {
        guard let proposal = current, let payload = proposal.payload, !payload.isEmpty else { return }
        onApprove?(proposal, payload)
        reset()
    }

    func approveEdited() {
        guard let proposal = current else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onApprove?(proposal, text)
        reset()
    }

    func reject() {
        guard let proposal = current else { return }
        onReject?(proposal)
        reset()
    }

    private func reset() {
        current = nil
        draft = ""
        isEditing = false
        errorMessage = nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ProposalStoreTests 2>&1 | tail -20
```
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/AIForeman/ProposalStore.swift \
        macos/Tests/Terminal/ProposalStoreTests.swift
git commit -m "feat: add ProposalStore for the foreman proposal card"
```

---

## Task 3: The `ForemanProposer`

**Files:**
- Create: `macos/Sources/Features/AIForeman/ForemanProposer.swift`
- Test: `macos/Tests/Terminal/ForemanProposerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// macos/Tests/Terminal/ForemanProposerTests.swift
import Testing
@testable import Ghostty

struct ForemanProposerTests {
    private func understanding(
        state: AgentInteractionState,
        actions: [TerminalSuggestedAction] = [],
        explanation: String = "Heuristic explanation."
    ) -> TerminalUnderstanding {
        TerminalUnderstanding.preview(
            terminalID: "t1",
            state: .waiting,
            shortExplanation: explanation,
            lastMeaningfulEvent: "Proceed? (y/n)",
            importantDetails: [],
            suggestedNextActions: actions,
            agentIdentity: .codex,
            agentInteractionState: state
        )
    }

    private func snapshot() -> TerminalSnapshot {
        TerminalSnapshot.makePreview(
            terminalID: "t1",
            windowID: "w1",
            tabID: "tab1",
            title: "codex",
            cwd: "/tmp",
            isFocused: true,
            visibleText: "Proceed? (y/n)",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex"
        )
    }

    @Test
    func runningStateProducesNoProposal() async {
        let proposer = ForemanProposer()
        let result = await proposer.makeProposal(
            understanding: understanding(state: .running),
            snapshot: snapshot()
        )
        #expect(result == nil)
    }

    @Test
    func usesLLMSummaryWhenAvailable() async {
        let proposer = ForemanProposer(summarize: { _ in "Kimi wants to push to main. Tests passed." })
        let action = TerminalSuggestedAction(
            title: "Approve the push",
            command: nil,
            reason: "",
            isRecommended: true,
            authoritativePayload: "y"
        )

        let result = await proposer.makeProposal(
            understanding: understanding(state: .waitingApproval, actions: [action]),
            snapshot: snapshot()
        )

        #expect(result?.summary == "Kimi wants to push to main. Tests passed.")
        #expect(result?.payload == "y")
        #expect(result?.actionTitle == "Approve the push")
        #expect(result?.kind == .waitingApproval)
    }

    @Test
    func fallsBackToHeuristicSummaryWhenLLMReturnsNil() async {
        let proposer = ForemanProposer(summarize: { _ in nil })
        let action = TerminalSuggestedAction(
            title: "Approve",
            command: nil,
            reason: "",
            isRecommended: true,
            authoritativePayload: "y"
        )

        let result = await proposer.makeProposal(
            understanding: understanding(
                state: .waitingApproval,
                actions: [action],
                explanation: "Codex is asking to proceed."
            ),
            snapshot: snapshot()
        )

        #expect(result?.summary == "Codex is asking to proceed.")
        #expect(result?.payload == "y")
    }

    @Test
    func errorStateWithoutActionStillProposesWithNoPayload() async {
        let proposer = ForemanProposer(summarize: { _ in "A build error appeared." })
        let result = await proposer.makeProposal(
            understanding: understanding(state: .error),
            snapshot: snapshot()
        )

        #expect(result != nil)
        #expect(result?.payload == nil)
        #expect(result?.kind == .error)
    }

    @Test
    func attentionPolicyMatchesExpectedStates() {
        #expect(ForemanProposer.needsAttention(.waitingApproval))
        #expect(ForemanProposer.needsAttention(.waitingChoice))
        #expect(ForemanProposer.needsAttention(.waitingText))
        #expect(ForemanProposer.needsAttention(.error))
        #expect(ForemanProposer.needsAttention(.completed))
        #expect(!ForemanProposer.needsAttention(.running))
        #expect(!ForemanProposer.needsAttention(.unknown))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ForemanProposerTests 2>&1 | tail -20
```
Expected: FAIL — compile error, `ForemanProposer` is not defined.

- [ ] **Step 3: Create the proposer**

```swift
// macos/Sources/Features/AIForeman/ForemanProposer.swift
import Foundation

/// Turns a `TerminalUnderstanding` (from the dumb detection engine) into a
/// `TerminalProposal` (the friendly card). The plain summary comes from an injected
/// async source — the LLM in production — and falls back to the heuristic explanation
/// when unavailable. The action/payload always comes from the understanding, so the
/// thing we send is what the agent itself surfaced.
struct ForemanProposer {
    /// Returns a plain-English summary for a snapshot, or `nil` when no LLM is
    /// configured or the call fails.
    let summarize: (TerminalSnapshot) async -> String?

    init(summarize: @escaping (TerminalSnapshot) async -> String? = { _ in nil }) {
        self.summarize = summarize
    }

    func makeProposal(
        understanding: TerminalUnderstanding,
        snapshot: TerminalSnapshot
    ) async -> TerminalProposal? {
        guard Self.needsAttention(understanding.agentInteractionState) else {
            return nil
        }

        let action = understanding.recommendedAction ?? understanding.suggestedNextActions.first
        let payload = action.flatMap { $0.authoritativePayload ?? $0.command }
        let actionTitle = action?.title ?? Self.defaultTitle(for: understanding.agentInteractionState)

        let llmSummary = (await summarize(snapshot))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (llmSummary?.isEmpty == false ? llmSummary : nil) ?? understanding.shortExplanation

        return TerminalProposal(
            terminalID: understanding.terminalID,
            fingerprint: Self.fingerprint(for: understanding),
            summary: summary,
            actionTitle: actionTitle,
            payload: payload,
            kind: understanding.agentInteractionState
        )
    }

    /// The states that warrant interrupting the user.
    static func needsAttention(_ state: AgentInteractionState) -> Bool {
        switch state {
        case .waitingApproval, .waitingChoice, .waitingText, .error, .completed:
            return true
        case .unknown, .running:
            return false
        }
    }

    /// A stable identifier for "this exact pending state", used to detect staleness.
    /// Prefers the authoritative wire fingerprint; falls back to the screen state.
    static func fingerprint(for understanding: TerminalUnderstanding) -> String {
        if let fingerprint = understanding.workerSnapshot?.attentionFingerprint {
            return fingerprint
        }
        if let fingerprint = understanding.suggestedNextActions.compactMap(\.authoritativeFingerprint).first {
            return fingerprint
        }
        return "\(understanding.agentInteractionState.rawValue)|\(understanding.lastMeaningfulEvent)"
    }

    private static func defaultTitle(for state: AgentInteractionState) -> String {
        switch state {
        case .waitingApproval: return "Approve"
        case .waitingChoice: return "Choose"
        case .waitingText: return "Reply"
        case .error: return "Review the error"
        case .completed: return "Acknowledge"
        case .unknown, .running: return "Continue"
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ForemanProposerTests 2>&1 | tail -20
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/AIForeman/ForemanProposer.swift \
        macos/Tests/Terminal/ForemanProposerTests.swift
git commit -m "feat: add ForemanProposer to build proposals from understandings"
```

---

## Task 4: The `ProposalCardView`

All decision logic lives in the already-tested `ProposalStore`; this view is a thin renderer. Verification is "compiles + preview renders", plus a SwiftUI design review.

**Files:**
- Create: `macos/Sources/Features/AIForeman/ProposalCardView.swift`

- [ ] **Step 1: Invoke the SwiftUI design skill to build the view**

Invoke `swiftui-design` to implement `ProposalCardView` to the structure below, matching the existing sidebar's visual language (`ForemanSidebarView.swift` for spacing/typography reference). Keep all behavior delegating to `ProposalStore`.

```swift
// macos/Sources/Features/AIForeman/ProposalCardView.swift
import SwiftUI

struct ProposalCardView: View {
    @ObservedObject var store: ProposalStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let proposal = store.current {
                card(for: proposal)
            } else {
                idleState
            }
        }
        .frame(minWidth: 300, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Foreman")
                .font(.system(size: 18, weight: .bold))
            Text("Watching your terminals. I'll let you know when one needs you.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private func card(for proposal: TerminalProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Needs you · \(proposal.terminalID)", systemImage: "exclamationmark.bubble.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)

            Text(proposal.summary)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)

            if store.isEditing {
                TextField("Your reply", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                HStack(spacing: 8) {
                    Button("Send") { store.approveEdited() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { store.cancelEdit() }
                        .buttonStyle(.bordered)
                }
            } else {
                Text("Suggested: \(proposal.actionTitle)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if proposal.canSend {
                        Button("✓ Yes") { store.approve() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("✗ No") { store.reject() }
                        .buttonStyle(.bordered)
                    Button("✎ Edit") { store.beginEdit() }
                        .buttonStyle(.bordered)
                }
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }
}

#Preview("Waiting") {
    let store = ProposalStore()
    store.present(
        TerminalProposal(
            terminalID: "term-2",
            fingerprint: "fp1",
            summary: "Kimi wants to push to main. Tests passed, so I'd let it.",
            actionTitle: "Approve the push",
            payload: "y",
            kind: .waitingApproval
        )
    )
    return ProposalCardView(store: store)
}

#Preview("Idle") {
    ProposalCardView(store: ProposalStore())
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Review the view with the SwiftUI review skills**

Invoke `swiftui-pro` and `hig-foundations` to review `ProposalCardView.swift` for modern-API correctness, accessibility (button labels, Dynamic Type), and HIG alignment. Apply any fixes they surface; keep behavior delegating to the store.

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/AIForeman/ProposalCardView.swift
git commit -m "feat: add ProposalCardView for the foreman proposal surface"
```

---

## Task 5: Drive the proposal from capture and mount the card

This produces a proposal from the already-computed understandings and shows the card instead of the chat. The send path and notification come in Task 6.

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalView.swift` (protocol + mount at ~line 151)
- Modify: `macos/Sources/Features/Terminal/BaseTerminalController.swift` (own `proposalStore`, ~line 57)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (drive proposer→store inside `refreshAIForemanSidebar`, ~line 2032)

- [ ] **Step 1: Add a `proposalStore` to the terminal view-model protocol and own it on the controller**

In `macos/Sources/Features/Terminal/TerminalView.swift`, the view-model protocol already declares (around line 40):
```swift
    var foremanSidebarStore: ForemanSidebarStore { get }
```
Add directly beneath it:
```swift
    var proposalStore: ProposalStore { get }
```

In `macos/Sources/Features/Terminal/BaseTerminalController.swift`, find (line ~57):
```swift
    let foremanSidebarStore = ForemanSidebarStore()
```
Add directly beneath it:
```swift
    let proposalStore = ProposalStore()
```
Build to confirm the controller still satisfies the view-model protocol:
```bash
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Mount `ProposalCardView` in place of `ForemanChatView`**

In `macos/Sources/Features/Terminal/TerminalView.swift` around line 151, replace:
```swift
                    ForemanChatView(store: viewModel.foremanSidebarStore)
```
with:
```swift
                    ProposalCardView(store: viewModel.proposalStore)
```
Leave the surrounding visibility condition (`viewModel.foremanSidebarStore.isSidebarVisible`) unchanged — the existing show/hide toggle still controls the panel.

- [ ] **Step 3: Drive the proposer from the existing capture loop**

In `macos/Sources/App/macOS/AppDelegate.swift`, the method `refreshAIForemanSidebar()` (~line 2032) contains this loop:
```swift
        for (controller, snapshots) in observation.snapshotsByController {
            controller.foremanSidebarStore.applySnapshots(
                snapshots,
                summariesByTerminalID: currentAISummaries(for: snapshots),
                understandingsByTerminalID: observation.understandingsByTerminalID
            )
        }
```
Add a call at the end of the loop body, after `applySnapshots(...)`:
```swift
            updateProposal(
                for: controller,
                snapshots: snapshots,
                understandingsByTerminalID: observation.understandingsByTerminalID
            )
```
Then add these two methods in the same `AppDelegate` extension:
```swift
    @MainActor
    private func updateProposal(
        for controller: BaseTerminalController,
        snapshots: [TerminalSnapshot],
        understandingsByTerminalID: [String: TerminalUnderstanding]
    ) {
        // v1: single-terminal — use the focused terminal, else the first.
        guard let snapshot = snapshots.first(where: { $0.isFocused }) ?? snapshots.first,
              let understanding = understandingsByTerminalID[snapshot.terminalID] else {
            return
        }

        guard ForemanProposer.needsAttention(understanding.agentInteractionState) else {
            controller.proposalStore.clear(terminalID: snapshot.terminalID)
            return
        }

        let summarize = makeProposalSummarizer()
        Task { @MainActor in
            guard let proposal = await ForemanProposer(summarize: summarize)
                .makeProposal(understanding: understanding, snapshot: snapshot) else {
                controller.proposalStore.clear(terminalID: snapshot.terminalID)
                return
            }
            controller.proposalStore.present(proposal)
        }
    }

    /// An async summary source backed by the configured LLM, or one that always
    /// returns nil when no key is set (the card then uses the heuristic summary).
    @MainActor
    private func makeProposalSummarizer() -> (TerminalSnapshot) async -> String? {
        guard let foremanService else {
            return { _ in nil }
        }
        return { snapshot in
            do {
                return try await foremanService.summarize(snapshot: snapshot).summary
            } catch {
                return nil
            }
        }
    }
```
Note: `foremanService` (lazy, line ~127) and `summarize(snapshot:)` already exist; `BaseTerminalController` owns both stores.

- [ ] **Step 4: Build and run the new-component tests to confirm no regressions**

Run:
```bash
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty 2>&1 | tail -20
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ProposalStoreTests \
  -only-testing:GhosttyTests/ForemanProposerTests 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalView.swift \
        macos/Sources/Features/Terminal/BaseTerminalController.swift \
        macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat: drive proposal card from snapshot capture and mount it"
```

---

## Task 6: Approve send path + macOS notification

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanNotifier.swift` (add `notifyProposal`)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (set `onApprove`/`onReject`; send; notify)

- [ ] **Step 1: Add a proposal notification to `ForemanNotifier`**

In `macos/Sources/Features/AIForeman/ForemanNotifier.swift`, add this method to the `ForemanNotifier` class (after `observe(report:...)`):
```swift
    /// Notify the user about a pending proposal when the app is not in the foreground.
    func notifyProposal(terminalID: String, summary: String) {
        guard authorized else { return }
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "Foreman needs you"
        content.body = summary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "foreman-proposal-\(terminalID)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
```

- [ ] **Step 2: Bind the store callbacks and notify on a new proposal**

In `macos/Sources/App/macOS/AppDelegate.swift`, in `updateProposal(for:snapshots:understandingsByTerminalID:)` (from Task 5), replace the success branch:
```swift
            controller.proposalStore.present(proposal)
```
with:
```swift
            let isNew = controller.proposalStore.current?.id != proposal.id
            bindProposalCallbacks(for: controller)
            controller.proposalStore.present(proposal)
            if isNew {
                ForemanNotifier.shared.notifyProposal(
                    terminalID: proposal.terminalID,
                    summary: proposal.summary
                )
            }
```
Then add the binding helper in the same extension. Capture `controller` weakly to avoid a retain cycle (controller → proposalStore → onApprove → controller):
```swift
    @MainActor
    private func bindProposalCallbacks(for controller: BaseTerminalController) {
        guard controller.proposalStore.onApprove == nil else { return }
        controller.proposalStore.onApprove = { [weak self, weak controller] proposal, payload in
            guard let self, let controller else { return }
            self.sendProposalReply(
                terminalID: proposal.terminalID,
                fingerprint: proposal.fingerprint,
                payload: payload,
                store: controller.proposalStore
            )
        }
        controller.proposalStore.onReject = { proposal in
            DebugLogger.log("[Foreman] proposal rejected for \(proposal.terminalID)")
        }
    }
```

- [ ] **Step 3: Implement the send using the existing dispatch mechanism**

Add this method to the same `AppDelegate` extension. It uses the exact mechanism already proven in `executePendingAttentionPayload` (~line 1737): resolve the controller, send a `DispatchQueueItem` via `dispatchQueueCoordinator`, register outcome tracking, and resolve the agent-state monitor.
```swift
    @MainActor
    func sendProposalReply(
        terminalID: String,
        fingerprint: String,
        payload: String,
        store: ProposalStore
    ) {
        guard let controller = terminalController(for: terminalID) else {
            store.errorMessage = "This terminal is no longer available."
            return
        }

        let item = DispatchQueueItem(terminalID: terminalID, message: payload)
        guard dispatchQueueCoordinator.send(item, through: controller) else {
            store.errorMessage = "Couldn't send to the terminal. Try again."
            return
        }

        registerTerminalOutcomeTracking(terminalID: terminalID, sentCommand: payload)
        agentStateMonitor.resolve(terminalID: terminalID, fingerprint: fingerprint)
        store.errorMessage = nil
    }
```

- [ ] **Step 4: Build and run new tests**

Run:
```bash
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty 2>&1 | tail -20
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ProposalStoreTests 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/AIForeman/ForemanNotifier.swift \
        macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat: send proposal approvals to the terminal and notify when away"
```

---

## Task 7: Retire old views + final verification

**Files:**
- Delete: `macos/Sources/Features/AIForeman/ForemanChatView.swift`
- Delete: `macos/Sources/Features/AIForeman/ForemanSidebarView.swift`

- [ ] **Step 1: Confirm the old views are unreferenced**

Run:
```bash
grep -rn 'ForemanChatView\|ForemanSidebarView' macos/Sources macos/Tests \
  | grep -v 'ForemanSidebarView.swift:\|ForemanChatView.swift:'
```
Expected: no remaining references (the mount was swapped in Task 5). If a test references them, update or remove that reference.

- [ ] **Step 2: Delete the retired view files**

```bash
git rm macos/Sources/Features/AIForeman/ForemanChatView.swift \
       macos/Sources/Features/AIForeman/ForemanSidebarView.swift
```

- [ ] **Step 3: Concurrency + testing review**

Invoke `swift-concurrency-pro` to review the new `@MainActor` boundaries and the `Task { @MainActor }` in `updateProposal` (and the weak captures in `bindProposalCallbacks`) for correctness, and `swift-testing-pro` to review the three new test files. Apply fixes inline.

- [ ] **Step 4: Full build + full new-suite run**

Run:
```bash
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty 2>&1 | tail -20
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalProposalTests \
  -only-testing:GhosttyTests/ProposalStoreTests \
  -only-testing:GhosttyTests/ForemanProposerTests 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED; all new tests PASS.

- [ ] **Step 5: Manual product verification**

Run the app (via Xcode), then:
- Launch an agent (Codex/Claude/Kimi) in a terminal and open the Foreman sidebar.
- Drive the agent to a prompt that needs input/approval → a proposal card appears with a plain summary + suggested action.
- Tap **Yes** → the payload is sent to that terminal; the card clears.
- Tap **No** → the card clears without sending.
- Tap **Edit**, change the text, **Send** → the edited text is sent.
- With the app in the background, trigger a new prompt → a macOS notification appears.
- Remove API keys → the card still appears using the agent's own parsed option as the suggestion.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: retire old foreman chat/sidebar views for the proposal card"
```

---

## Deferred follow-ups (explicitly NOT in v1)

- Delete `ForemanSidebarStore`, `ForemanAgent`, `ForemanSidebarRouting` and gut their ~600 lines of `AppDelegate` wiring (large, independent cleanup — do once the card model is proven).
- Multi-terminal overview / project cards / channels.
- Project goals + human-confirmed completion checkpoints.
- Autonomous mode behavior on top of the proposal loop.
```
