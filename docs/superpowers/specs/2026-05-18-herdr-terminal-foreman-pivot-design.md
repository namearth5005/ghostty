# Herdr Terminal Foreman Pivot Design

## Purpose

Define the product direction for pivoting away from the current Ghostty Foreman architecture and toward a terminal-first system built on top of `herdr`'s runtime model.

The goal is not to preserve the current Foreman implementation. The goal is to preserve the user outcome:

- run several real terminal projects at once
- let AI read and understand what is happening
- get concise explanations instead of terminal noise
- get a suggested next reply or action
- optionally let the AI continue autonomously
- require human confirmation before a project is marked complete

## Product Thesis

The product should be a **terminal-first AI foreman**.

It should not feel like a chat app that happens to talk to terminals. It should feel like real terminals are running normally while an AI supervision layer sits above them and turns many projects into one understandable control surface.

The core value is:

- visibility across multiple projects
- plain-English understanding of terminal state
- useful suggested next actions
- optional autonomous progress
- human-controlled completion

The hero use case is a user running multiple projects in parallel while mostly doing something else. When they look back, they should not have to read raw terminal output to recover context. The product should already tell them:

- what happened
- why it matters
- what the recommended next step is
- whether the AI already handled it

## Why Pivot

The current Foreman effort has been converging toward the wrong center of gravity.

It has been trying to build:

- project goals
- terminal attention
- suggested replies
- reactive automation
- UI state

inside a chat/sidebar-first architecture.

That makes the product harder to understand and harder to trust. The user does not primarily want a supervisory conversation. The user wants a project overview built on top of real terminals.

`herdr` already aligns better with that product truth because it is:

- terminal-native
- workspace-oriented
- persistent
- agent-aware
- centered on the real pane/session runtime

So the pivot is not "copy a competitor." It is "start from the right runtime abstraction."

## Recommended Direction

The recommended direction is:

```text
herdr runtime/workspace foundation
  +
thin AI supervision layer
  +
project overview UX
```

This means:

- use `herdr` as the base runtime model
- stop preserving the current Ghostty Foreman architecture as the main path
- build only the minimal product layer that creates the desired user experience

## Alternatives Considered

### 1. Ghostty-first Foreman rewrite

Keep Foreman inside Ghostty and redesign the architecture around terminal-first concepts.

Pros:

- keeps native Ghostty integration
- avoids a runtime pivot

Cons:

- continues from an architecture already fighting the product direction
- slower path to a convincing multi-project experience
- keeps too much pressure on the existing Swift/macOS surface

### 2. Herdr-first base with thin AI layer

Fork or spike from `herdr`, then add the AI/product layer on top.

Pros:

- easiest path to terminal-first behavior
- runtime, session, pane, and agent-state problems are largely pre-solved
- aligns directly with the intended product feel

Cons:

- loses continuity with current Ghostty-native Foreman code
- introduces AGPL obligations if adopted as a product base

### 3. Hybrid runtime adapter model

Treat `herdr` as a runtime substrate but design a more abstract product layer intended to support multiple clients later.

Pros:

- strongest long-term architecture
- separates runtime and product cleanly

Cons:

- more system-design work up front
- unnecessary complexity for v1

### Decision

Choose **Option 2 with the mindset of Option 3**:

- start from `herdr`
- build the smallest possible AI supervision layer
- keep boundaries clean enough that the product layer is not deeply tangled with the runtime

## Adoption Constraint

This pivot is not only a technical decision. It is also a product and licensing decision.

If the product is built directly on a fork of `herdr`, that means accepting `herdr`'s AGPL obligations as part of the product strategy.

This spec assumes the team is comfortable with that trade:

- faster path to a credible terminal-first product
- less need to rebuild runtime primitives
- but lower freedom to treat the runtime layer as a closed proprietary base

If that assumption changes, the fallback direction is:

- keep this product design
- copy the runtime ideas
- do not adopt the codebase directly

## Product Identity

This product is:

- a terminal workspace with an AI supervisor layer

This product is not:

- a chat-first agent manager
- a general-purpose planning framework
- a terminal replacement
- a system that lets AI self-certify completion

## Primary User Surface

The primary user surface should be a **project overview**, not a supervisor chat.

The terminal remains the source of truth, but the default user experience should be:

- one card per project
- one clear state per project
- one prominent suggested next move

The project overview should be the first thing the user sees when checking back in on multiple projects.

## Main Screen Shape

The main screen should present **one card per project**.

Each project card should answer three questions immediately:

1. What should I do next?
2. What happened in plain English?
3. Is the AI already handling this, or does it need me?

### Card Layout Priority

The most prominent line should be:

- **suggested next reply/action**

Below that should be:

- a concise explanation of the latest state

Alongside that should be:

- project state
- autonomy mode
- whether human attention is required now

This ordering matters. The product should optimize for fast scanning and fast resumption, not for detailed log reading.

## State Model

V1 should keep the visible state model small and legible:

- `working`
- `needs input`
- `needs approval`
- `done unseen`
- `idle`

Important distinction:

- runtime state and attention state should not be conflated
- a project can be technically idle but still deserve attention because the user has not yet seen the result

This is one of the strongest ideas to inherit from `herdr`.

## Autonomy Model

Autonomy should be **project-scoped**.

Each project should have exactly one mode:

- `Interactive`
- `Autonomous`
- `Paused`

### Interactive

- AI watches and explains
- AI suggests next replies/actions
- AI never acts on its own

### Autonomous

- AI may continue advancing the project
- AI may reply, run commands, edit files, test, and continue work
- AI stops when blocked, uncertain, approval-gated, or likely done

### Paused

- AI does not advance the project
- project remains visible in the overview

### Global Rules

Two rules must remain universal:

1. Risky checkpoints still stop and surface clearly.
2. Completion always requires human confirmation.

## Completion Rule

The system must distinguish:

- **autonomous progress**
- **completion authority**

Autonomous progress means the AI can keep moving the project forward without asking every time.

Completion authority stays human-owned.

When the AI believes a goal is done, it should stop at a checkpoint and say:

- what changed
- why it believes the goal was satisfied
- ask the human to confirm completion

The AI may propose completion. It may not silently mark the project complete.

Simple rule:

```text
AI can do work.
Human decides when the goal is complete.
```

## Runtime Architecture

The runtime architecture should remain minimal:

```text
Real terminals
  ->
Runtime/workspace layer
  ->
AI understanding layer
  ->
Project overview cards
  ->
Optional actions back into terminals
```

### Real Terminals

Real terminals remain the source of truth. Agents still run in their native terminal environments.

### Runtime / Workspace Layer

This layer is effectively what `herdr` already provides:

- sessions
- panes
- tabs
- workspaces/projects
- persistent runtime
- attach/detach
- agent detection
- local control API

This layer should not be rebuilt first.

### AI Understanding Layer

This is the custom product layer. Its responsibilities are:

- read terminal/agent state
- explain what happened in plain English
- determine whether the project needs attention
- suggest the next reply or action
- continue autonomously when the project mode allows it

### Overview Layer

The overview layer is the human control surface. It should aggregate terminal activity into project cards instead of exposing panes as the primary unit for the first experience.

## Conversation and Context Model

V1 should stay light on memory and context machinery.

The system needs enough context to:

- understand the current project goal
- explain the current terminal situation
- suggest a useful next reply or action

It does not need an elaborate long-lived mission-control memory system in v1.

The product should favor:

- current project goal
- current terminal/runtime state
- recent relevant context

over:

- deep historical abstraction
- chat-first internal memory systems

## V1 Scope

V1 should be intentionally narrow.

### In Scope

1. Project overview screen
2. One card per project
3. Project grouping by workspace/repo/cwd
4. Small visible state model
5. Plain-English explanation of current state
6. Suggested next reply/action
7. Per-project autonomy mode
8. Human-confirmed completion checkpoint

### Explicitly Out of Scope

1. Chat-first supervisor UX
2. Large planning/runtime abstractions
3. Deep strategy or mission-planning systems
4. Fancy long-lived memory systems
5. Automatic completion
6. Complex permission matrices as the main UX
7. Broad platform/client expansion in v1

## First Milestone

The first milestone is not "full architecture completeness."

The first milestone is:

- run several projects at once
- glance at the overview once
- understand every project quickly
- get a useful suggested next action on blocked work
- clearly see which projects need nothing
- clearly see which ones need approval
- clearly see when a project is asking for completion confirmation

That is the first product proof.

## Build Strategy

### Base Assumption

Treat `herdr` as the runtime foundation, not the finished product.

The first development effort should focus on the thin product layer that creates the intended user outcome.

### Practical Development Strategy

1. Start from the cloned `herdr` codebase.
2. Create a dedicated fork or spike branch for this product direction.
3. Do not try to preserve or incrementally port the current Ghostty Foreman architecture into that effort.
4. Build the smallest custom supervision layer possible.
5. Keep the first UI inside the same terminal-first product shape.

### The First Custom Layer Should Only Do Four Jobs

1. Group terminals into projects
2. Produce a concise plain-English explanation of current state
3. Produce a suggested next reply/action
4. Enforce project autonomy mode and human completion confirmation

Anything beyond that should be treated as a later phase unless it directly improves the core multi-project overview demo.

## Why This Is The Easiest Credible Path

This direction is easier because it does not fight the runtime.

`herdr` already gives:

- the real terminal-centric foundation
- the session/workspace model
- the agent-awareness baseline
- the persistence and control substrate

The product work can therefore focus on what actually differentiates the experience:

- understanding
- summarization
- suggestion
- autonomy
- clarity

## Success Criteria

The pivot is successful if the product can convincingly demonstrate:

- multiple projects running in real terminals
- fast understanding without reading raw terminal logs
- useful next-step suggestions
- optional project-scoped autonomy
- human-controlled completion

If those are true, the new direction is productively aligned even before broader polish or deeper architecture work.
