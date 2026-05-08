# Foreman Agent Orchestrator Interpretation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add interpretation-first agent detection and chat surfacing so Foreman can detect likely coding agents, infer when they are running/waiting/completed/failed, choose the newest qualifying terminal as the current subject, and publish a terminal-linked next-step summary into Foreman chat.

**Architecture:** Extend terminal snapshots with foreground process metadata, then enrich `TerminalUnderstanding` with agent identity, agent-specific state, and a surfacing decision. `ForemanSidebarStore` becomes the subject selector for the newest qualifying terminal update and uses `ForemanConversation` helpers to keep one live Foreman interpretation message current instead of appending noisy status spam.

**Tech Stack:** Swift, Swift Testing, SwiftUI, existing Ghostty macOS AI Foreman code, `xcodebuild` targeted tests

---

## File Structure

### Existing files to modify

- `macos/Sources/Features/AIForeman/TerminalSnapshot.swift`
  - Add foreground process metadata to the snapshot model and preview helper.
- `macos/Sources/Features/Terminal/TerminalController.swift`
  - Extend `TerminalSnapshotSource` and `makeTerminalSnapshot()` to pass foreground PID and process name.
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
  - Populate foreground PID and best-effort process-name lookup from the existing `surfaceModel.foregroundPID`.
- `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`
  - Add `AgentType`, `AgentState`, surfacing fields, and optional terminal reference text helpers.
- `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`
  - Add deterministic agent detection, agent-state inference, surfacing gates, and subject summary helpers.
- `macos/Sources/Features/AIForeman/ForemanConversation.swift`
  - Add message metadata and an upsert API for the current live interpretation message.
- `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
  - Track current subject terminal ID, detect the newest surfaced update, and refresh the live interpretation message.
- `macos/Sources/Features/AIForeman/ForemanChatView.swift`
  - Render the live interpretation message text cleanly and keep terminal references visible.

### Existing test files to modify

- `macos/Tests/Terminal/TerminalSnapshotTests.swift`
  - Cover snapshot process metadata.
- `macos/Tests/Terminal/TerminalSnapshotCaptureTests.swift`
  - Cover source-to-snapshot propagation of PID and process name.
- `macos/Tests/Terminal/TerminalUnderstandingTests.swift`
  - Cover agent detection, waiting/error/completed/running inference, and surfacing decisions.
- `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`
  - Cover current subject selection and live interpretation message replacement behavior.

### Existing files to read while implementing

- `macos/Sources/App/macOS/AppDelegate.swift`
- `macos/Sources/Features/Terminal/BaseTerminalController.swift`
- `macos/Sources/Ghostty/Ghostty.Surface.swift`

## Task 1: Capture Foreground Process Metadata In Snapshots

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalSnapshot.swift`
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
- Test: `macos/Tests/Terminal/TerminalSnapshotTests.swift`
- Test: `macos/Tests/Terminal/TerminalSnapshotCaptureTests.swift`

- [ ] **Step 1: Write the failing tests for snapshot process metadata**

Update `macos/Tests/Terminal/TerminalSnapshotTests.swift` with:

```swift
    @Test
    func snapshotStoresForegroundProcessMetadata() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-6",
            windowID: "win-6",
            tabID: "tab-6",
            title: "agent",
            cwd: "/tmp/project",
            isFocused: true,
            foregroundPID: 4242,
            foregroundProcessName: "codex",
            visibleText: "Working...",
            recentScrollbackLines: ["Working..."],
            lastInputPreview: "codex"
        )

        #expect(snapshot.foregroundPID == 4242)
        #expect(snapshot.foregroundProcessName == "codex")
        #expect(snapshot.summaryInput.contains("codex"))
    }
```

Update `macos/Tests/Terminal/TerminalSnapshotCaptureTests.swift` with:

```swift
private struct StubSnapshotSource: TerminalSnapshotSource {
    let terminalSnapshotTerminalID: String
    let terminalSnapshotWindowID: String
    let terminalSnapshotTabID: String
    let terminalSnapshotTitle: String
    let terminalSnapshotWorkingDirectory: String?
    let terminalSnapshotIsFocused: Bool
    let terminalSnapshotForegroundPID: Int?
    let terminalSnapshotForegroundProcessName: String?
    let terminalSnapshotVisibleText: String
    let terminalSnapshotRecentScrollbackLines: [String]
    let terminalSnapshotLastInputPreview: String?
}
```

and add:

```swift
    @Test
    func captureSnapshotIncludesForegroundProcessMetadata() async {
        let source = StubSnapshotSource(
            terminalSnapshotTerminalID: "term-2",
            terminalSnapshotWindowID: "win-2",
            terminalSnapshotTabID: "tab-2",
            terminalSnapshotTitle: "codex",
            terminalSnapshotWorkingDirectory: "/tmp/project",
            terminalSnapshotIsFocused: false,
            terminalSnapshotForegroundPID: 9001,
            terminalSnapshotForegroundProcessName: "codex",
            terminalSnapshotVisibleText: "Proceed? [y/n]",
            terminalSnapshotRecentScrollbackLines: ["Proceed? [y/n]"],
            terminalSnapshotLastInputPreview: "codex"
        )

        let snapshot = await source.makeTerminalSnapshot()

        #expect(snapshot.foregroundPID == 9001)
        #expect(snapshot.foregroundProcessName == "codex")
    }
```

- [ ] **Step 2: Run the targeted snapshot tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/TerminalSnapshotTests -only-testing:GhosttyTests/TerminalSnapshotCaptureTests
```

Expected:

```text
error: extra arguments at positions ... in call to 'makePreview'
error: type 'StubSnapshotSource' does not conform to protocol 'TerminalSnapshotSource'
Testing failed
```

- [ ] **Step 3: Extend `TerminalSnapshot` and the preview helper**

Update `macos/Sources/Features/AIForeman/TerminalSnapshot.swift`:

```swift
    let isFocused: Bool
    let foregroundPID: Int?
    let foregroundProcessName: String?
    let captureMode: String
```

Update `summaryInput`:

```swift
        if let foregroundProcessName, !foregroundProcessName.isEmpty {
            components.append(foregroundProcessName)
        }
```

Update `makePreview` signature and initializer:

```swift
    static func makePreview(
        terminalID: String,
        windowID: String,
        tabID: String,
        title: String,
        cwd: String?,
        isFocused: Bool,
        foregroundPID: Int? = nil,
        foregroundProcessName: String? = nil,
        visibleText: String,
        recentScrollbackLines: [String],
        lastInputPreview: String?
    ) -> TerminalSnapshot {
        ...
        return TerminalSnapshot(
            terminalID: terminalID,
            windowID: windowID,
            tabID: tabID,
            title: title,
            cwd: cwd,
            isFocused: isFocused,
            foregroundPID: foregroundPID,
            foregroundProcessName: foregroundProcessName,
            captureMode: "shell",
            visibleText: normalizedVisible,
            recentScrollback: normalizedScrollback,
            lastInputPreview: lastInputPreview,
            signals: ...
        )
    }
```

- [ ] **Step 4: Extend `TerminalSnapshotSource` and `makeTerminalSnapshot()`**

Update `macos/Sources/Features/Terminal/TerminalController.swift`:

```swift
protocol TerminalSnapshotSource {
    var terminalSnapshotTerminalID: String { get }
    var terminalSnapshotWindowID: String { get }
    var terminalSnapshotTabID: String { get }
    var terminalSnapshotTitle: String { get }
    var terminalSnapshotWorkingDirectory: String? { get }
    var terminalSnapshotIsFocused: Bool { get }
    var terminalSnapshotForegroundPID: Int? { get }
    var terminalSnapshotForegroundProcessName: String? { get }
    var terminalSnapshotVisibleText: String { get }
    var terminalSnapshotRecentScrollbackLines: [String] { get }
    var terminalSnapshotLastInputPreview: String? { get }
}
```

and:

```swift
    @MainActor
    func makeTerminalSnapshot() -> TerminalSnapshot {
        TerminalSnapshot.makePreview(
            terminalID: terminalSnapshotTerminalID,
            windowID: terminalSnapshotWindowID,
            tabID: terminalSnapshotTabID,
            title: terminalSnapshotTitle,
            cwd: terminalSnapshotWorkingDirectory,
            isFocused: terminalSnapshotIsFocused,
            foregroundPID: terminalSnapshotForegroundPID,
            foregroundProcessName: terminalSnapshotForegroundProcessName,
            visibleText: terminalSnapshotVisibleText,
            recentScrollbackLines: terminalSnapshotRecentScrollbackLines,
            lastInputPreview: terminalSnapshotLastInputPreview
        )
    }
```

- [ ] **Step 5: Populate PID and process name from `Ghostty.SurfaceView`**

Update `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`:

```swift
import Darwin
```

Inside `extension Ghostty.SurfaceView: TerminalSnapshotSource` add:

```swift
    var terminalSnapshotForegroundPID: Int? {
        surfaceModel?.foregroundPID
    }

    var terminalSnapshotForegroundProcessName: String? {
        guard let pid = terminalSnapshotForegroundPID else { return nil }
        return Self.resolveForegroundProcessName(pid: pid)
    }
```

and add a helper inside the extension:

```swift
    private static func resolveForegroundProcessName(pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let copied = proc_name(pid, &buffer, UInt32(buffer.count))
        guard copied > 0 else { return nil }
        let name = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
```

- [ ] **Step 6: Run the targeted snapshot tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/TerminalSnapshotTests -only-testing:GhosttyTests/TerminalSnapshotCaptureTests
```

Expected:

```text
Test Suite 'TerminalSnapshotTests' passed
Test Suite 'TerminalSnapshotCaptureTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 7: Commit the snapshot metadata slice**

```bash
git add macos/Sources/Features/AIForeman/TerminalSnapshot.swift macos/Sources/Features/Terminal/TerminalController.swift macos/Sources/Ghostty/Surface\ View/SurfaceView_AppKit.swift macos/Tests/Terminal/TerminalSnapshotTests.swift macos/Tests/Terminal/TerminalSnapshotCaptureTests.swift
git commit -m "feat: capture terminal foreground process metadata"
```

## Task 2: Add Agent Detection, Agent-State Inference, And Surfacing Gates

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`
- Test: `macos/Tests/Terminal/TerminalUnderstandingTests.swift`

- [ ] **Step 1: Write the failing tests for agent detection and surfacing**

Add to `macos/Tests/Terminal/TerminalUnderstandingTests.swift`:

```swift
    @Test
    func engineDetectsCodexWaitingForApproval() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex",
            cwd: "/tmp/project",
            isFocused: true,
            foregroundPID: 4242,
            foregroundProcessName: "codex",
            visibleText: "Plan ready.\nProceed? [y/n]",
            recentScrollbackLines: ["Plan ready.", "Proceed? [y/n]"],
            lastInputPreview: "codex"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.detectedAgent == .codex)
        #expect(understanding.agentState == .waitingForUser)
        #expect(understanding.shouldSurfaceToForeman == true)
        #expect(understanding.suggestedNextActions.first?.title == "Approve and continue")
        #expect(understanding.suggestedNextActions.first?.command == "y")
    }

    @Test
    func engineDetectsCompletedAgentOutputWhenPromptReturns() {
        let engine = TerminalUnderstandingEngine()
        let previous = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex",
            cwd: "/tmp/project",
            isFocused: true,
            foregroundPID: 4242,
            foregroundProcessName: "codex",
            visibleText: "Applying patch...",
            recentScrollbackLines: ["Applying patch..."],
            lastInputPreview: "codex"
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex",
            cwd: "/tmp/project",
            isFocused: true,
            foregroundPID: 4242,
            foregroundProcessName: "codex",
            visibleText: "Applied patch.\nuser@host %",
            recentScrollbackLines: ["Applied patch.", "user@host %"],
            lastInputPreview: "codex"
        )

        let understanding = engine.understand(
            current: current,
            previous: previous,
            lastOutcome: nil
        )

        #expect(understanding.detectedAgent == .codex)
        #expect(understanding.agentState == .completed)
        #expect(understanding.shouldSurfaceToForeman == true)
    }

    @Test
    func engineDoesNotSurfaceGenericRunningNoise() {
        let engine = TerminalUnderstandingEngine()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "build-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "build",
            cwd: "/tmp/project",
            isFocused: false,
            foregroundPID: 5000,
            foregroundProcessName: "swift",
            visibleText: "Compiling module A...",
            recentScrollbackLines: ["Compiling module A..."],
            lastInputPreview: "swift build"
        )

        let understanding = engine.understand(
            current: snapshot,
            previous: nil,
            lastOutcome: nil
        )

        #expect(understanding.detectedAgent == .none)
        #expect(understanding.agentState == .idle)
        #expect(understanding.state == .running)
        #expect(understanding.shouldSurfaceToForeman == false)
    }
```

- [ ] **Step 2: Run the understanding tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/TerminalUnderstandingTests
```

Expected:

```text
error: value of type 'TerminalUnderstanding' has no member 'detectedAgent'
error: value of type 'TerminalUnderstanding' has no member 'agentState'
error: value of type 'TerminalUnderstanding' has no member 'shouldSurfaceToForeman'
Testing failed
```

- [ ] **Step 3: Extend `TerminalUnderstanding` with agent fields**

Update `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`:

```swift
enum AgentType: String, Codable, Equatable, Sendable {
    case none
    case codex
    case claudeCode
    case aider
    case cursor
}

enum AgentState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case waitingForUser
    case error
    case completed
}
```

Add fields to `TerminalUnderstanding`:

```swift
    let detectedAgent: AgentType
    let agentState: AgentState
    let shouldSurfaceToForeman: Bool
```

Update the preview helper:

```swift
            detectedAgent: .none,
            agentState: .idle,
            shouldSurfaceToForeman: false,
```

- [ ] **Step 4: Add deterministic agent detection and surfacing logic**

Update `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`:

```swift
        let detectedAgent = detectAgent(in: current)
        let agentState = inferAgentState(
            current: current,
            previous: previous,
            detectedAgent: detectedAgent,
            terminalState: state
        )
        let shouldSurface = shouldSurfaceToForeman(
            current: current,
            previous: previous,
            terminalState: state,
            detectedAgent: detectedAgent,
            agentState: agentState
        )
        let suggestedActions = makeSuggestions(
            for: current,
            state: state,
            detectedAgent: detectedAgent,
            agentState: agentState,
            lastEvent: lastEvent
        )
```

Return:

```swift
        return TerminalUnderstanding(
            terminalID: current.terminalID,
            title: current.title,
            cwd: current.cwd,
            state: state,
            lastMeaningfulEvent: lastEvent,
            shortExplanation: explain(state: state, snapshot: current, lastEvent: lastEvent),
            importantDetails: importantDetails(from: visible, state: state),
            suggestedNextActions: suggestedActions,
            detectedAgent: detectedAgent,
            agentState: agentState,
            shouldSurfaceToForeman: shouldSurface
        )
```

Add helpers:

```swift
    private func detectAgent(in snapshot: TerminalSnapshot) -> AgentType {
        let process = snapshot.foregroundProcessName?.lowercased() ?? ""
        let text = [snapshot.visibleText, snapshot.recentScrollback, snapshot.lastInputPreview]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")

        if process.contains("codex") || text.contains("proceed? [y/n]") {
            return .codex
        }
        if process.contains("claude") || text.contains("shall i proceed?") || text.contains("approve?") {
            return .claudeCode
        }
        if process.contains("aider") || text.contains("apply this change?") {
            return .aider
        }
        if process.contains("cursor") {
            return .cursor
        }
        return .none
    }

    private func inferAgentState(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        detectedAgent: AgentType,
        terminalState: TerminalUnderstandingState
    ) -> AgentState {
        guard detectedAgent != .none else { return .idle }
        let visible = current.visibleText.lowercased()
        if visible.contains("proceed?") || visible.contains("approve?") || visible.contains("yes/no/all") {
            return .waitingForUser
        }
        if terminalState == .failed {
            return .error
        }
        if terminalState == .waiting,
           previous?.signals.likelyWaitingForInput == false {
            return .completed
        }
        if current.signals.likelyWaitingForInput && visible.contains("%") {
            return .completed
        }
        return .running
    }

    private func shouldSurfaceToForeman(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        terminalState: TerminalUnderstandingState,
        detectedAgent: AgentType,
        agentState: AgentState
    ) -> Bool {
        if detectedAgent != .none {
            switch agentState {
            case .waitingForUser, .error, .completed:
                return true
            case .running, .idle:
                break
            }
        }

        switch terminalState {
        case .failed, .succeeded:
            return true
        case .running, .waiting, .idle, .noisyHealthy:
            return false
        }
    }
```

Update `makeSuggestions` for waiting agents:

```swift
        if detectedAgent != .none && agentState == .waitingForUser {
            return [
                .init(
                    title: "Approve and continue",
                    command: "y",
                    reason: "The agent is explicitly asking for approval.",
                    isRecommended: true
                ),
                .init(
                    title: "Open the terminal and review the prompt",
                    command: nil,
                    reason: "Use this when you want to inspect the exact pending request first.",
                    isRecommended: false
                ),
            ]
        }
```

- [ ] **Step 5: Run the understanding tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/TerminalUnderstandingTests
```

Expected:

```text
Test Suite 'TerminalUnderstandingTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 6: Commit the agent inference slice**

```bash
git add macos/Sources/Features/AIForeman/TerminalUnderstanding.swift macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift macos/Tests/Terminal/TerminalUnderstandingTests.swift
git commit -m "feat: infer terminal agent state for Foreman"
```

## Task 3: Track The Current Subject Terminal And Upsert One Live Interpretation Message

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Write the failing store tests for subject selection and message replacement**

Add to `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`:

```swift
    @MainActor
    @Test
    func applySnapshotsPromotesNewestSurfacedTerminalToCurrentSubject() {
        let store = ForemanSidebarStore()
        let first = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex A",
            cwd: "/tmp/project",
            isFocused: true,
            foregroundPID: 1,
            foregroundProcessName: "codex",
            visibleText: "Proceed? [y/n]",
            recentScrollbackLines: ["Proceed? [y/n]"],
            lastInputPreview: "codex"
        )
        let second = TerminalSnapshot.makePreview(
            terminalID: "term-2",
            windowID: "win-1",
            tabID: "tab-2",
            title: "build",
            cwd: "/tmp/project",
            isFocused: false,
            foregroundPID: 2,
            foregroundProcessName: "swift",
            visibleText: "Compiling...",
            recentScrollbackLines: ["Compiling..."],
            lastInputPreview: "swift build"
        )

        store.applySnapshots(
            [first, second],
            understandingsByTerminalID: [
                "term-1": TerminalUnderstanding(
                    terminalID: "term-1",
                    title: "Codex A",
                    cwd: "/tmp/project",
                    state: .waiting,
                    lastMeaningfulEvent: "Proceed? [y/n]",
                    shortExplanation: "Codex Agent is waiting for approval.",
                    importantDetails: ["Proceed? [y/n]"],
                    suggestedNextActions: [
                        .init(title: "Approve and continue", command: "y", reason: "Approval requested.", isRecommended: true)
                    ],
                    detectedAgent: .codex,
                    agentState: .waitingForUser,
                    shouldSurfaceToForeman: true
                ),
                "term-2": TerminalUnderstanding.preview(
                    terminalID: "term-2",
                    state: .running,
                    shortExplanation: "Build is running.",
                    lastMeaningfulEvent: "Compiling...",
                    importantDetails: [],
                    suggestedNextActions: []
                )
            ]
        )

        #expect(store.currentSubjectTerminalID == "term-1")
        #expect(store.conversation.messages.last?.content.contains("Codex A") == true)
    }

    @MainActor
    @Test
    func applySnapshotsReplacesPreviousLiveInterpretationInsteadOfAppendingAnother() {
        let store = ForemanSidebarStore()
        store.conversation.addOrReplaceLiveInterpretation(
            terminalID: "term-1",
            content: "Old summary",
            action: nil
        )

        store.conversation.addOrReplaceLiveInterpretation(
            terminalID: "term-1",
            content: "New summary",
            action: nil
        )

        #expect(store.conversation.messages.count == 1)
        #expect(store.conversation.messages[0].content == "New summary")
    }
```

- [ ] **Step 2: Run the store tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected:

```text
error: value of type 'ForemanSidebarStore' has no member 'currentSubjectTerminalID'
error: value of type 'ForemanConversation' has no member 'addOrReplaceLiveInterpretation'
Testing failed
```

- [ ] **Step 3: Add message metadata and an upsert helper to `ForemanConversation`**

Update `macos/Sources/Features/AIForeman/ForemanConversation.swift`:

```swift
enum ConversationMessageKind: String, Codable, Sendable, Equatable {
    case standard
    case liveInterpretation
}
```

Extend `ConversationMessage`:

```swift
    let kind: ConversationMessageKind
    let terminalID: String?
```

Update the initializer defaults:

```swift
        kind: ConversationMessageKind = .standard,
        terminalID: String? = nil,
```

Add a helper:

```swift
    func addOrReplaceLiveInterpretation(
        terminalID: String,
        content: String,
        action: AgentAction?
    ) {
        if let index = messages.lastIndex(where: { $0.kind == .liveInterpretation }) {
            let existing = messages[index]
            messages[index] = ConversationMessage(
                id: existing.id,
                role: .agent,
                content: content,
                action: action,
                timestamp: Date(),
                kind: .liveInterpretation,
                terminalID: terminalID
            )
            return
        }

        messages.append(
            ConversationMessage(
                role: .agent,
                content: content,
                action: action,
                kind: .liveInterpretation,
                terminalID: terminalID
            )
        )
    }
```

- [ ] **Step 4: Track and surface the current subject in `ForemanSidebarStore`**

Update `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`:

```swift
    @Published var currentSubjectTerminalID: String?
    private var lastSurfacedFingerprintByTerminalID: [String: String] = [:]
```

Initialize the new property:

```swift
        currentSubjectTerminalID: String? = nil,
```

and:

```swift
        self.currentSubjectTerminalID = currentSubjectTerminalID
```

At the end of `applySnapshots(...)` add:

```swift
        let surfacedCandidates = snapshots.compactMap { snapshot -> (TerminalSnapshot, TerminalUnderstanding)? in
            guard let understanding = understandingsByTerminalID[snapshot.terminalID],
                  understanding.shouldSurfaceToForeman else {
                return nil
            }
            return (snapshot, understanding)
        }

        if let newest = surfacedCandidates.last {
            let fingerprint = "\(newest.1.agentState.rawValue)|\(newest.1.lastMeaningfulEvent)|\(newest.1.shortExplanation)"
            if lastSurfacedFingerprintByTerminalID[newest.0.terminalID] != fingerprint {
                lastSurfacedFingerprintByTerminalID[newest.0.terminalID] = fingerprint
                currentSubjectTerminalID = newest.0.terminalID
                refreshLiveInterpretation(snapshot: newest.0, understanding: newest.1)
            }
        }
```

Add a helper:

```swift
    private func refreshLiveInterpretation(
        snapshot: TerminalSnapshot,
        understanding: TerminalUnderstanding
    ) {
        let terminalLabel = snapshot.title.isEmpty ? snapshot.terminalID : snapshot.title
        let content = "\(terminalLabel) · \(understanding.shortExplanation)\nNext: \(understanding.recommendedAction?.title ?? "Review terminal output")"
        let action = understanding.recommendedAction.flatMap { suggested -> AgentAction? in
            guard let command = suggested.command else { return nil }
            return .sendCommand(terminalID: snapshot.terminalID, command: command, reason: suggested.reason)
        }

        conversation.addOrReplaceLiveInterpretation(
            terminalID: snapshot.terminalID,
            content: content,
            action: action
        )
    }
```

- [ ] **Step 5: Run the store tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected:

```text
Test Suite 'ForemanSidebarStoreTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 6: Commit the subject-selection slice**

```bash
git add macos/Sources/Features/AIForeman/ForemanConversation.swift macos/Sources/Features/AIForeman/ForemanSidebarStore.swift macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "feat: surface live Foreman terminal interpretations"
```

## Task 4: Render Terminal-Linked Chat Summaries Cleanly And Verify Integration

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanChatView.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Write the failing integration-style store test for action badges**

Add to `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`:

```swift
    @MainActor
    @Test
    func liveInterpretationCarriesSendCommandActionForMechanicalApproval() {
        let store = ForemanSidebarStore()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex Agent",
            cwd: "/tmp/project",
            isFocused: true,
            foregroundPID: 1,
            foregroundProcessName: "codex",
            visibleText: "Proceed? [y/n]",
            recentScrollbackLines: ["Proceed? [y/n]"],
            lastInputPreview: "codex"
        )
        let understanding = TerminalUnderstanding(
            terminalID: "term-1",
            title: "Codex Agent",
            cwd: "/tmp/project",
            state: .waiting,
            lastMeaningfulEvent: "Proceed? [y/n]",
            shortExplanation: "Codex Agent is waiting for approval.",
            importantDetails: ["Proceed? [y/n]"],
            suggestedNextActions: [
                .init(title: "Approve and continue", command: "y", reason: "Approval requested.", isRecommended: true)
            ],
            detectedAgent: .codex,
            agentState: .waitingForUser,
            shouldSurfaceToForeman: true
        )

        store.applySnapshots([snapshot], understandingsByTerminalID: ["term-1": understanding])

        let action = store.conversation.messages.last?.action
        #expect(action == .sendCommand(terminalID: "term-1", command: "y", reason: "Approval requested."))
    }
```

- [ ] **Step 2: Run the store test and verify it fails for message formatting or action wiring**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected:

```text
Expectation failed: action was nil or content omitted the terminal label
Testing failed
```

- [ ] **Step 3: Render live interpretation messages with visible terminal context**

Update `macos/Sources/Features/AIForeman/ForemanChatView.swift` inside `ChatBubble`:

```swift
                if message.kind == .liveInterpretation, let terminalID = message.terminalID {
                    Text("Terminal: \(terminalID)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(message.role == .user ? .primary : .secondary)
```

This keeps the first slice simple: terminal references are visible in chat immediately, without introducing a custom clickable terminal link view yet.

- [ ] **Step 4: Make the app refresh path preserve surfaced understandings**

Update `macos/Sources/App/macOS/AppDelegate.swift` in `refreshAIForemanSidebar()`:

```swift
            let understandings = snapshots.map { snapshot in
                aiForemanUnderstandingEngine.understand(
                    current: snapshot,
                    previous: aiForemanPreviousSnapshots[snapshot.terminalID],
                    lastOutcome: nil
                )
            }
```

Keep the existing `applySnapshots(...)` call, but verify during implementation that no extra guard prevents the conversation update when the sidebar is visible. If there is such a guard nearby, remove it so surfaced updates can reach `ForemanSidebarStore` while preserving the existing approval flow.

- [ ] **Step 5: Run the focused store and understanding tests, then the Foreman sidebar suite**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/TerminalUnderstandingTests -only-testing:GhosttyTests/ForemanSidebarStoreTests -only-testing:GhosttyTests/TerminalSnapshotCaptureTests -only-testing:GhosttyTests/TerminalSnapshotTests
```

Expected:

```text
Test Suite 'TerminalSnapshotTests' passed
Test Suite 'TerminalSnapshotCaptureTests' passed
Test Suite 'TerminalUnderstandingTests' passed
Test Suite 'ForemanSidebarStoreTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 6: Build the macOS app to catch integration regressions**

Run:

```bash
xcodebuild build -project macos/Ghostty.xcodeproj -scheme Ghostty -destination "platform=macOS"
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 7: Commit the chat surfacing slice**

```bash
git add macos/Sources/Features/AIForeman/ForemanChatView.swift macos/Sources/Features/AIForeman/ForemanSidebarStore.swift macos/Sources/App/macOS/AppDelegate.swift macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "feat: publish live terminal interpretations in Foreman chat"
```

## Self-Review

- Spec coverage:
  - Snapshot PID/process metadata: Task 1
  - Agent detection and state inference: Task 2
  - Surfacing gate and newest qualifying terminal policy: Tasks 2 and 3
  - Chat-facing current subject summary: Tasks 3 and 4
  - Mechanical next-action payloads: Tasks 2 and 4
- Placeholder scan:
  - No `TODO` or `TBD` placeholders remain.
  - The one implementation note in Task 4 is constrained to a specific local verification point in `AppDelegate.refreshAIForemanSidebar()`, not an unspecified follow-up.
- Type consistency:
  - `AgentType`, `AgentState`, `ConversationMessageKind`, `currentSubjectTerminalID`, and `addOrReplaceLiveInterpretation` are referenced consistently across tasks.
