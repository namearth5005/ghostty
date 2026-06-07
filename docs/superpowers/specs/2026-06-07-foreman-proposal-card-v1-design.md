# Foreman Proposal Card — v1 Design

**Date:** 2026-06-07
**Status:** Approved design, ready for implementation planning

---

## The idea, in one line

> A **personal assistant for your AI agents.** You're doing something else (gaming, other work). When an agent in a terminal needs you, the Foreman sends you a short message — *"here's what's happening, here's what I'd do"* — and you just tap **Yes**.

That is the entire v1 product. One interaction: approve a proposal.

```
   📱  Foreman
   "Kimi finished and wants to push the code.
    Tests passed, looks fine. Want me to let it?"

        [ 👍 Yes ]   [ 👎 No ]   [ ✎ Edit ]
```

## Why we're doing it this way

The current sidebar fused two different things into one surface: a **chatbot** you converse with and **per-terminal AI suggestions** you click. They were forced through one input box whose meaning silently changed ("Guiding Foreman" vs "Replying to term-2"), which is the disconnection the product feels today.

The approve-a-proposal model dissolves that ambiguity: the unit of interaction becomes a **proposal card about a specific terminal**, not an ambiguous chat line. You almost never type free text — you approve.

### Two helpers, clear division of labor

- **The watcher** — dumb, cheap, always on. Rules + parsing (no LLM). Detects *when* a terminal needs attention. Reliable because it mostly mirrors the agent's own output.
- **The Foreman** — smart, paid, occasional. A real LLM. Turns "needs attention" into a plain-English **summary + one suggested action**.
- **You** — the approver. Yes / No / Edit.

## Build approach: fresh shell, lift the engine

An audit confirmed every valuable "engine" file is a **clean leaf** — zero dependency on the store, agent, views, or AppDelegate. So we keep the engine and rebuild only the tangled shell on top of it.

Because it is all **one build target**, "lifting" means *referencing* the existing leaf files from a new shell — no copying. We delete the old shell once the new one works.

```
KEEP & REFERENCE (unchanged):
  OpenAIClient, AnthropicClient                      (LLM plumbing)
  Codex/Claude/Kimi SessionMonitors + WireTypes      (wire taps)
  AgentRawRuntimeDetector, AgentScreenInteractionDetector,
  AgentMeaningDetector, AgentIdentityDetector, AgentRuntimeDetector,
  AgentInteractionContext(+Resolver)                 (detection — ~100 edge cases)
  TerminalSnapshot, TerminalScreenText               (capture)
  ForemanNotifier                                    (macOS notifications)
  Pure model types (AgentAction, AgentInteractionState, …)
  Likely reusable (verify at plan time):
  ForemanMemoryStore, ForemanProjectScope, ManagedAgentRegistry

BUILD NEW (small):
  TerminalProposal      (the unit)
  TerminalWatcher       (wraps lifted detectors → "needs attention")
  ForemanProposer       (wraps lifted LLM client → summary + 1 action)
  ProposalStore + ProposalCardView  (hold + render the card; send on Yes)

DELETE once the new shell works:
  ForemanSidebarStore, ForemanAgent, ForemanSidebarRouting,
  ForemanChatView, ForemanSidebarView
```

### The one discipline rule

**Copy/reference the leaf logic verbatim. Do NOT "clean it up" while moving it.** The ugliness in the detectors *is* the accumulated edge-case knowledge. Refactor later, in place, with its tests. Rewriting it "nicer" mid-move is how the months of fixes get re-lost.

### The one real cost

The **Ghostty integration glue** — how the snapshot pulls live terminal text, how the panel mounts in `TerminalView`, how events flow from `AppDelegate` — is coupled to Ghostty and must be re-wired. It is a small, well-understood surface; copy the existing hook points.

## Components (the whole fresh shell)

| Component | Responsibility | Depends on |
|---|---|---|
| `TerminalProposal` | The unit: `{ terminalID, fingerprint, summary, suggestion(title, payload/command), kind }` | models only |
| `TerminalWatcher` | Run lifted detectors/monitors on snapshots; emit "needs attention" for states `{waitingText, waitingApproval, waitingChoice, error, completed}` | lifted detectors, snapshot |
| `ForemanProposer` | Given snapshot + detected state, ask the lifted LLM client for summary + one action; fall back to the agent's parsed menu when the LLM is unavailable | lifted LLM client, detectors |
| `ProposalStore` | Hold current proposal; expose approve / reject / edit; call the terminal send path on Yes | `TerminalProposal`, terminal send path (integration glue) |
| `ProposalCardView` | Render summary + suggested action + `[Yes] [No] [Edit]` | `ProposalStore` |

## Data flow

```
terminal output changes
  → TerminalSnapshot (lifted)
  → TerminalWatcher runs detectors (lifted) ── needs attention? ──┐
                                                                  │ yes
  → ForemanProposer asks LLM: summary + 1 suggested action  ◄─────┘
  → ProposalStore.current = TerminalProposal
       ├─► ProposalCardView shows the card
       └─► ForemanNotifier fires a macOS notification (if app unfocused)
  → user taps:  Yes  → send payload to terminal (terminal send path / integration glue)
                No   → clear proposal
                Edit → tweak text → send
  → next snapshot: if the terminal moved on, clear the card
```

Mode: **interactive** ("suggest everything first"). The existing `autonomous` mode is left intact for later but is not part of v1.

## Error handling / graceful degradation

- **LLM down or no API key** → the card still appears via the *dumb-but-honest* path: show the detected state plus the agent's own parsed options as the buttons. The watcher is reliable without the LLM, so the product still functions, just without the friendly summary.
- **Stale proposal** (terminal changed before the user taps) → guard with the `attentionFingerprint` the engine already produces. If the fingerprint changed, the card refreshes instead of sending to the wrong state. No misfires.
- **Send failure** → surface a short inline error on the card; keep the proposal so the user can retry.

## Testing

- `ProposalStore`: approve / reject / edit transitions; stale-fingerprint guard blocks a send to a changed state.
- `ForemanProposer`: produces a proposal from a snapshot using a fake LLM client; falls back to the parsed-menu proposal when the LLM call fails.
- `TerminalWatcher`: emits attention only for the right states (reuses existing detector test fixtures).
- The lifted engine keeps all of its current tests unchanged.

## Out of scope for v1 (deferred, not deleted)

- Multi-terminal overview / project cards
- Project goals and goal-completion checkpoints
- Autonomous mode behavior
- The chat surface (no free-text conversation in v1 — just the card)
- Channels / explicit target switching

The engine already supports these; they can be layered back on once the single-terminal approve loop feels right.

## Success criteria

1. With an agent running in one terminal, when it stops for input/approval/error/completion, a proposal card appears with a plain summary and one suggested action.
2. Tapping **Yes** sends the right thing to that terminal; **No** dismisses without sending; **Edit** lets the user adjust before sending.
3. When the app is unfocused, the same proposal arrives as a macOS notification.
4. With no API key / LLM failure, the card still appears using the agent's own parsed options.
5. The old shell files (`ForemanSidebarStore`, `ForemanAgent`, `ForemanSidebarRouting`, `ForemanChatView`, `ForemanSidebarView`) are deleted, and the app builds and runs on the new shell.
