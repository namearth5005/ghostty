# Foreman Connected Terminal Chat Design

## Goal

Make Foreman's terminal cards and bottom chat feel like one connected workflow instead of two separate state machines.

The user should be able to:

- See which terminal needs attention.
- See that same terminal event inside the chat workspace.
- Type a custom reply in chat and have it go to the correct terminal.
- Avoid stale duplicate suggestions after typing a replacement reply.
- Work with multiple waiting terminals without Foreman silently guessing the wrong target.

## Problem

Foreman currently has two mostly separate interaction paths:

```text
Terminal card flow
Terminal changes state
→ Foreman detects waiting / choice / approval
→ Foreman shows a pending card or suggestion
→ User clicks
→ Text goes directly to that terminal
```

```text
Bottom chat flow
User types in Foreman chat
→ Foreman treats it as a message to Foreman
→ Foreman may plan/respond
→ The message is not inherently tied to the waiting terminal card
```

This is why the terminal-only flow works, but mixing terminal suggestions with chat input feels disconnected.

## Product Model

Use this mental model:

```text
Terminal list = inbox / navigator
Chat = active workspace for the selected terminal or Foreman goal
```

Terminal rows stay compact. They show current status, waiting state, and whether an action is available.

The chat area shows the active context in full:

```text
Replying to: Kimi · Terminal 2

Kimi is waiting:
"What should I do next?"

Foreman suggests:
[Inspect the sidebar/chat state and propose the cleanest fix]

Your reply:
[ type here... ]
```

If the user selects another waiting terminal, the chat workspace switches to that terminal's context.

## Shared State Rule

Do not duplicate terminal suggestions into chat as separate actions.

Instead, render one underlying `PendingAgentAttention` in two places:

- Compact rendering in the terminal row.
- Full rendering in the chat workspace.

The shared object should remain keyed by:

- `terminalID`
- `fingerprint`
- `agentIdentity`
- `interactionState`

This prevents two independent buttons from getting out of sync.

## Input Routing

All user input should pass through one routing decision before execution.

Suggested model:

```swift
enum ForemanInputIntent {
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
```

The bottom chat should no longer always mean "send a message to Foreman." It should resolve intent from visible UI state.

## Target Selection Rules

Foreman should make the common case fast, but never silently guess in ambiguous cases.

Target resolution order:

1. If the user explicitly selects a terminal row, use that terminal.
2. If the chat workspace is already showing a selected pending attention, use that terminal.
3. If exactly one terminal is waiting, use that terminal.
4. If the focused Ghostty terminal is waiting, use that terminal.
5. If multiple terminals are waiting and no target is clear, ask the user to choose.

Ambiguous state should show target chips:

```text
Choose where this goes:
[ Kimi · Terminal 2 ] [ Codex · Terminal 3 ] [ Guide Foreman ]
```

The AI should not infer the target from vague text like "yes continue" when multiple terminals are waiting.

## Chat Input Behavior

The input should always show its current destination:

```text
[ Replying to Kimi · Terminal 2 ▼ ]
[ type your message...            ↑ ]
```

When a terminal is waiting, the default mode should be `Reply to <agent>`.

There should still be a way to switch to `Guide Foreman` when the user wants to talk to Foreman instead of replying to the agent.

## Typed Reply Supersedes Suggested Reply

If a terminal has a suggested reply and the user types a custom reply in chat, the typed reply wins.

Example:

```text
Suggested reply:
"Inspect the repo and recommend the next task."

User types:
"Focus specifically on the chat and terminal state connection."
```

Expected behavior:

```text
Send user's custom text to the selected terminal
→ mark the old suggestion resolved or superseded
→ remove stale buttons from the row and chat workspace
→ record that the user replied to that terminal
```

The old suggestion must not remain clickable after a replacement reply is sent.

## Multi-Terminal Behavior

Multiple waiting terminals are allowed.

Only one terminal context should be active in the chat workspace at a time.

Terminal rows act as the navigator:

```text
Kimi     Waiting for text      1 suggestion
Claude   Running
Codex    Needs approval        2 actions
```

Clicking a row sets `selectedTerminalID` and updates the chat workspace.

If the active selected terminal becomes irrelevant, resolved, or closes, Foreman may advance selection using the target selection rules.

## Error Handling

If the selected pending attention disappears before send:

- Do not send stale input.
- Show a short message that the terminal state changed.
- Keep the typed text in the input if possible.

If sending fails:

- Mark the pending attention as failed.
- Keep the action visible with the error.
- Allow retry or switching to `Guide Foreman`.

If the target is ambiguous:

- Do not send.
- Show target chips.

## Testing

Add focused tests for:

- Chat input routes to the selected pending terminal.
- Typed chat reply supersedes the suggested action for the same fingerprint.
- Multiple waiting terminals require explicit target selection.
- Clicking a terminal row changes the chat workspace target.
- Resolved pending attention disappears from both the row and chat workspace.
- A stale fingerprint prevents sending.

## Non-Goals

- Do not introduce a full per-terminal agent actor system yet.
- Do not add long-term vector memory.
- Do not redesign terminal understanding.
- Do not make the LLM guess terminal targets.
- Do not duplicate terminal suggestion objects into chat state.

## Acceptance Criteria

- Terminal rows and chat show the same pending terminal event.
- The chat clearly displays where a typed message will go.
- In the common one-waiting-terminal case, the user can type without manually selecting a terminal.
- In ambiguous multi-terminal cases, Foreman asks the user to choose.
- Custom typed replies replace stale suggested replies.
- Existing terminal-card click flow continues to work.
