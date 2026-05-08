# AI Agent Reactive Auto-Drive — Design Spec

**Date:** 2025-05-05  
**Status:** Approved for implementation  
**Approach:** One-Shot Event Reaction (Approach A)

---

## Problem Statement

The current reactive auto-drive feature spams the user because:
1. **Idle shell prompts are classified as `.waiting`** — any terminal with a `$` or `%` prompt triggers the agent
2. **Race conditions** — multiple Tasks fire per refresh cycle, starting competing agents
3. **Conversation message duplication** — every trigger appends a new goal message without clearing history
4. **Infinite restart loop** — the agent stops after `respond`, then the next refresh starts a new one

## Goal

When an AI agent (Kimi, Claude Code, Codex) transitions from **working** → **needs input/approval**, the Foreman AI reacts **once** with the terminal's context, decides what to do, acts (autonomous) or shows a button (interactive), and **stops**.

Shell terminals and idle prompts are completely ignored.

---

## Architecture

```
Sidebar Refresh (every 1.5s)
    │
    ▼
┌─────────────────────────────┐
│  TerminalUnderstandingEngine │
│  (existing)                  │
│                              │
│  Computes understandings     │
│  for ALL terminals           │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│  AgentStateMonitor           │
│  (NEW — @MainActor)          │
│                              │
│  Watches ONLY terminals      │
│  where agentIdentity != .none│
│                              │
│  Tracks previous             │
│  agentInteractionState per   │
│  terminal                    │
│                              │
│  Fires on transitions:       │
│  .running → .waitingApproval │
│  .running → .waitingChoice   │
│  .running → .waitingText     │
│  .running → .error           │
│                              │
│  Ignores:                    │
│  • Shell terminals           │
│  • Same-state transitions    │
│  • .idle, .noisyHealthy      │
└──────────────┬──────────────┘
               │ AgentNeedsAttentionEvent
               ▼
┌─────────────────────────────┐
│  ForemanAgent                │
│  .react(to: event)           │
│  (MODIFIED — one-shot)       │
│                              │
│  1. Capture snapshot of      │
│     triggering terminal      │
│  2. Build focused prompt:    │
│     "Kimi needs approval.    │
│      Output: [delta]"        │
│  3. Call LLM (ONE step)      │
│  4. Execute action           │
│  5. STOP                     │
│                              │
│  No loop. No goal message.   │
│  No conversation reset.      │
└─────────────────────────────┘
```

---

## Components

### 1. AgentNeedsAttentionEvent

Immutable struct carrying everything the agent needs for its one-shot reaction.

```swift
struct AgentNeedsAttentionEvent: Sendable {
    let terminalID: String
    let agentIdentity: AgentIdentity
    let interactionState: AgentInteractionState
    let deltaText: String
    let timestamp: Date
}
```

### 2. AgentStateMonitor

`@MainActor` class that observes terminal understandings and fires events.

**State:**
```swift
private var previousAgentStateByTerminalID: [String: AgentInteractionState] = [:]
private var lastEventByTerminalID: [String: Date] = [:]
private let cooldownSeconds: TimeInterval = 5
```

**Behavior:**
1. Receives `[TerminalUnderstanding]` from sidebar refresh
2. Filters to `agentIdentity != .none`
3. For each AI terminal:
   - `previous = previousAgentStateByTerminalID[id]`
   - `current = understanding.agentInteractionState`
   - If `previous == .running` and `current ∈ {.waitingApproval, .waitingChoice, .waitingText, .error}`:
     - Check cooldown: `lastEventByTerminalID[id]` must be nil or > 5s ago
     - If cooldown elapsed, fire `AgentNeedsAttentionEvent`
     - Update `lastEventByTerminalID[id] = now`
   - Update `previousAgentStateByTerminalID[id] = current`
4. When a terminal leaves the watched set (closed), remove its entries

**Cooldown logic:** Prevents duplicate events if the agent responds with `declareComplete` or `respond` and the terminal is still in the same waiting state on the next refresh.

### 3. ForemanAgent.react(to:)

Replaces `startReactive()`. Runs exactly one iteration.

```swift
func react(to event: AgentNeedsAttentionEvent) async {
    // 1. Add contextual message to conversation (no reset, no goal)
    await MainActor.run {
        conversation.addMessage(role: .user, content: makeContextMessage(for: event))
    }
    
    // 2. Capture snapshot of triggering terminal
    let snapshot = await captureTriggeringSnapshot(event.terminalID)
    
    // 3. One LLM step
    let response = try await foremanService.agentStep(...)
    
    // 4. Execute action
    await executeAction(response)
    
    // 5. Done — no loop, no re-entry
}
```

**No `conversation.start()`** — we don't reset iteration count, don't clear messages, don't append a goal message. The conversation state persists across reactions.

### 4. AppDelegate Wiring

**Removes:**
- `maybeStartReactiveAgent`
- `reactiveLastHandledTime`
- `reactiveCooldownSeconds`
- `isStartingReactiveAgent`
- `ForemanAgent.startReactive()`
- The `Task { }` in `refreshAIForemanSidebar`

**Adds:**
```swift
private let agentStateMonitor = AgentStateMonitor()

// In applicationDidFinishLaunching or similar:
agentStateMonitor.onEvent = { [weak self] event in
    Task { await self?.foremanAgent?.react(to: event) }
}

// In refreshAIForemanSidebar:
agentStateMonitor.observe(understandings: understandings)
```

---

## State Transition Reference

### Kimi

| Previous State | Current State | Event Fired? | Notes |
|---|---|---|---|
| `.running` | `.waitingApproval` | ✅ Yes | "Approve edit to auth.ts?" |
| `.running` | `.waitingChoice` | ✅ Yes | "Choose an option:" |
| `.running` | `.waitingText` | ✅ Yes | "What would you like to do?" |
| `.running` | `.error` | ✅ Yes | Error occurred |
| `.running` | `.completed` | ❌ No | Kimi finished normally |
| `.waitingApproval` | `.running` | ❌ No | User already acted |
| `.waitingText` | `.running` | ❌ No | User already replied |
| `.waitingApproval` | `.waitingApproval` | ❌ No | Same state, cooldown active |

### Claude Code / Codex

Same transition table. Wire protocols provide 0.98 confidence on state detection.

### Shell Terminals

Ignored entirely. `agentIdentity == .none` → never watched.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| LLM call fails | Log error, add message to conversation, stop. Don't retry immediately. |
| Send command fails | Log error, add message, stop. |
| Agent already reacting to another event | Queue the event or drop it (TBD — see open question). |
| Terminal closes while agent is reacting | Agent captures snapshot, terminal missing → LLM sees no terminal → likely `declareStuck` or `respond`. |

---

## Testing Strategy

1. **Unit test:** `AgentStateMonitor` fires event on `.running → .waitingApproval`, ignores shell terminals, respects cooldown.
2. **Unit test:** `AgentStateMonitor` does NOT fire on `.waitingApproval → .waitingApproval` (same state).
3. **Unit test:** `ForemanAgent.react(to:)` runs exactly one iteration and stops.
4. **Unit test:** `ForemanAgent.react(to:)` does not call `conversation.start()` or duplicate messages.
5. **Integration test:** Full flow — Kimi wire record says `waitingApproval` → monitor fires → agent sends `yes` in autonomous mode.

---

## Open Questions

1. **Event queuing:** If two terminals need attention simultaneously, should the agent queue them or handle only one? Recommendation: handle one at a time, queue the second.
2. **Conversation persistence:** Should reactions accumulate in the same conversation thread, or start a fresh thread per event? Recommendation: same thread — the user sees a continuous log of what the Foreman did.
3. **Mode per event:** Should the user be able to override mode (interactive/autonomous) per event? Recommendation: no, use the global mode from the sidebar.

---

## Migration Plan

1. Create `AgentNeedsAttentionEvent` and `AgentStateMonitor`
2. Add `ForemanAgent.react(to:)`
3. Wire up `AppDelegate`
4. Remove all current reactive trigger code
5. Remove `ForemanAgent.startReactive()`
6. Add tests
7. Build and verify
