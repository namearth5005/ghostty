# Foreman Terminal Understanding Design

Date: 2026-04-30
Project: Ghostty macOS AI Foreman
Status: Draft approved in conversation, written for review

## Summary

The next Foreman phase should make Ghostty feel like a conversational terminal interpreter first and a command runner second. The primary user value is not more automation. It is faster understanding.

Foreman should watch terminal activity, condense noisy output into plain English, answer questions about what happened, and suggest likely fixes when something fails. Execution remains approval-gated. Multi-terminal behavior stays independent-by-default in v1 to avoid incorrect inferred relationships between unrelated terminals.

## Goals

- Make Foreman useful even when the user does not want it to run commands.
- Let the user understand what happened in a terminal without reading the full raw output.
- Preserve a normal inspectable sidebar while shifting heavy compression into chat and voice.
- Suggest likely next actions after failures, with a clear recommendation and fallbacks.
- Support many visible terminals in one session, but summarize them independently unless the user narrows focus.

## Non-Goals

- Automatic cross-terminal task inference.
- Autonomous multi-terminal orchestration.
- Team sync or collaboration features.
- Deep memory-driven planning as a requirement for the first version.
- Continuous background intelligence across every terminal forever.
- Large productization or paywall work beyond existing gates.

## Product Model

Foreman becomes one assistant with two layers:

- Sidebar layer: operational truth. It shows watched terminals, per-terminal state, suggestions, approvals, and inspectable detail.
- Conversation layer: compressed understanding. It answers what happened, what matters, what failed, and what to do next in chat or voice.

Core rule:

Foreman should interpret terminals before it tries to control them.

## User Experience

### Default Scope

- All visible or available terminals are eligible by default.
- The system treats terminals independently by default.
- The user can later narrow focus to one terminal or a subset of terminals.

### Foreman Responsibilities

For a single terminal, Foreman should answer these questions in order:

1. What is this terminal currently doing?
2. What happened most recently?
3. Did it succeed, fail, or stall?
4. What important details matter?
5. What should happen next?

### Summary Behavior

Summaries should be adaptive:

- If one important thing changed, mention only that.
- If several things changed, give a short recap plus the top priority.
- If nothing important changed, say that explicitly.

Example:

```text
Terminal 5 is idle now. The last command failed because `hfind` is not installed.
This looks like a typo rather than an environment issue.
Most likely next step: run `find . -print`.
Alternatives: verify whether you meant `fd`, or install the missing tool if `hfind` was intentional.
```

### Sidebar vs Chat/Voice

The sidebar should remain a normal control surface. It is not the main compression layer.

| Surface | Purpose |
|---|---|
| Sidebar | Rawer operational view, per-terminal state, suggestions, approvals |
| Chat/voice | Condensed understanding, answers, short recaps, next-step guidance |

## Functional Requirements

### Per-Terminal Understanding

Foreman should maintain a structured summary for each visible terminal:

```text
TerminalSummary
- terminal_id
- current_state: idle | running | succeeded | failed | waiting | noisy_healthy
- last_meaningful_event
- short_explanation
- important_details[]
- suggested_next_actions[]
```

`noisy_healthy` means the terminal is producing output but there is no sign of failure or blocked progress. This avoids over-reporting expected log noise as a problem.

### Suggestion Contract

When Foreman detects a failure or stall, it should provide:

1. A concise explanation of what happened.
2. A ranked list of 2-3 likely next actions.
3. One recommended next action.
4. Approval before any execution.

### Multi-Terminal V1 Behavior

- Foreman sees all terminals that are in scope.
- It summarizes each terminal independently.
- It does not try to invent a shared story across terminals by default.
- It can still produce a short overall recap by composing independent summaries.

## Architecture

The system should be split into four layers:

| Layer | Responsibility |
|---|---|
| Terminal Observation | Capture snapshots, detect changes, extract meaningful signals |
| Terminal Understanding | Build per-terminal summaries and classify success, failure, stall, or healthy noise |
| Conversation Orchestrator | Answer user questions, decide whether to summarize, suggest, ask, or act |
| Execution / Approval | Propose commands, wait for approval, execute, and feed results back into observation |

ASCII flow:

```text
+--------------------+
| Terminal snapshots |
+----------+---------+
           |
           v
+-------------------------+
| Observation layer       |
| - diff snapshots        |
| - detect state changes  |
| - identify noise/signal |
+-----------+-------------+
            |
            v
+-----------------------------+
| Understanding layer         |
| - summarize one terminal    |
| - classify failure/success  |
| - build next-step options   |
+-------------+---------------+
              |
              v
+-----------------------------+
| Conversation orchestrator   |
| - answer in plain English   |
| - adapt summary length      |
| - decide suggest vs ask     |
| - route to approval if act  |
+-------------+---------------+
              |
              v
+-----------------------------+
| Execution / approval        |
| - propose command           |
| - wait for approval         |
| - run in chosen terminal    |
| - feed result back in       |
+-----------------------------+
```

## Codebase Mapping

The design should map to the current macOS Foreman code like this:

- `ForemanAgent.swift`
  - Own the conversation orchestration layer.
  - Reason over structured terminal summaries instead of raw terminal noise whenever possible.

- `ForemanChatView.swift`
  - Remain the primary compressed explanation surface for text and future voice interactions.

- `ForemanSidebarView.swift`
  - Remain the inspectable operational surface.
  - Show watched terminals, status, and approval opportunities without becoming the primary summarizer.

- `ForemanMemoryStore.swift`
  - Stay optional in the first implementation.
  - Later support retrieval of similar failures and successful past fixes.

- LLM clients
  - Consume structured terminal-understanding context.
  - Avoid using raw snapshots as the first or only reasoning substrate when structured summaries are available.

## Scope Split

### V1 In Scope

- Per-terminal state detection.
- Plain-English single-terminal summaries.
- Adaptive chat and voice compression.
- Ranked fix suggestions on failure.
- Explicit approval before execution.
- All-terminals-visible baseline with independent terminal summaries.
- User focus selection for one terminal or a subset later in the session.

### V1 Out of Scope

- Automatic cross-terminal task inference.
- Autonomous multi-terminal orchestration.
- Team sync.
- Heavy store or paywall expansion work.
- Full memory-driven repair planning.
- Long-lived autonomous background analysis of every terminal.

## Implementation Phases

```text
Phase 1: Understand one terminal well
    |
    v
Phase 2: Explain it conversationally
    |
    v
Phase 3: Suggest fixes safely
    |
    v
Phase 4: Scale to many independent terminals
    |
    v
Phase 5: Add memory and smarter recovery
```

### Recommended Order

1. Build structured terminal-understanding output for one terminal.
2. Make chat and voice answer from that structure first.
3. Add ranked failure-recovery suggestions.
4. Add independent multi-terminal overview.
5. Add user focus controls.
6. Add memory retrieval to improve summaries and fix suggestions.

## Testing Strategy

The implementation plan should include tests for:

- Per-terminal state classification from representative snapshots.
- Summary adaptation when nothing changed, one thing changed, or several things changed.
- Failure explanation and ranked fix suggestion generation.
- Approval gating for all execution paths.
- Independent multi-terminal summaries without accidental cross-terminal merging.

## Risks

| Risk | Mitigation |
|---|---|
| LLM overfits to noisy raw terminal text | Prefer structured summaries over raw snapshots |
| False relationships between terminals | Keep terminals independent by default |
| Repetitive summaries | Use adaptive recap behavior |
| Low trust in command execution | Keep approvals explicit |
| Scope creep into orchestration too early | Enforce the v1 out-of-scope list |

## Decision Summary

| Topic | Decision |
|---|---|
| Primary value | Terminal understanding first, control second |
| Default scope | All terminals visible |
| Default relationship | Independent terminals |
| Summary surface | Chat and voice for compression, sidebar for inspection |
| Suggestion behavior | Ranked 2-3 options with one recommendation |
| Execution | Approval required |
| Memory | Helpful later, not required for first win |

