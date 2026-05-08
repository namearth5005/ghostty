# Foreman Reactive Auto-Drive — AI Handoff Document

> **Date:** 2026-05-06
> **Status:** Core implementation complete. Needs polish, testing, and memory integration.
> **Last build:** Succeeds, all tests pass (22 ForemanAgentTests + 8 AgentStateMonitorTests)

---

## What We Built

### Reactive Auto-Drive v2
A one-shot reactive system where the Foreman Agent watches AI agent terminals (Kimi, Claude Code, Codex) and reacts **once** when they transition from working → needing attention.

### Architecture

```
Sidebar Refresh (every 2.0s)
    │
    ▼
┌─────────────────────────────┐
│  TerminalUnderstandingEngine │  ← existing, computes state from wire protocols
│                              │     + screen heuristics for Kimi approval UI
└──────────────┬───────────────┘
               │
               ▼
┌─────────────────────────────┐
│  AgentStateMonitor           │  ← NEW (macos/Sources/Features/AIForeman/)
│                              │     AgentStateMonitor.swift
│  Tracks per-terminal state   │     AgentNeedsAttentionEvent.swift
│  Fires on transitions:       │
│  • .running → .waiting*      │
│  • First detection for       │
│    .waitingApproval/Choice/  │
│    error (URGENT only)       │
│                              │
│  SPAM LOOP FIX: Tracks       │
│  foremanReactedToState —     │
│  skips firing if terminal    │
│  returns to same state after │
│  Foreman acted.              │
└──────────────┬───────────────┘
               │ AgentNeedsAttentionEvent
               ▼
┌─────────────────────────────┐
│  ForemanAgent.react(to:)    │  ← MODIFIED
│                              │
│  One-shot: captures snapshot,│
│  runs ONE LLM iteration,     │
│  executes action, stops.     │
│  No loop. No goal msg.       │
│                              │
│  Action buttons in terminal  │
│  cards (NEW):                │
│  • waitingApproval →         │
│    [Approve] [Reject]        │
│  • waitingChoice → options   │
│  • waitingText → [Reply]     │
│  • error → [Retry]           │
└─────────────────────────────┘
```

---

## Files Created

| File | Purpose |
|------|---------|
| `macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift` | Immutable event fired when AI agent needs attention |
| `macos/Sources/Features/AIForeman/AgentStateMonitor.swift` | Watches terminals, fires events on meaningful transitions |
| `macos/Tests/Terminal/AgentStateMonitorTests.swift` | 8 tests for the monitor |

## Files Modified

| File | What Changed |
|------|-------------|
| `macos/Sources/App/macOS/AppDelegate.swift` | Wires AgentStateMonitor to ForemanAgent.react(to:). On-demand agent creation. |
| `macos/Sources/Features/AIForeman/ForemanAgent.swift` | Added `react(to:captureSnapshots:)` one-shot method. Added action button helpers. |
| `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift` | Added `detectKimiScreenApproval()` heuristic for Kimi shell-command approval UI (wire protocol doesn't emit ApprovalRequest for these). |
| `macos/Sources/Features/AIForeman/TerminalSummaryRow.swift` | Added action buttons (Approve/Reject/Choice options/Reply/Retry) in terminal cards. |
| `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift` | Added `agentContextOptions` to `TerminalSummaryRowModel`. |
| `macos/Sources/Features/AIForeman/AgentInteractionContext.swift` | Added `optionsArray` helper for waitingChoice. |
| `macos/Sources/Features/AIForeman/AnthropicClient.swift` | Updated system prompt: tell LLM not to wrap agent messages in printf/echo, infer context from terminal history. |
| `macos/Sources/Features/AIForeman/OpenAIClient.swift` | Same prompt updates as AnthropicClient. |
| `macos/Tests/Terminal/ForemanAgentTests.swift` | Added tests for react() behavior. |

---

## Current Behavior

### What Works
1. ✅ **First-detection fix**: Kimi welcome screen no longer triggers on startup
2. ✅ **Transition-based firing**: `.running → .waiting*` fires correctly
3. ✅ **Urgent first-detection**: `.waitingApproval/Choice/error` fire on first detection
4. ✅ **Non-urgent first-detection ignored**: `.waitingText` does NOT fire on first detection
5. ✅ **Spam loop fixed**: `foremanReactedToState` prevents re-firing when Foreman causes the state change
6. ✅ **Action buttons in terminal cards**: Approve/Reject/Choice/Reply/Retry buttons render
7. ✅ **Kimi screen approval heuristic**: Detects "Shell is requesting approval to run command" when wire protocol misses it
8. ✅ **All tests pass**: 22 ForemanAgentTests + 8 AgentStateMonitorTests

### What Works But Needs Polish
1. ⚠️ **Prompt context is messy**: The raw terminal dump appears in the sidebar chat conversation. User wants internal evaluation without visible system prompts.
2. ⚠️ **Action buttons are basic**: Approve sends "1" for Kimi, "y" for others. Reject sends "3" for Kimi, "n" for others. This may not match all agent UIs.
3. ⚠️ **Foreman asks user back when context is vague**: If user just says "hello", Foreman asks "What should I send?" instead of inferring.

### Known Issues
1. 🐛 **Visual clutter in sidebar chat**: The context message ("Kimi in terminal X is waiting...") appears as a user-visible message in the conversation thread. User wants this processed internally.
2. 🐛 **Duplicate terminal IDs in messages**: Some messages show short ID (57470C9D) and others show full UUID in the same conversation.
3. 🐛 **Action buttons don't show Foreman's specific suggestion**: When Foreman LLM decides to send a command, the action badge shows in chat but NOT as a clickable button in the terminal card. User wants the terminal card to show the actual suggested action.

---

## What Still Needs To Be Done

### Priority 1: Clean Up Sidebar Chat (UX)
**Problem:** `ForemanAgent.react(to:)` adds the context message directly to `conversation.messages`:
```swift
conversation.addMessage(role: .user, content: contextMessage)
```
This makes the sidebar chat visually noisy.

**Solution options:**
- **Option A:** Don't add context to conversation.messages. Pass it directly to the LLM as part of the prompt, and only show the agent's decision in chat.
- **Option B:** Add context as a system message or hidden message that doesn't render in UI.
- **Option C:** Collapsible raw context — show brief summary with expand/collapse for full terminal output.

**User preference:** Internal processing (Option A) — the AI should read state internally and show only clean suggestions.

### Priority 2: Terminal Card Shows Foreman's Actual Suggestion
**Problem:** The action buttons in `TerminalSummaryRow` are generic (always [Approve] [Reject]). The user wants the terminal card to show the **specific action the Foreman LLM decided**, just like the chat does.

**Solution:** When `ForemanAgent.react(to:)` generates an action in interactive mode, store the pending action somewhere accessible to `ForemanSidebarStore`. Then `TerminalSummaryRow` can display it as a button.

**Implementation sketch:**
```swift
// In ForemanSidebarStore
var pendingForemanActions: [String: AgentAction] = [:]

// In ForemanAgent.handleSendCommand (interactive mode)
await MainActor.run {
    store.pendingForemanActions[terminalID] = action
}

// In TerminalSummaryRow
if let pendingAction = row.pendingForemanAction {
    ActionButton(title: pendingAction.title, command: pendingAction.command)
}
```

### Priority 3: Memory / Context Awareness
**Problem:** Each reactive trigger is isolated. The LLM has no memory of previous interactions in the same project.

**Research done:** Agent swarm produced a full design doc at:
`docs/superpowers/plans/foreman-memory-integration.md`

**Key finding:** `ForemanMemoryStore` (SQLite + FTS5) already exists and stores data, but **no code reads from it**.

**Quick win:** Add a `Relevant past context from this project:` section to the LLM prompt by querying `ForemanMemoryStore` for past outcomes.

### Priority 4: Approval UI State Not Showing Correctly
**Problem:** When Foreman sets `status = .waitingForUser` in interactive mode, the sidebar bottom input area sometimes shows "What should I do?" (readyToStart) instead of the approval buttons (Skip/Run).

**Likely cause:** The `ConversationUIPhase.resolve()` logic may not correctly detect `.waitingForUser` status when there are existing messages in the conversation.

---

## Testing

### Run tests
```bash
# AgentStateMonitor tests
cd /Users/nambouchara/speed2/ghostty && xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/AgentStateMonitorTests

# ForemanAgent tests
cd /Users/nambouchara/speed2/ghostty && xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests

# Build
cd /Users/nambouchara/speed2/ghostty && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug
```

### Manual test checklist
1. Open Kimi → Foreman should NOT trigger (first detection of .waitingText is ignored)
2. Type "hello" in Kimi → Kimi processes → returns to waiting → Foreman should trigger
3. Foreman should suggest something (or ask what to send if context is vague)
4. Approve prompt in Kimi → Foreman should show [Approve] [Reject] buttons in terminal card
5. Click [Approve] → should send approval to Kimi
6. Foreman should NOT spam loop (only reacts once)

---

## Architecture Notes

### Why `AgentStateMonitor` is separate from `ForemanAgent`
The monitor is `@MainActor` and runs on every sidebar refresh (2s). The agent is an `actor` that runs LLM calls asynchronously. Separation prevents the refresh timer from blocking on LLM latency.

### Why `react(to:)` doesn't call `conversation.start()`
`start()` resets iteration count and appends a goal message. `react()` is meant to be a lightweight reaction that piggybacks on the existing conversation. It adds one context message, runs one step, and stops.

### Kimi wire protocol specifics
- `TurnBegin` → `.running`
- `StepBegin` → `.running`
- `TurnEnd` → `.waitingText`
- `ApprovalRequest` → `.waitingApproval`
- `QuestionRequest` → `.waitingChoice` or `.waitingText`
- **BUG:** Kimi does NOT emit `ApprovalRequest` for shell-command approvals (the `find` / `ls` approval UI). The screen heuristic `detectKimiScreenApproval()` catches this.

---

## Design Docs

| Doc | Location |
|-----|----------|
| Reactive Auto-Drive v2 Design Spec | `docs/superpowers/specs/2025-05-05-ai-agent-reactive-auto-drive-design.md` |
| Memory Integration Plan (9 tasks) | `docs/superpowers/plans/foreman-memory-integration.md` |
| This handoff doc | `docs/superpowers/plans/2026-05-06-reactive-auto-drive-handoff.md` |

---

## Build & Launch

```bash
# Build
cd /Users/nambouchara/speed2/ghostty && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug

# Launch
open /Users/nambouchara/Library/Developer/Xcode/DerivedData/Ghostty-gbgqgpplpmuptgbhinobncpfzleh/Build/Products/Debug/Foreman.app

# Debug log
tail -f /tmp/foreman.log
```

---

## Context for Next AI

The user explicitly wants:
1. **AI-agent-only reactive behavior** — shell terminals completely ignored ✅
2. **No visual clutter** — context messages should be processed internally, not dumped in chat ❌ (needs work)
3. **Smart suggestions** — Foreman should infer context from terminal history, not ask user back constantly ⚠️ (prompt updated, needs memory)
4. **Action buttons in terminal cards** — user should be able to click [Approve] in the sidebar terminal card ✅ (basic version done)
5. **No spam loops** — react once per event, not continuously ✅

The user is pragmatic — they want functional improvements over perfect architecture. Test everything manually before claiming it's done.
