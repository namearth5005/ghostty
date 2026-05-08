# Reactive Agent Reply Schema Design

## Goal

Foreman should never silently drop a handled `waitingText` event from an AI
agent terminal. When Kimi, Claude Code, or Codex asks for text input, Foreman
should produce one of three explicit UI outcomes: a reply to send to the agent,
a question for the human, or no action.

## Current Problem

The current reactive path reuses the generic autonomous `agentStep` contract.
That contract lets the LLM return `respond`, `send_command`, `ask_user`,
`declare_complete`, or `declare_stuck`. The waiting-text sidebar only renders
`send_command`, so valid `ask_user` output is discarded. This is what happened
when Kimi asked what to do in the `mend` directory: the LLM asked the human for
direction, but the UI had no representation for that outcome.

## Design

Add a dedicated `draftAgentReply` LLM call for reactive `waitingText` events.
The response schema is intentionally narrower than `agentStep`:

```json
{
  "thought": "string",
  "suggestion": {
    "type": "reply_to_agent|ask_human|no_action",
    "terminal_id": "string",
    "message": "string",
    "reason": "string",
    "confidence": 0.0
  }
}
```

`reply_to_agent` becomes a pending attention card with one send button. The
button sends raw text to the AI agent terminal, not shell syntax.

`ask_human` becomes a pending attention card without a terminal-send action.
This keeps Foreman visible and explains what it needs from the user instead of
dropping the event.

`no_action` returns nil and renders nothing. It is reserved for duplicate or
non-actionable waiting text.

## Files

- `macos/Sources/Features/AIForeman/ForemanModels.swift`
- `macos/Sources/Features/AIForeman/ForemanService.swift`
- `macos/Sources/Features/AIForeman/OpenAIClient.swift`
- `macos/Sources/Features/AIForeman/AnthropicClient.swift`
- `macos/Sources/Features/AIForeman/ForemanAgent.swift`
- `macos/Tests/Terminal/ForemanAgentTests.swift`
- `macos/Tests/Terminal/ForemanServiceTests.swift`
- `macos/Tests/Terminal/AnthropicClientTests.swift`

