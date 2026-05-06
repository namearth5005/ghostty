# Reactive Attention Product Design

Date: 2026-05-06

## Goal

Make Foreman's reactive AI-agent support feel smooth, predictable, and product-ready.
When Kimi, Claude Code, or Codex needs attention, Foreman should surface exactly one
clear decision point in the sidebar. It must not spam chat, loop on unchanged state,
or ask the Foreman LLM to analyze deterministic approval prompts.

## User-Facing Behavior

Foreman reacts differently based on the agent state:

- `waitingApproval`: show one pending approval card with direct actions. Do not call
  the Foreman LLM by default.
- `waitingChoice`: show the available choices as direct actions. Do not call the
  Foreman LLM by default.
- `waitingText`: offer a suggested reply only when there is enough context, using the
  Foreman LLM. Otherwise ask the user for input.
- `error`: show the error and offer deterministic recovery actions if available.
  Use the LLM only for diagnosis or non-obvious next steps.

The chat pane is for user-visible discussion and Foreman's explicit suggestions. It
must not render internal event messages like "Kimi in terminal X is waiting...".

## Architecture

### Agent State Monitor

`AgentStateMonitor` continues to observe `TerminalUnderstanding` values on sidebar
refresh. It should emit events only when an actionable request changes.

Each actionable event gets a stable fingerprint derived from:

- terminal ID
- agent identity
- interaction state
- request text or approval description
- choice labels when present

The monitor suppresses repeated events for the same fingerprint until one of these
happens:

- the terminal leaves the waiting state
- the request fingerprint changes
- the user resolves the pending item
- the terminal closes

This replaces the current one-refresh `foremanReactedToState` suppression, which
allows repeated firing while an approval prompt remains on screen.

### Pending Attention Store

Add sidebar state for pending agent attention, keyed by terminal ID.

Each pending item contains:

- terminal ID
- agent identity
- interaction state
- fingerprint
- title
- description
- detail text
- options or approval actions
- creation timestamp
- resolution state

This store is the source of truth for terminal-card action UI. It is separate from
`ForemanConversation.messages` so internal state does not pollute chat history.

### Terminal Card UI

Terminal cards render pending attention directly:

- Kimi approval: `Approve once`, `Approve session`, `Reject`, `Tell model...`
- Generic approval: `Approve`, `Reject`
- Choices: one button per choice, capped to a small visible count
- Text input: `Suggest reply` and, when available, one specific suggested reply
- Error: `Retry` only when retry is semantically valid

Buttons execute raw agent inputs through the existing dispatch path. The label must
match what will be sent closely enough that users can trust it.

### Foreman Agent / LLM

`ForemanAgent.react(to:)` should no longer append visible user messages for internal
events. It should accept hidden context when LLM analysis is needed.

The LLM is skipped entirely for deterministic states:

- approval prompts with known actions
- choice prompts with known options

For `waitingText` and unclear errors, the LLM is allowed to produce one suggested action. In
interactive mode that action is stored as a pending attention suggestion, not
immediately sent.

### Conversation UI Phase

Reactive mode must not depend on `conversation.goal` to display the correct input
state. If the conversation is `waitingForUser` and the last action is a pending
command or reply, the UI shows the approval/reply controls even when there is no
manual goal.

## Data Flow

1. Sidebar refresh captures snapshots.
2. `TerminalUnderstandingEngine` classifies agent state.
3. `AgentStateMonitor` emits an event only if the request fingerprint is new.
4. Deterministic states update `pendingAttentionByTerminalID` without calling the LLM.
5. Semantic states call `ForemanAgent.react` with hidden context.
6. Terminal cards render pending attention.
7. User action sends the selected raw input and marks the pending item resolved.
8. Monitor remains suppressed until terminal state changes or a new fingerprint appears.

## Error Handling

- If sending an action fails, keep the pending item visible and show an inline error.
- If the terminal disappears, remove its pending item.
- If the LLM fails for a semantic suggestion, show a non-blocking card error and keep
  manual input available.
- If a prompt cannot be parsed confidently, prefer "Needs input" over inventing an
  action.

## Testing

Add tests for:

- unchanged `waitingApproval` emits once, not every refresh
- resolving a pending approval allows future new fingerprints
- Kimi approval creates pending attention without invoking Foreman LLM
- `waitingChoice` creates choice buttons without invoking Foreman LLM
- reactive `waitingForUser` displays approval controls even with `goal == nil`
- hidden context is not appended to visible chat messages
- failed send leaves pending attention visible with an error

Manual checklist:

- Start Kimi at welcome screen: no reactive trigger.
- Ask Kimi to run a shell command requiring approval: one terminal card appears.
- Wait 30 seconds without clicking: no new chat messages and no duplicate card.
- Click `Approve once`: sends `1`, clears pending card after Kimi leaves approval.
- Trigger another different approval: a new card appears.
- Trigger `waitingText`: Foreman can suggest a reply, but no raw context message appears.

## Non-Goals

- Long-term memory integration.
- Prompt caching.
- Full redesign of the sidebar visual language.
- Autonomous approval execution by default.
