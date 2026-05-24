# Foreman Project Goal Runtime Design

## Purpose

Foreman should not treat long-running mission intent as loose chat context, and it should not overload terminal reply cards with persistent goal semantics. Instead, it should separate:

- project-scoped long-lived mission control
- terminal-scoped local interaction and interruption handling

This design introduces a project-scoped goal runtime architecture that complements the existing terminal attention system.

## Core Model

The recommended architecture is:

```text
Foreman
  ->
Project Registry
  ->
Project Goal Runtime
  ->
Terminal Assignment
  ->
Terminal Attention
```

### Project Registry

The project registry identifies active projects based on terminal repo roots and working directories. It owns:

- project identity
- project title
- root path
- active terminal membership

This is the top-level scope boundary. Foreman should not have one global goal for all work across all repos. It should have one goal per project.

### Project Goal Runtime

Each project gets one goal runtime. This is the long-lived mission for that project.

Examples:

- `mend`: "Support ChatGPT first without breaking Claude Code behavior"
- `ghostty`: "Implement a robust project goal runtime for Foreman"
- `strata`: "Fix the backend deploy issue"

The first implementation should be hybrid in shape:

- state stored in memory for now
- API and lifecycle shaped so local persistence can be added later without redesign

The runtime API should already support operations like:

- set goal
- get goal
- clear goal
- update status

### Terminal Assignment

Each terminal belongs to one project. Terminal-to-project assignment should be:

- automatic by repo root or cwd first
- clarified with the user only when ambiguous

This lets Foreman reason from the correct project goal when a terminal asks for input.

### Terminal Attention

Terminal attention remains terminal-local. It is used for:

- approvals
- choices
- replies
- errors
- local interruptions

It should not become the source of truth for the project mission.

## Interaction Model

Foreman should handle terminal events using this flow:

```text
Terminal asks for something
      |
      v
Foreman identifies the project
      |
      v
Foreman reads:
- project goal
- project policy file
- terminal context
      |
      v
Foreman decides:
- resolve automatically
- or ask the human
```

### Needs Direction

`Needs direction` should be a plain reply flow.

User messages in this state should:

- go directly to the waiting terminal agent
- not invoke reevaluation UI by default
- not silently become project goal updates

Future enhancement:

- an explicit `reply + adopt as project goal` action may exist later

But that should not be part of v1.

### Approval / Choice

Approvals and choices remain terminal-local action cards.

Foreman may recommend which option is best, but the interaction is still local to the terminal and should not be confused with changing the project mission.

### Set / Edit Project Goal

Project goal editing should be a separate control path from reply cards.

This is where the long-lived mission changes. It should not be mixed into a terminal reply experience.

## Key UX Rule

The core user-facing rule is:

```text
Reply card = answer this terminal
Goal control = change this project's mission
```

That split is cleaner than asking one card to do both jobs.

## Project Goal Runtime Lifecycle

Each project goal runtime should use a simple lifecycle:

```text
No goal
  ->
Active
  ->
Paused
  ->
Active
  ->
Complete
```

Failure path:

```text
Active
  ->
Stuck
```

### State Meanings

- `No goal`
  - the project exists, but no current mission has been set

- `Active`
  - Foreman may use this project goal to decide what to do and whether it can resolve terminal events automatically

- `Paused`
  - the mission still exists, but Foreman should not keep autonomously advancing it
  - useful for interruptions, context switches, or explicit pause

- `Complete`
  - Foreman believes the project mission has been satisfied
  - it should summarize why

- `Stuck`
  - Foreman believes it cannot continue without missing information, conflicting constraints, or human input

### State Ownership Rule

Project goal state belongs to the project, not to any single terminal.

If one terminal closes, the goal does not disappear. Only these things should change the goal:

- user sets a new goal
- user clears the goal
- user pauses/resumes it
- Foreman marks it complete
- Foreman marks it stuck

## Why This Architecture Is Better

This design is better than overloading reply cards with mission semantics because it cleanly separates:

- persistent project mission
- disposable terminal interaction

This avoids several problems:

- confusing users about whether they are changing the mission or answering one terminal
- losing project intent when terminals close
- coupling long-lived mission state to ephemeral local UI
- making voice interaction harder later by overloading one reply surface

## Relationship To Codex `/goal`

Codex's `/goal` architecture is a strong backbone for the project-goal runtime portion of Foreman, but it should not be copied literally as the entire product model.

What maps well:

- persisted long-running objective
- lifecycle states
- system-owned pause/resume semantics
- explicit completion and stuck handling
- narrow model-facing mission semantics

What does not map directly:

- Codex is mostly thread-centric
- Foreman is multi-terminal and must still keep terminal-local attention items

So the right adaptation is:

```text
Codex-style project goal runtime
+ existing Foreman terminal attention model
```

not:

```text
replace terminal attention with one global goal mechanism
```

## Multi-Project Support

This design is intended to work across multiple unrelated repos at once.

Foreman should support:

```text
Foreman
  |
  |-- Project: mend
  |     |-- project goal
  |     |-- terminal subgoals
  |
  |-- Project: ghostty
  |     |-- project goal
  |     |-- terminal subgoals
  |
  |-- Project: strata
        |-- project goal
        |-- terminal subgoals
```

That prevents cross-project context leakage and lets each repo have its own mission, completion logic, and terminal activity.

## Implementation Direction

Recommended first steps:

1. Introduce a project registry and terminal-to-project assignment.
2. Add an in-memory project goal runtime with the final intended API shape.
3. Keep `Needs direction` as a plain reply flow.
4. Keep terminal attention cards local and separate from goal editing.
5. Add project policy-file support so Foreman can answer more terminal questions autonomously under the project goal.
6. Add local persistence for the project goal runtime after the in-memory model is proven.

## Non-Goals For First Version

The first version should not:

- silently turn terminal replies into project goals
- merge goal editing into reply cards
- attempt one giant global goal across unrelated projects
- replace terminal-local approvals and choices with project-goal logic

## Summary

Foreman should use:

- one goal runtime per project for long-lived mission control
- terminal-local attention cards for immediate interaction

This gives:

- better autonomy
- clearer user mental model
- safer multi-project behavior
- a clean path to persistence later
