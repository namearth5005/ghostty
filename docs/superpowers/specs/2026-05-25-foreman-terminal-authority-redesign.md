# Foreman Terminal-Authority Redesign

**Date:** 2026-05-25
**Status:** Validated for review
**Recommendation:** Make terminal-local worker state authoritative and thin Foreman into a narrator/router/voice layer.

## Goal

Redesign Foreman so it no longer behaves like a second worker brain. Terminal-local workers should own local context, local planning, execution, and next-step suggestions. Foreman should own cross-terminal narration, routing, summarization, voice output, autonomy policy, and escalation.

### Suggested Goal Prompt

```text
/goal set Redesign Foreman so each terminal-local worker owns its own context, execution, and next-step suggestions, while Foreman only narrates, summarizes, routes, voices, and escalates across terminals. Replace duplicate planning in Foreman with authoritative structured terminal state, preserve stale-target safety, and make manual and autonomous behavior consistent across many terminals.
```

## Problem

The current architecture has three overlapping planners:

1. `TerminalUnderstandingProjector` derives terminal-local suggested actions.
2. `PendingAgentAttentionFactory` derives a separate pending-attention action model.
3. `ForemanAgent` separately drafts replies, recommends next steps, evaluates goals, and can directly send commands.

This creates a split-brain product:

- terminal cards can imply one next step
- Foreman chat can imply a different next step
- autonomous behavior can be driven by Foreman-authored reasoning instead of worker-local reasoning

The result is ambiguity about who is actually in charge.

## Current-State Validation

The redesign direction is grounded in the current codebase, not just product preference.

### Duplicate Planning Authority Exists Today

- `TerminalUnderstandingProjector` produces terminal-local `suggestedNextActions`.
- `PendingAgentAttentionFactory` separately derives approval and choice actions from the same terminal state.
- `ForemanAgent` separately drafts replies, recommends next steps, evaluates completion, and can directly send commands.

This means the current system has multiple places deciding what should happen next.

### Foreman Still Acts Like A Worker

`ForemanAgent` still has direct execution authority through `onSendCommand`, and it can author recommendation prompts such as “recommend the single most useful next step toward that goal.” That is evidence that Foreman is still behaving like a second worker instead of a thin coordinator.

### Mode And Completion State Are Still Leaky

- `ForemanSidebarSession.receiveUserMessage` recreates a missing in-memory session in `.interactive` mode rather than preserving the previous mode.
- Kimi `plan_mode` is parsed in wire data but is not currently used to drive routing or continuation policy.
- `ForemanAgent.reopenCompletedGoalAfterUserMessageIfNeeded` reopens completed goals on any non-empty follow-up text.

Those are direct examples of why mode policy and goal policy should move out of a monolithic Foreman agent and into explicit shared runtime rules.

### Goal And Terminal State Are Still Split Across Layers

- terminal-local suggestions live in `TerminalUnderstanding`
- completion gating is applied in the router and sidebar store
- active project goal is still stored on `ForemanConversation`
- `ForemanAgent` independently evaluates project goals against observed terminals

This split confirms that the product still lacks one clear semantic authority boundary.

## Non-Goals

- Rewriting the entire macOS sidebar or observation infrastructure first
- Replacing all heuristic terminal understanding immediately
- Building a full event-sourced terminal protocol before the product model is stable
- Removing autonomy entirely

## Approaches Considered

### 1. Keep the current architecture and only clean boundaries

Pros:
- lowest migration risk
- minimal short-term disruption

Cons:
- preserves duplicate planning
- keeps chat and terminal suggestions semantically split
- does not solve user trust problems in autonomous mode

### 2. Recommended: terminal-authoritative state with thin Foreman

Pros:
- matches the intended product model
- scales better to many terminals and voice mode
- removes duplicate planning authority
- keeps recent routing/session work useful

Cons:
- requires a real semantic pivot in the agent layer
- requires a new worker-to-Foreman state contract

### 3. Full event protocol rewrite

Pros:
- strongest long-term protocol surface
- rich replay and auditing

Cons:
- too heavy for the current phase
- unnecessary before the authority model is settled

## Product Model

Use this mental model:

```text
You
  -> Foreman
     -> worker in terminal A
     -> worker in terminal B
     -> worker in terminal C
```

Foreman is the control tower.

Workers are the local brains.

That means:

- Foreman does not freelance shell work when an active worker already owns the task
- Foreman does not invent a second local plan for a terminal that already has one
- terminal-local context stays in the terminal-local worker
- Foreman consumes compressed state, not full raw context by default

## Responsibility Boundaries

### Foreman Owns

- user-facing narration
- voice summary generation
- target resolution and routing
- project or user-intent assignment to workers
- autonomy policy
- escalation and interruption rules
- cross-terminal rollup state
- explicit goal lifecycle controls such as reopen, extend, or clear

### Terminal Worker Owns

- local context and local memory
- local execution loop
- local plan
- next-step suggestion
- blocked, waiting, running, and completed reporting
- terminal-local approval and prompt semantics

### Shared Runtime Owns

- current observed terminal state
- worker session identifiers
- revision tracking
- goal or assignment bookkeeping
- stale-state validation
- pending attention identity

## Goal Model

The redesign should separate user intent from worker execution.

### `UserIntent`

The user-authored top-level objective for a project or visible work area.

Example:

```text
make this terminal production ready
```

### `WorkerGoal`

The assignment a specific terminal-local worker is currently pursuing.

Examples:

```text
investigate failing auth tests
identify required production env vars
compare refactor options for the API layer
```

### `ForemanAssignment`

Foreman’s read-only mapping of which workers are pursuing which intent, plus their status.

Important rule:

- Foreman may persist `UserIntent`
- workers own `WorkerGoal`
- Foreman should not be the authority that decides the next concrete terminal step once a worker is active

## Terminal State Contract

Foreman should consume one small authoritative per-terminal snapshot. This is the control plane. Raw terminal output remains an on-demand evidence plane.

### Required Fields

- `schema_version`
- `terminal_id`
- `worker_session_id`
- `revision`
- `observed_at`
- `ttl_ms`
- `worker_goal`
- `agent.identity`
- `state.lifecycle`
- `state.attention`
- `state.summary`

### Optional Fields

- `state.details`
- `request`
- `suggestions`

### Suggested Shape

```json
{
  "schema_version": 1,
  "terminal_id": "term-123",
  "worker_session_id": "codex-20260525-abc",
  "revision": 42,
  "observed_at": "2026-05-25T10:15:30Z",
  "ttl_ms": 15000,
  "worker_goal": "investigate auth failures",
  "agent": {
    "identity": "codex"
  },
  "state": {
    "lifecycle": "running",
    "attention": "choice_required",
    "summary": "Codex needs a decision on the refactor direction.",
    "details": [
      "Two API strategies were identified.",
      "Current tests still pass."
    ]
  },
  "request": {
    "id": "req-42",
    "kind": "choice",
    "prompt": "Which API direction should I take?",
    "options": [
      { "id": "keep_api", "label": "Keep current API", "recommended": true },
      { "id": "break_api", "label": "Allow breaking change" }
    ]
  },
  "suggestions": [
    {
      "id": "s1",
      "kind": "reply",
      "title": "Keep current API",
      "payload": { "text": "Keep the current API and adapt the internals." },
      "rationale": "Lowest migration risk.",
      "recommended": true,
      "execution": "manual_only",
      "request_id": "req-42"
    }
  ]
}
```

### Normalized Values

`state.lifecycle`:

- `idle`
- `running`
- `blocked`
- `completed`
- `failed`

`state.attention`:

- `none`
- `reply_required`
- `choice_required`
- `approval_required`
- `error`

`suggestions.kind`:

- `reply`
- `command`
- `choice`
- `approval`
- `foreman_prompt`

`suggestions.execution`:

- `manual_only`
- `autonomous_ok`

### Contract Rules

- `summary` must be one voice-friendly sentence
- `details` should contain at most 3 short facts
- `suggestions` should contain at most 3 items
- every actionable suggestion tied to a live request should include `request_id`
- the terminal-authored snapshot is authoritative when present
- legacy or unsupported terminals may still fall back to heuristic understanding

## Manual And Autonomous Modes

The state contract should stay the same in both modes. Only dispatch policy changes.

### Manual Mode

- Foreman may summarize and prefill suggestions
- nothing is sent unless the user explicitly approves or sends it
- the UI should feel like:

```text
Terminal 2 needs input.
Suggested reply from Codex: Keep the current API and adapt the internals.
[Edit] [Send]
```

### Autonomous Mode

- Foreman may automatically dispatch only suggestions marked `autonomous_ok`
- the exact target must still be current and fresh
- approvals, ambiguity, plan mode, low confidence, or completed goals stop continuation
- autonomy is a dispatch policy, not a separate state model

## Routing And UX Rules

### One Resolved Target

Each sidebar must have exactly one resolved destination at a time:

- a specific terminal request
- project-level guidance
- blocked ambiguous state
- completed-goal state

The chat header, footer, row actions, and pending-attention controls must all derive from the same resolved target object.

### Never Guess Across Multiple Waiting Terminals

If multiple terminals are waiting and the target is not explicit:

- do not dispatch
- preserve the draft
- require explicit target selection

### Worker Suggestions Are First-Class

If an active worker already suggested the next reply or action:

- Foreman should surface it
- Foreman should not silently replace it with a Foreman-authored alternative

Foreman may still suggest routing-level actions such as:

- switch attention to another terminal
- launch a new worker
- ask the user to choose between waiting workers

### Voice Rules

Voice must:

- identify project, terminal, agent, and need type
- separate facts from recommendations
- mention when multiple terminals need attention
- ignore stale or superseded requests

## Edge-Case Rules

### Mode Transitions

- sidebar or session recreation must preserve mode
- Kimi `plan_mode` must be a first-class runtime state
- plan mode blocks autocontinue unless the user explicitly resumes
- completed goals must not auto-reopen on generic user text

### Stale State

- every action must echo `worker_session_id`, `revision`, and `request_id` when relevant
- if any of those changed, the action is rejected
- target changes must preserve the draft and force explicit retargeting
- a changed prompt in the same coarse waiting state must still invalidate old UI

### Simultaneous Terminals

- one sidebar owns one session state
- multiple sidebars must never steal each other’s session ownership
- mixed-project terminals must not accidentally share one goal scope

### Approval And Completion

- approvals remain terminal-local, even in autonomous mode
- completed-goal gating applies across chat, rows, suggested replies, and approval controls
- Foreman may propose completion, but final completion should remain explicit and inspectable

## Migration Strategy

### Keep

- `ForemanSidebarRouting`
- `ForemanSidebarSession`
- `AppDelegate` observation and monitor infrastructure for now
- `ForemanProjectGoalRuntime` storage pieces
- stale-target safety concepts already built around terminal identity and fingerprints

### Thin Or Repurpose

- `TerminalUnderstandingProjector` should become the semantic adapter from worker-authored state into UI-friendly understanding
- `PendingAgentAttentionFactory` should derive UI from structured requests and suggestions instead of parsing freeform approval text
- `ForemanConversation` should become transcript and UI status state only

### Replace Or Split

- `ForemanAgent` should stop being a monolithic second brain
- goal evaluation and completed-goal policy should move into shared runtime policy
- any remaining Foreman LLM work should be one-shot planning or narration against immutable observed state, not a second long-lived terminal planner

### Recommended Sequence

1. Make structured terminal-local state the single authoritative control plane.
2. Extract goal and mode policy out of `ForemanAgent`.
3. Thin `ForemanConversation` to transcript and UI status.
4. Replace `ForemanAgent` internals with a coordinator or one-shot planner.
5. Extract shared observation runtime out of `AppDelegate` only after authority boundaries are stable.

## Verification Targets

The redesign should eventually be validated against these behaviors:

- manual mode never dispatches worker suggestions without user approval
- autonomous mode only dispatches `autonomous_ok` suggestions while fresh
- Kimi `plan_mode` blocks continuation
- multiple waiting terminals force explicit targeting
- stale requests invalidate prior reply buttons and drafted actions
- completed goals stay latched until explicit reopen, extend, or clear
- voice summaries name the correct terminal and attention type
- separate sidebars or windows keep independent session ownership

## Final Recommendation

Do not rewrite the whole product. Keep the recent routing and per-sidebar session work. Replace the semantic center of gravity.

The new source of truth should be:

```text
terminal-local worker state -> Foreman narration/routing/voice -> user
```

Not:

```text
terminal-local state + Foreman local planning + pending-attention planning
```
