# Interactive Suggested Actions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make suggested actions in terminal sidebar cards clickable, sending commands directly to terminals via the existing dispatch path.

**Architecture:** Add one callback `onExecuteSuggestion` through `ForemanSidebarStore` → `BaseTerminalController` → `AppDelegate`, which looks up the terminal and calls `sendForemanText()`. Convert `TerminalSummaryRow` static action text into pill-style buttons. Reuse existing `sendForemanText` — no new abstractions.

**Tech Stack:** Swift, SwiftUI, AppKit (macOS)

---

### Task 1: Add `onExecuteSuggestion` callback to ForemanSidebarStore

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift:100`

Add the callback property after `onLaunchAgent`:

```swift
var onLaunchAgent: ((AgentIdentity) -> Void)?
var onExecuteSuggestion: ((String, String) -> Void)?
```

Add a public method to trigger it:

```swift
func executeSuggestion(terminalID: String, command: String) {
    onExecuteSuggestion?(terminalID, command)
}
```

**Test:** Build the project to verify compilation.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild build -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5
```

**Expected:** `** BUILD SUCCEEDED **`

---

### Task 2: Wire callback in BaseTerminalController

**Files:**
- Modify: `macos/Sources/Features/Terminal/BaseTerminalController.swift:178`

After the `onLaunchAgent` wiring block, add:

```swift
foremanSidebarStore.onExecuteSuggestion = { [weak self] terminalID, command in
    guard let self else { return }
    (NSApp.delegate as? AppDelegate)?.executeSuggestedAction(
        terminalID: terminalID,
        command: command
    )
}
```

**Test:** Build the project.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild build -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5
```

**Expected:** `** BUILD SUCCEEDED **`

---

### Task 3: Add `executeSuggestedAction` to AppDelegate

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (after `skipForemanAction`, around line 1473)

Add the method:

```swift
@MainActor
func executeSuggestedAction(terminalID: String, command: String) {
    guard let controller = terminalController(for: terminalID) else {
        DebugLogger.log("[AppDelegate] executeSuggestedAction: no controller for \(terminalID)")
        return
    }
    let success = controller.sendForemanText(command, to: terminalID)
    DebugLogger.log("[AppDelegate] executeSuggestedAction: terminal=\(terminalID.prefix(8)) success=\(success)")
}
```

**Test:** Build the project.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild build -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5
```

**Expected:** `** BUILD SUCCEEDED **`

---

### Task 4: Convert suggested actions to buttons in TerminalSummaryRow

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift:79-91`

Replace the static `suggestedActions` rendering with buttons. The row needs access to the store callback. Add a callback property to the view:

At the top of the view struct, add:

```swift
var onExecuteSuggestion: ((String, String) -> Void)?
```

Replace the `suggestedActions` rendering block:

```swift
if !row.suggestedActions.isEmpty {
    VStack(alignment: .leading, spacing: 6) {
        ForEach(row.suggestedActions.prefix(2), id: \.title) { action in
            if let command = action.command {
                Button(action: {
                    onExecuteSuggestion?(row.terminalID, command)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: action.isRecommended ? "star.fill" : "bolt.fill")
                            .font(.system(size: 8))
                        Text(action.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(SuggestedActionButtonStyle(isRecommended: action.isRecommended))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: action.isRecommended ? "star.fill" : "circle")
                        .font(.system(size: 8))
                        .foregroundStyle(action.isRecommended ? .yellow : .secondary)
                    Text(action.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

**Test:** Build the project.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild build -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5
```

**Expected:** `** BUILD SUCCEEDED **`

---

### Task 5: Add `SuggestedActionButtonStyle`

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift` (append at end of file)

Add the button style:

```swift
struct SuggestedActionButtonStyle: ButtonStyle {
    let isRecommended: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isRecommended ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecommended
                        ? (configuration.isPressed ? Color.blue.opacity(0.7) : Color.blue)
                        : (configuration.isPressed ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.1))
                    )
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
```

**Test:** Build the project.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild build -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5
```

**Expected:** `** BUILD SUCCEEDED **`

---

### Task 6: Wire the callback in ForemanChatView's TerminalSummaryRow usage

**Files:**
- Find and modify wherever `TerminalSummaryRow` is instantiated in `ForemanChatView.swift` or `ForemanSidebarView.swift`

Find the `TerminalSummaryRow` call site and pass the callback:

```swift
TerminalSummaryRow(
    row: row,
    onExecuteSuggestion: { terminalID, command in
        store.executeSuggestion(terminalID: terminalID, command: command)
    }
)
```

If there are multiple call sites (e.g., in both `ForemanChatView` and `ForemanSidebarView`), update all of them.

**Test:** Build the project.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild build -project Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5
```

**Expected:** `** BUILD SUCCEEDED **`

---

### Task 7: Write unit test for the button callback

**Files:**
- Create: `macos/Tests/Terminal/SuggestedActionButtonTests.swift`

```swift
import Foundation
import Testing
@testable import Ghostty

struct SuggestedActionButtonTests {

    @Test
    func executeSuggestionCallbackFiresWithCorrectArgs() {
        let store = ForemanSidebarStore()

        var capturedTerminalID: String?
        var capturedCommand: String?

        store.onExecuteSuggestion = { terminalID, command in
            capturedTerminalID = terminalID
            capturedCommand = command
        }

        store.executeSuggestion(terminalID: "test-terminal-123", command: "ls -la")

        #expect(capturedTerminalID == "test-terminal-123")
        #expect(capturedCommand == "ls -la")
    }

    @Test
    func executeSuggestionNoOpWhenCallbackNil() {
        let store = ForemanSidebarStore()
        // onExecuteSuggestion is nil by default
        store.executeSuggestion(terminalID: "t1", command: "cmd")
        // Should not crash; test passes if we get here
        #expect(true)
    }
}
```

**Test:** Run the new test.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild test -project Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/SuggestedActionButtonTests -destination 'platform=macOS' 2>&1 | tail -15
```

**Expected:** Both tests pass.

---

### Task 8: Run full wire test suite

**Test:** Run all wire-related tests to confirm no regressions.

```bash
cd /Users/nambouchara/speed2/ghostty/macos && xcodebuild test -project Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/KimiWireRuntimeSimulationTests -only-testing:GhosttyTests/KimiWelcomeScreenTests -only-testing:GhosttyTests/CodexWireRuntimeSimulationTests -only-testing:GhosttyTests/ClaudeWireRuntimeSimulationTests -only-testing:GhosttyTests/SuggestedActionButtonTests -destination 'platform=macOS' 2>&1 | tail -20
```

**Expected:** All tests pass.

---

### Task 9: Commit

```bash
cd /Users/nambouchara/speed2/ghostty && git add -A && git commit -m "foreman: make suggested actions in sidebar interactive

Terminal cards in the sidebar now render suggested actions as clickable
buttons. Tapping a button sends the associated command directly to the
corresponding terminal via the existing sendForemanText path.

- ForemanSidebarStore: add onExecuteSuggestion callback
- BaseTerminalController: wire callback to AppDelegate
- AppDelegate: add executeSuggestedAction(terminalID:command:)
- TerminalSummaryRow: convert static text → pill buttons with
  SuggestedActionButtonStyle (blue for recommended, gray for others)
- SuggestedActionButtonTests: verify callback fires with correct args"
```
