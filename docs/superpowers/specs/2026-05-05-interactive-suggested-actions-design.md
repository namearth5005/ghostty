# Interactive Suggested Actions — Design Spec

**Date:** 2026-05-05  
**Status:** Approved  
**Approach:** A (Simple Button Dispatch)

## Problem

`TerminalSummaryRow` renders `suggestedActions` as static text with icons (star/circle). The user can see suggestions like "Reply to the agent" or "Let Foreman explain..." but cannot interact with them. The actions already carry `command: String?` — when non-nil, it's an executable command. The dispatch infrastructure (`sendForemanQueueItem`, `DispatchQueueCoordinator.send()`) already works for sending text to terminals.

## Goal

Make suggested actions in the terminal sidebar cards clickable, reusing the existing dispatch path. Tap a button → command is sent to the corresponding terminal.

## Architecture

```
TerminalSummaryRow (SwiftUI)
    ↓ tap on suggested action button
ForemanSidebarStore.onExecuteSuggestion?(terminalID, command)
    ↓ callback wired in BaseTerminalController
AppDelegate.executeSuggestedAction(terminalID:command:)
    ↓ reuses existing dispatch path
DispatchQueueCoordinator.send(command, to: terminalID)
    ↓
Terminal receives the text input
```

## Changes

### 1. ForemanSidebarStore

Add one callback:

```swift
var onExecuteSuggestion: ((String, String) -> Void)?
```

- `String` = terminalID
- `String` = command to send

### 2. BaseTerminalController

Wire the callback in the store setup block:

```swift
foremanSidebarStore.onExecuteSuggestion = { [weak self] terminalID, command in
    guard let self else { return }
    (NSApp.delegate as? AppDelegate)?.executeSuggestedAction(
        terminalID: terminalID,
        command: command
    )
}
```

### 3. AppDelegate

Add a thin wrapper:

```swift
func executeSuggestedAction(terminalID: String, command: String) {
    DispatchQueueCoordinator.shared.send(
        text: command,
        toTerminalID: terminalID
    )
}
```

This reuses the same code path as `sendForemanQueueItem` but without queue tracking or outcome monitoring. Suggested actions are fire-and-send; no need for the full queue lifecycle.

### 4. TerminalSummaryRow

Convert `suggestedActions` rendering from static text to buttons:

```swift
ForEach(row.suggestedActions.prefix(2), id: \.title) { action in
    if let command = action.command {
        Button(action.title) {
            onExecuteSuggestion?(row.terminalID, command)
        }
        .buttonStyle(SuggestedActionButtonStyle(isRecommended: action.isRecommended))
    } else {
        // Informational action without a command — keep as static text
        Label(action.title, systemImage: action.isRecommended ? "star.fill" : "circle")
    }
}
```

**Button styles:**
- **Recommended** (`isRecommended: true`): filled blue pill, matching the chat "Run" button style
- **Other** (`isRecommended: false`): outlined gray pill

**Layout:** actions stack vertically beneath the agent context card, maintaining the existing VStack alignment.

## Error Handling

- `executeSuggestedAction` validates the terminal exists via `TerminalController.find(terminalID:)` before sending. If the terminal was closed since the snapshot, silently no-op.
- `DispatchQueueCoordinator.send()` already handles timing-safe delivery (waits for prompt, respects shell state).
- No retry logic needed — if delivery fails, the user sees the terminal didn't react and can tap again.

## Out of Scope

- Chat history logging of executed suggestions (can be added later)
- Undo / rollback of executed commands
- Confirmation dialogs before sending (suggested actions are low-risk user-initiated)
- Informational actions without commands — these remain static text

## Testing

1. **Unit test:** Given a `TerminalSummaryRow` with suggested actions, tapping a button calls `onExecuteSuggestion` with the correct terminalID and command.
2. **Integration test:** Wire a mock `ForemanSidebarStore`, simulate a terminal in `waitingApproval` state, verify the suggested action button renders, tap it, verify `DispatchQueueCoordinator` receives the command.
