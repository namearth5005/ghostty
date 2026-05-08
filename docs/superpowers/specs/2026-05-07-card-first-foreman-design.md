# Card-First Foreman Design

Date: 2026-05-07
Project: Ghostty macOS AI Foreman
Status: Approved direction

## Summary

Foreman should feel like an operations console for AI-agent terminals, not a
chatbot attached to a terminal. It watches quietly, understands terminal-agent
state, and surfaces the current human decision as a direct action on the
terminal card.

Chat remains useful for explanation, diagnosis, and discussion, but it is not
the primary reactive surface. Internal terminal events must not appear as
visible chat messages.

## Product Principle

The terminal card is the primary control surface.

When an agent needs attention:

- deterministic approval prompts become approval buttons on the terminal card
- deterministic choice prompts become choice buttons on the terminal card
- text prompts show manual reply controls and, when useful, one suggested reply
- unclear errors can ask the Foreman LLM for diagnosis
- chat only shows user-visible interpretation or explicit Foreman suggestions

## Current Problems

The current branch mixes several incompatible state models:

- `AgentStateMonitor` emits by coarse state and cooldown, not by request identity.
- `ForemanAgent.react(to:)` appends internal context to visible chat.
- `ForemanSidebarStore` has terminal rows but no persistent pending-attention
  source of truth.
- `ConversationUIPhase` depends on `conversation.goal`, so reactive approval
  flows can look like a fresh "What should I do?" session.
- Kimi/Codex/Claude wire state is available to sidebar understanding, but
  Foreman agent planning re-runs understanding without the same wire context.

The result is a UI that can spam, loop, ask the LLM for deterministic prompts,
or hide the one action the user actually needs.

## Target Architecture

```text
TerminalSnapshot + AgentSignalProvider
        |
        v
TerminalUnderstanding
        |
        v
AgentStateMonitor / AttentionLedger
        |
        v
ForemanSidebarStore.pendingAttentionByTerminalID
        |
        v
TerminalSummaryRow direct actions

Only ambiguous cases:
        |
        v
ForemanAgent semantic helper + hidden context
```

## Core Models

### Agent Attention Event

`AgentNeedsAttentionEvent` represents a new actionable request from an agent.
It must carry a stable fingerprint.

The fingerprint is derived from:

- terminal ID
- agent identity
- interaction state
- request details
- choice labels when present
- tool/session identifiers when available

### Pending Agent Attention

`PendingAgentAttention` is the sidebar source of truth.

It contains:

- terminal ID
- agent identity
- interaction state
- fingerprint
- title
- description
- optional detail
- typed actions
- creation timestamp
- resolution state
- optional inline error

Rows are projections of this state. Snapshot refreshes should not erase an
unresolved pending item unless the terminal disappears, leaves the waiting
state, or presents a new fingerprint.

### Hidden Context

Foreman can collect hidden prompt context for LLM calls, but hidden context is
not part of visible chat history. It can include raw terminal details, event
fingerprints, and current understandings.

Visible chat messages should be limited to:

- user-authored chat
- Foreman's explicit explanations
- Foreman's suggested semantic next step
- command/action approval messages when the user is in an active chat session

## Routing Policy

| Agent state | Default route | LLM? |
| --- | --- | --- |
| `waitingApproval` | pending terminal-card approval | no |
| `waitingChoice` | pending terminal-card choices | no |
| `waitingText` | pending reply control, optional suggested reply | only for suggestion |
| `error` | deterministic recovery if obvious, otherwise diagnosis | sometimes |
| `running` | status only | no |
| `completed` | status only | no |

## Terminal Card Behavior

Pending attention renders before generic suggested actions.

Kimi approval should expose:

- Approve once
- Approve session
- Reject / Tell model

Generic approval should expose:

- Approve
- Reject

Choice prompts should expose the parsed choices. If there are too many choices,
show the first few and fall back to manual reply for the rest.

Text prompts should expose:

- a manual reply field or action entry point
- a suggested reply only after Foreman has enough context to suggest one

## State Ownership

`AgentStateMonitor` owns only transition/fingerprint tracking.

`ForemanSidebarStore` owns pending attention and UI projection state.

`ForemanAgent` owns semantic LLM work. It should not be the default receiver for
deterministic approval or choice events.

`ForemanConversation` should remain the visible conversation projection. It may
hold hidden context as prompt material, but UI should never render it as chat.

`AppDelegate` should route events but should not encode product policy inline
after this layer exists.

## Agent Signal Direction

The immediate implementation can keep existing Kimi/Codex/Claude monitors, but
the next structural layer should normalize them through an `AgentSignalProvider`
protocol.

Signals should carry:

- agent identity
- session ID when available
- terminal binding evidence
- timestamp
- sequence or offset
- interaction context
- freshness/confidence

The engine should prefer fresh, strongly-bound signals over screen heuristics.
Global newest-session fallback should be low confidence.

## Error Handling

If sending a pending action fails, keep the pending item visible and show an
inline error on the terminal card.

If the terminal disappears, remove the pending item and resolve the monitor
state.

If an LLM suggestion fails, keep manual input available and show a non-blocking
card error.

If parsing confidence is low, prefer "Needs input" over inventing an action.

## Testing Strategy

The first implementation slice should make the branch compile and cover:

- unchanged approval emits once
- changed approval fingerprint emits again
- resolved fingerprint can emit again
- Kimi approval creates pending attention without invoking the LLM
- choice prompt creates choice actions without invoking the LLM
- hidden context does not render in chat
- failed send leaves pending attention visible with an error
- reactive approval UI works without `conversation.goal`

Manual verification should use Kimi first because it currently exposes the most
visible approval-flow pain.

