# Codex Goal Architecture Replication Notes

> Source basis: this document is derived from the provided gist summary of OpenAI Codex's `/goal` implementation, plus parallel architectural analysis. It is optimized for understanding and replication, not for historical completeness.

## Purpose

Codex's `/goal` is not just a slash command that stores a string. It is a thread-scoped runtime subsystem for long-running objectives with:

- persisted state
- lifecycle control
- usage accounting
- budget enforcement
- event-driven continuation
- model-facing tools
- user-facing TUI state

The deepest design choice is this split:

- the model may create a goal and declare it complete
- the system runtime owns pause/resume, accounting, budget limits, and continuation

That asymmetry is what makes the feature reliable.

## Mental Model

Think of `/goal` as a five-layer stack:

1. Persistence: durable source of truth per thread
2. App-server API: set/get/clear + notifications
3. Model tools: narrow semantic surface for the LLM
4. Runtime lifecycle engine: accounting, pauses, resumes, continuation
5. TUI: slash command, status bar, goal visibility

```text
User / TUI
   |
   v
/goal slash command  <---- notifications ----  App-server
   |                                           |
   | set/get/clear                             | persists / broadcasts
   v                                           v
Thread goal runtime  <-------------------->  SQLite thread_goals
   |
   | exposes minimal goal tools
   v
Model
```

## Layer 1: Persistence

### Canonical Table

The gist describes a `thread_goals` table with one current goal per thread:

```sql
CREATE TABLE thread_goals (
    thread_id TEXT PRIMARY KEY NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    goal_id TEXT NOT NULL,
    objective TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('active', 'paused', 'budget_limited', 'complete')),
    token_budget INTEGER,
    tokens_used INTEGER NOT NULL DEFAULT 0,
    time_used_seconds INTEGER NOT NULL DEFAULT 0,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);
```

### Why This Shape Matters

- `thread_id` as primary key means this is a current-state register, not an append-only history table.
- `goal_id` is a version token, not just an identifier.
- usage counters live on the same row as lifecycle state, so accounting and budget enforcement can be atomic.

### Required Invariants

- At most one current goal per thread.
- Valid statuses are only:
  - `active`
  - `paused`
  - `budget_limited`
  - `complete`
- `budget_limited` and `complete` are terminal.
- Replacing a goal resets usage and assigns a new `goal_id`.
- Usage accounting must be able to reject stale writes from old goal versions.
- Budget enforcement must happen in the same write path as usage accounting.

### Critical Concurrency Primitive: `goal_id`

This is the most important persistence detail.

Every replacement generates a new UUID-like `goal_id`. Later updates can pass an `expected_goal_id`; if the current row no longer matches, the write is ignored.

This protects against the core race:

```text
old goal in flight
    |
user replaces goal
    |
late accounting event arrives
    |
stale write must not mutate new goal
```

Without `goal_id` versioning, late tool-completion or accounting events can corrupt the new goal's counters or status.

### Atomic Budget Enforcement

Budget limits are not just runtime logic; they are persistence logic. The write that increments `tokens_used` should also be able to transition the row to `budget_limited` in the same SQL statement.

That avoids a race-prone sequence like:

1. read tokens
2. compare to budget
3. write new status

If replication does not keep budget enforcement atomic with usage updates, it is weaker than the original design.

### Replacement Semantics

The persistence layer needs two different meanings:

- same objective: update in place, preserve usage
- new objective: replace goal, reset usage, new `goal_id`

That is not just a storage optimization; it is the semantic boundary between "same mission with changed metadata" and "new mission".

## Layer 2: App-Server API

### RPC Surface

The app-server exposes three thread-scoped methods:

- `thread/goal/set`
- `thread/goal/get`
- `thread/goal/clear`

This is intentionally small. The API is a coordination boundary, not a full goal-management programming model.

### `thread/goal/set` Does Three Jobs

One method covers:

- create
- replace
- mutate existing goal

Behavior depends on payload:

- new objective: replace, reset counters, new `goal_id`
- same objective: update status and/or budget, preserve counters
- `tokenBudget: null`: remove budget
- omitted fields: no change

Clients should not infer replace-vs-update rules. The server must own that semantic decision.

### Notifications

Two notifications are enough:

- `thread/goal/updated`
- `thread/goal/cleared`

The important replication detail is that these should be full authoritative snapshots, not partial patches. Snapshot notifications keep UI and runtime simpler and safer.

### App-Server Invariants

- Notifications should reflect post-commit state only.
- `set` should be safe for retries.
- Terminal states should remain terminal unless the user replaces or clears the goal.
- `clear` should remove the goal, not soft-delete it ambiguously.

## Layer 3: Model Tools

### Intentional Asymmetry

The model only gets three tools:

- `create_goal(objective, token_budget?)`
- `get_goal()`
- `update_goal(status: "complete")`

The model does not get to:

- pause goals
- resume goals
- clear goals
- mark budget-limited
- arbitrarily mutate status

This is not a missing feature. It is the core safety boundary.

### Why the Tool Surface Is Narrow

- prevents the model from self-authorizing endless work
- prevents it from bypassing interruption semantics
- keeps budget enforcement system-owned
- makes `complete` a strong semantic event

The design principle is:

```text
Model owns mission expression and success declaration.
System owns lifecycle governance.
```

### Completion Budget Report

When a budgeted goal is marked complete, the tool can return a budget report alongside the final goal state. That is a subtle UX decision with architectural implications: accounting is not just enforcement, it is something the model can surface naturally to the user at closeout time.

## Layer 4: Runtime Lifecycle Engine

This is the heart of the system.

### Runtime State Machine

Statuses:

- `active`
- `paused`
- `budget_limited`
- `complete`

Intended transition meanings:

- `active -> paused`: user or system interruption
- `paused -> active`: thread resume
- `active -> budget_limited`: runtime accounting crossed budget
- `active -> complete`: explicit model success declaration
- `clear`: deletion, not a status transition

Only `budget_limited` and `complete` are terminal. `paused` is resumable by design.

### Event Bus

The runtime listens to lifecycle events such as:

- turn started
- tool completed
- turn finished
- task interrupted
- thread resumed
- maybe-continue-if-idle
- external mutation starting
- external set
- external clear

This is best understood as a reducer over session events.

That is stronger than embedding goal logic into tool handlers or the TUI because:

- accounting stays consistent
- interrupts are first-class
- resume behavior is centralized
- external mutations and turn lifecycle share one policy engine

### Accounting Model

The runtime maintains two incremental snapshots:

- token accounting snapshot
- wall-clock accounting snapshot

It computes deltas:

```text
current - last_accounted = persistable usage delta
```

This avoids double-counting and allows multiple lifecycle events to account usage safely.

### Serialization Guard

Accounting updates must be serialized. The gist references a `Semaphore(1)` guard around accounting updates. That is not incidental. Without serialization, `ToolCompleted` and `TurnFinished` can race and overcount.

### Budget-Limit Steering

When accounting crosses a token budget, the runtime can inject budget-limit steering into the response stream. This should be suppressed:

- on the completion turn
- after the first budget-limit report for the same goal version

This is another place where `goal_id` versioning matters.

### Continuation Model

The system supports one-shot continuation, not a free-running autonomous loop.

Triggers:

- thread resume
- external activation or set-to-active
- maybe-continue-if-idle

Guardrails:

- no continuation if thread is busy
- no continuation if another continuation is already in flight
- no continuation in Plan mode
- no continuation for terminal goals
- no continuation after a no-tool continuation turn

### No-Tool Suppression

One of the best design choices:

- if a continuation turn produces zero tool calls, suppress the next automatic continuation

This prevents recursive "I'll continue..." loops where the model talks but does not act.

### How the Loop Stops

The continuation engine is intentionally conservative. It stops or declines to continue when:

- goal is `complete`
- goal is `budget_limited`
- continuation is suppressed after a no-tool continuation
- thread is not idle
- another continuation is already in flight
- plan mode is active
- user interruption pauses the goal

The key property:

```text
An active goal can exist without immediate execution.
```

"Goal exists" and "another automatic turn should fire right now" are separate questions.

## Layer 5: TUI / UX

### Slash Command

`/goal` is not just a setup action. It is available inline and during active task execution, which makes it part of the live control loop.

Its responsibilities:

- create or replace the current thread goal
- show current goal state
- let the user steer runtime lifecycle without leaving the thread

### Status Bar

The status bar displays:

- goal objective
- status
- elapsed time
- token usage

This matters more than it seems. A goal system without continuous visibility becomes untrustworthy. Codex makes the goal feel like thread state, not hidden metadata.

### Resume Ordering

On thread resume, the right order is:

1. emit goal snapshot notification
2. apply runtime resume effects
3. reactivate paused goals when appropriate
4. maybe continue the goal if the thread is idle

This prevents races where work resumes before clients understand the current goal state.

## Architectural Principles Worth Copying

### 1. Goals are runtime state, not prompt state

Do not model a goal as just another piece of conversation context. Persist it as thread runtime state with lifecycle, accounting, and notifications.

### 2. The model should not own lifecycle authority

If the model can pause/resume/clear goals, the system loses its ability to enforce interrupts, budgets, and consistent continuation semantics.

### 3. Continuation should be trigger-based, not self-sustaining

One continuation per trigger is a much safer design than "keep going while goal is active".

### 4. Accounting must be incremental and serialized

Absolute recomputation is brittle. Parallel delta writes without locking are also brittle.

### 5. Replace and update are semantically different

Changing the objective means new mission, new version, reset usage. Editing budget or state on the same objective should preserve accounting.

## Replication Pitfalls

If you were re-implementing this architecture, these are the main ways to get it wrong:

- treating the goal as prompt memory instead of persisted runtime state
- keying updates only by `thread_id` and omitting `goal_id` version checks
- enforcing budgets outside the DB write path
- allowing the model to pause or resume goals
- making continuation a free-running loop
- forgetting pre-mutation accounting before external set/clear
- conflating "goal exists" with "goal should auto-run now"
- using patch-style UI updates instead of authoritative snapshots

## Recommended Replication Order

1. Add `thread_goals` persistence with `goal_id` versioning.
2. Implement storage methods:
   - get
   - insert
   - replace
   - partial update
   - pause active
   - delete
   - account usage atomically
3. Define explicit transition rules.
4. Build `thread/goal/set|get|clear`.
5. Add `updated` and `cleared` notifications.
6. Expose minimal model tools:
   - create
   - get
   - complete
7. Add runtime lifecycle event handling:
   - accounting
   - interrupts
   - resume
   - continuation suppression
8. Add TUI visibility and slash command wiring.

## Practical Bottom Line

The `/goal` feature is best understood as a thread-scoped goal runtime, not a command.

Its strongest design decisions are:

- one durable goal register per thread
- versioned replacements with stale-write rejection
- atomic usage + budget enforcement
- event-driven runtime lifecycle
- conservative continuation
- a deliberately weak model control surface

If you preserve those properties, you can replicate the architecture faithfully. If you drop them, you may keep the UI shape but you will not keep the behavioral guarantees that make the system dependable.
