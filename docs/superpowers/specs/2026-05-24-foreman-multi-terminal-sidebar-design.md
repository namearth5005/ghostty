# Foreman Multi-Terminal Sidebar Design

**Date:** 2026-05-24
**Status:** Approved
**Approach:** A (one shared Foreman conversation per sidebar/project, with explicit active-terminal context)

## Goal

Make Foreman work smoothly across many terminals in one sidebar by:

- removing app-global chat session ownership
- aligning chat, row recommendations, and pending-attention actions under one routing model
- making terminal targeting explicit when several terminals are active
- enforcing completed-goal gating across every sidebar entry point
- improving the sidebar UX so the active context is always obvious

## Current Problems

The current product splits into three different behavior paths:

1. Bottom chat sends text through the Foreman agent path.
2. Pending-attention buttons send literal payloads to terminals.
3. Row-level suggested actions send commands directly when a command exists.

These paths do not share one targeting model or one goal-gating model.

The current `AppDelegate` also owns one global `foremanAgent` and one global `foremanAgentStore`, which creates session-stealing behavior when multiple sidebars or windows are active.

## Product Model

Use this mental model:

```text
Terminal rows = navigator
Chat panel = active workspace for the selected project + selected terminal context
Pending attention = terminal-local interrupt state
Project goal = shared project mission state
```

Each sidebar owns one project-scoped Foreman conversation.

That conversation may coordinate many terminals, but only one terminal context is active in chat at a time.

## Architecture

### 1. Session Ownership

Move Foreman chat session ownership out of the app-global singleton path.

The system should become:

```text
ForemanSidebarStore
  -> ForemanSidebarSession / session controller
     -> ForemanConversation
     -> active terminal context
     -> routing state

AppDelegate
  -> shared infrastructure only
     - project goal runtime
     - terminal snapshot capture
     - dispatch queue sending
     - terminal outcome tracking
```

`AppDelegate` should no longer be the source of truth for "the currently active Foreman chat session."

This allows:

- two sidebars/windows to own independent chat sessions
- one sidebar to coordinate many terminals without losing one coherent project conversation

### 2. Unified Sidebar Routing

Every sidebar action should resolve through one routing layer, regardless of surface.

Inputs:

- typed chat text
- row-level recommendation tap
- pending-attention action tap
- selected terminal
- active pending-attention state
- current project goal state

Outputs:

- send a terminal reply
- send a terminal command
- send an approval or choice payload
- guide Foreman in project chat
- reopen, extend, or clear a completed goal
- block and require explicit target selection
- suppress an action because the goal is completed

The UI surface should not determine behavior. The router should.

### 3. State Model

The sidebar needs an explicit active-target model instead of deriving behavior indirectly from whichever message happens to be visible.

Recommended types:

```swift
enum ForemanSidebarIntent {
    case guideForeman(String)
    case sendTerminalReply(terminalID: String, fingerprint: String, message: String)
    case sendTerminalCommand(terminalID: String, command: String)
    case sendPendingAttentionAction(terminalID: String, fingerprint: String, payload: String)
    case reopenCompletedGoal(projectID: String)
    case extendGoal(projectID: String, text: String)
    case clearGoal(projectID: String)
}

enum ForemanSidebarTarget {
    case project
    case terminalReply(terminalID: String, fingerprint: String)
    case ambiguous(options: [ForemanTargetOption])
    case completedGoal(projectID: String)
}
```

The sidebar computes a resolved target from current state before dispatching any action.

## Target Resolution Rules

The target resolution order should be explicit and deterministic:

1. If the selected terminal has active pending attention, use that terminal.
2. Otherwise, if exactly one terminal is waiting, use that terminal.
3. Otherwise, if the focused terminal is waiting, use that terminal.
4. Otherwise, if multiple terminals are waiting and no explicit target is selected, do not guess.
5. Show target chips and require explicit target selection.

Examples:

```text
Replying to Codex · term-3
Guiding Foreman for /repo/path
Choose a terminal:
[ Codex · term-3 ] [ Kimi · term-5 ] [ Guide Foreman ]
```

This avoids silent misroutes for short inputs like "yes", "continue", or "do that".

## Chat and Row Alignment

Chat, row suggestions, and pending-attention controls should be three views over the same action model, not three unrelated systems.

Rules:

- if a row suggestion is executable, it resolves to a routed intent
- if a row suggestion is informational only, either:
  - convert it into a routed `guideForeman` intent, or
  - remove it from the interactive affordance layer
- pending-attention actions remain terminal-local, but they still go through the same router
- typed chat replies to a waiting terminal supersede older suggested replies for the same fingerprint

That means:

- no dead text pretending to be an action
- no separate logic tree for "chat path" versus "row path"
- one place to enforce project-goal policy and stale-state checks

## Completed Goal Gating

Completed-goal behavior must apply to all sidebar entry points, not just the Foreman agent path.

When project goal status is `completed`:

- suppress automatic Foreman follow-up drafting
- suppress row-level executable "do more work" suggestions
- suppress "recommend next step" reply-drafting actions
- show an explicit completion state instead:
  - `Reopen`
  - `Extend goal`
  - `Close goal`

Allowed actions in this state:

- reopen the goal
- replace the goal
- clear the goal
- inspect terminal state without dispatching more work

This keeps completed goals latched consistently across the full sidebar.

## Stale-State Safety

Every terminal-local reply or action should continue to be guarded by:

- `terminalID`
- `fingerprint`

Rules:

- if the target fingerprint disappears before send, do not silently reroute
- preserve the typed draft text
- show that the target changed
- require the user to retarget explicitly or switch to project guidance

If a user types a custom reply for a waiting terminal:

- that custom reply supersedes any older suggested reply for the same fingerprint
- the old suggestion should disappear or become inert
- stale buttons must not remain clickable after the replacement reply is sent

## Sidebar UX

### Terminal List

Terminal rows remain the navigator.

Each row shows:

- title
- cwd
- summarized state
- agent context
- pending-attention summary
- actionable recommendations, only when they are real routed actions

### Chat Header

The chat header should always show the current destination:

- `Replying to Codex · term-3`
- `Guiding Foreman for ghostty`
- `Goal complete for ghostty`
- `Choose a terminal`

This header is the source of truth for where the next message goes.

### Footer Controls

Footer controls must derive from the resolved sidebar target, not from the last visible conversation bubble.

This prevents the current mismatch where a terminal-specific approval can exist while the footer is showing generic reply controls for another selected row.

### Selection Behavior

Selecting a row updates the active terminal context.

If the selected terminal becomes irrelevant or disappears:

- if another pending target is unambiguous, advance to it
- otherwise fall back to project guidance mode

## Implementation Shape

Expected file-level changes:

- add a pure routing/state model for sidebar intents and targets
- replace app-global Foreman chat session ownership with per-sidebar session ownership
- keep shared project-goal runtime in the shared infrastructure layer
- route row suggestions, pending-attention actions, and typed chat through one dispatcher
- move footer/header UI state to the resolved sidebar target model

This is intentionally an evolution of the current Foreman structures, not a full rewrite into a new actor system.

## Testing

Minimum required coverage:

- two sidebar stores can own independent sessions without stealing each other's chat control
- typed chat, row suggestions, and pending-attention buttons resolve through the same routed intent model
- selected terminal drives the active chat target
- ambiguous multi-terminal waiting state requires explicit target selection
- completed goals suppress both chat-driven and row-driven follow-up actions
- stale fingerprint blocks send and preserves user draft
- custom typed reply supersedes prior suggested reply for the same fingerprint
- footer controls, header target, and visible thread remain aligned with the active terminal context

## Non-Goals

- full per-terminal Foreman agent graphs
- long-term memory beyond the existing project goal runtime
- changing Kimi/Claude/Codex pending-attention semantics outside the routing unification needed here
- redesigning the entire sidebar visual language

## Success Criteria

This work is complete when:

1. Multiple sidebars/windows no longer steal one shared Foreman chat session.
2. One sidebar can coordinate many terminals with one coherent project conversation.
3. The user can always tell where the next input will go.
4. Chat, recommendations, and pending attention follow one routing model.
5. Completed goals suppress further work suggestions consistently across the sidebar.
6. Stale terminal attention cannot silently consume user input.
