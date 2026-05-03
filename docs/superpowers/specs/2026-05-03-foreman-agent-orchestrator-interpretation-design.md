# Foreman Agent Orchestrator Interpretation-First Design

Date: 2026-05-03
Project: Ghostty macOS AI Foreman
Status: Draft approved in conversation, written for review

## Summary

The next Foreman slice should make the sidebar and chat feel like one live operator that watches terminal agents, decides when output is worth reading, and tells the user what happened, what terminal it refers to, and what to do next.

This slice is interpretation-first. It does not depend on fixing the broken suggestion buttons inside terminal cards. The execution path already works elsewhere in Foreman. The immediate product value is reliable understanding, not a new control path.

## Product Vision

Foreman is an AI Agent Orchestrator, not just a terminal dashboard.

The intended experience is:

- The user stays in one conversation with Foreman.
- Foreman watches terminal activity in the background.
- Foreman decides when a terminal output is stable enough or important enough to interpret.
- Foreman explains what happened in plain language.
- Foreman points to the exact terminal involved.
- Foreman suggests the next action, especially for lightweight interactive approvals or obvious retries.

The motivating demo is that the user can be doing something else, such as playing a game, while Foreman keeps track of coding-agent terminals and surfaces only the current actionable update.

## Goals

- Detect likely AI coding agents from terminal process metadata and output patterns.
- Infer agent-oriented state such as running, waiting for user input, failed, completed, or idle.
- Use state as an internal gating signal to decide when Foreman should read and summarize output.
- Keep Foreman chat focused on one current terminal subject at a time.
- Generate chat summaries that include a clear terminal reference and an actionable next step.
- Preserve usefulness for non-agent terminals through generic terminal understanding fallbacks.

## Non-Goals

- Fixing the broken suggestion-row click handling in `TerminalSummaryRow.swift`.
- Full multi-terminal orchestration or global importance ranking.
- Perfect detection for every terminal tool or every AI agent.
- New execution infrastructure for terminal actions.
- Autonomous command execution without existing approval flows.

## First-Slice Policy

### Primary Terminal Selection

Foreman should watch all eligible terminals, but chat should focus on one current subject at a time.

The subject-selection rule for this slice is event-driven recency, not global priority scoring:

- When a terminal produces a qualifying update, it becomes the current Foreman subject.
- A newer qualifying update from another terminal can replace it.
- Foreman should not try to compute a full "most important terminal" ranking yet.

This keeps behavior legible: Foreman is talking about the terminal that most recently produced a meaningful update.

### Read Gating

State labels should be internal control signals, not just UI badges.

Foreman should prefer to interpret when output is actionable or stable enough to read:

- `waiting`: read now because the terminal likely needs user input
- `failed`: read now because the user needs a diagnosis or next step
- `completed`: read now because a final result is available
- `running`: read only when there is a sufficiently stable or meaningful update
- `idle` or generic noise: usually do not escalate unless the content itself appears important

This avoids summarizing every transient token while still keeping Foreman live.

## User Experience

### Chat Behavior

Foreman chat should act like a live interpreter, not a state-change log.

Each chat update should:

- be anchored to a specific terminal
- identify what the process or agent is doing
- state whether it is blocked, failed, completed, or still running
- propose the likely next action

The message should refer to the source terminal clearly enough that the user knows where to look. A terminal hyperlink or equivalent terminal reference is required for the product flow.

Examples:

```text
Codex Agent in Terminal 2 is waiting for approval. Suggested next action: approve and continue.
```

```text
Build failed in Terminal 1 because `GameScene` is missing `updateHUD()`. Review that error before retrying the build.
```

### Action Framing

Foreman should distinguish between two categories of suggestions:

- Mechanical next actions
  - approvals
  - simple retries
  - obvious shell responses
- Judgment-required actions
  - inspect an error
  - decide between fixes
  - review a diff or plan

Even before the sidebar button bug is fixed, Foreman should generate the correct suggested-action payloads so the execution path can be reused later from a different UI surface.

## Architecture

The current three-layer structure should remain, but the understanding layer becomes agent-aware and the UI/store layer gains a single current subject concept.

```text
TerminalSnapshot
    |
    v
TerminalUnderstandingEngine
    |
    v
ForemanSidebarStore + Foreman chat subject selection
    |
    v
Chat summary + suggested next action + terminal reference
```

### Layer 1: Snapshot

`TerminalSnapshot` should be extended with:

- `foregroundPID: Int?`
- `foregroundProcessName: String?`

These values should come from the foreground process group already available on the Ghostty side. Process-name lookup should be best-effort on macOS.

### Layer 2: Understanding

`TerminalUnderstanding` should be extended with agent-specific information:

- `detectedAgent: AgentType?`
- `agentState: AgentState`
- `shouldSurfaceToForeman: Bool`

Recommended enums:

```text
AgentType
- none
- codex
- claudeCode
- aider
- cursor

AgentState
- idle
- running
- waitingForUser
- error
- completed
```

Detection should combine process-name signals with output-pattern heuristics so Foreman remains useful even when process lookup fails or is ambiguous.

### Layer 3: Store and Chat

`ForemanSidebarStore` should keep all terminal rows, but it also needs enough state to support a single active Foreman subject:

- current subject terminal ID
- most recent surfaced understanding per terminal
- recency tracking for qualifying updates

When a terminal produces a new surfaced understanding, the store should promote it to the current subject and refresh the Foreman chat-facing summary for that terminal.

## Detection and Inference Rules

### Agent Detection

Agent detection should start with cheap deterministic heuristics:

- process-name matching for `codex`, `claude`, `aider`, `cursor`
- fallback output matching for known prompt or approval strings

Examples of useful output patterns:

- Codex: `Proceed?`, `y/n`, plan-style approval prompts
- Claude Code: `Shall I proceed?`, `Approve?`, `I will:`
- Aider: `Apply this change?`, `Yes/No/All`

The system should be extensible so more patterns can be added without changing the UI layer.

### Agent State Inference

The engine should infer state from a combination of:

- existing terminal signals
- last input preview
- visible text
- recent scrollback
- detected agent type

Examples:

- prompt asking for approval -> `waitingForUser`
- clear error output or failed tool result -> `error`
- final summary with prompt restored -> `completed`
- agent still printing progress or logs -> `running`
- no agent signal -> `idle` or generic terminal state fallback

### Surface Gating

The engine should produce a surfacing decision alongside the understanding:

- true for actionable or stable updates
- false for churn, noise, or non-meaningful refreshes

This is the control point that decides when Foreman chat should refresh.

## Data Flow

1. `SurfaceView_AppKit` captures snapshots for each terminal.
2. Snapshot creation resolves foreground PID and process name when available.
3. `TerminalUnderstandingEngine` computes:
   - generic terminal state
   - detected agent type
   - inferred agent state
   - whether this update should surface to Foreman
   - suggested next actions
4. `ForemanSidebarStore` records the new understanding for that terminal.
5. If the update should surface, the store marks that terminal as the current subject.
6. Foreman chat refreshes its latest operator-style summary for that subject terminal.

## Safety and Stability Rules

- Do not surface every text refresh.
- Do not let pure noise from another terminal steal the current subject.
- If process-name detection fails, fall back to output heuristics instead of dropping agent understanding.
- If no agent is detected, still provide generic terminal understanding so Foreman remains broadly useful.
- Keep action execution approval-gated through the existing Foreman routing logic.

## Codebase Mapping

- `macos/Sources/Features/AIForeman/TerminalSnapshot.swift`
  - add foreground process metadata to the snapshot model and preview helpers
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
  - populate foreground PID and process-name data during snapshot capture
- `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`
  - add agent identity, agent state, and surfacing metadata
- `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`
  - implement agent detection, agent-state inference, and surfacing rules
- `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
  - track current subject terminal and refresh chat-facing summaries from surfaced updates
- `macos/Sources/Features/AIForeman/ForemanChatView.swift`
  - render terminal-linked chat summaries that clearly identify the active subject terminal

## Testing Strategy

The implementation plan should include targeted tests for:

- snapshot creation carrying PID and process-name metadata
- process-name and output-pattern agent detection
- agent-state inference for running, waiting, error, completed, and idle cases
- surfacing decisions that suppress noisy refreshes and emit on actionable or stable updates
- current-subject selection preferring the newest qualifying terminal update
- chat summaries that include terminal identity and suggested next action

## Risks

| Risk | Mitigation |
|---|---|
| Process lookup is unavailable or unreliable | Fall back to output-pattern detection |
| Over-eager refreshes create chat spam | Use surfacing gates tied to actionable or stable states |
| Subject switching feels random | Use simple recency-based qualifying updates instead of opaque ranking |
| Agent heuristics misclassify normal shell output | Keep generic fallback behavior and constrain agent patterns tightly |
| UI action path differs from chat action path | Reuse existing approval-routing logic and defer UI button repair to the next slice |
