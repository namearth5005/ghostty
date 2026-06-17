# AI Foreman — Handoff Prompt (continue from here)

Date: 2026-06-17
Branch: `claude/ghostly-app-viability-32ketc`
Status: strategy decided, foundational rebuild scoped, **not yet started**.

You are picking up the **AI Foreman** feature in this Ghostty fork. Read this
whole file before touching code. It is written to be self-contained — you should
not need the prior chat session.

---

## TL;DR (the decision)

- The differentiated, worth-building product is **multi-terminal "mission
  control"**: a passive monitor that honestly tells the user the true state of
  every pane they have open in a tab while they multitask (idle / running /
  done / failed / waiting-for-input), and pings them when a *backgrounded* pane
  changes state.
- The **agent-that-runs-commands half is deprioritized**. "An AI agent that
  sends commands in your terminal" is the most saturated space in software
  (Claude Code, Codex, Cursor, Warp Agent Mode, Aider). Foreman's `ForemanAgent`
  loop is a competent version of a commodity. Do **not** invest more there for
  now. Keep it, but it is the cherry, not the cake.
- **The whole product lives or dies on one thing: trustworthy per-pane state
  detection.** That is currently the weakest part of the code. Fixing it is the
  job.

### Why this is the moat (and why it stays in the terminal)

Being *inside the emulator* is the one place you can read true command
boundaries + exit codes + process liveness. An external CLI agent or a
tmux+LLM wrapper **cannot** get exit codes and command boundaries cleanly —
they are stuck doing the same flaky scrollback regex Foreman does today. So the
defensible product is: *"a monitor that knows the real state of every pane
because it reads the terminal's own semantic signals."*

(Caveat, stay honest: this is a **fork**. Upstream Ghostty forbids this work —
see `AI_POLICY.md` and `AGENTS.md` ("Never create a PR"). Distribution is an
unsolved problem. For now the goal is a **dogfoodable build the owner uses
themselves**, not a release. Do not open PRs/issues against upstream.)

---

## The core finding

Foreman decides each pane's state with **text regex over scrollback** in
`macos/Sources/Features/AIForeman/TerminalSnapshot.swift`. Three of the four
signals are unreliable, and the most valuable one is **inverted**:

1. **`isLikelyWaitingForInput` (line ~199) is backwards.** It returns `true`
   when the last visible line ends in a shell prompt char (`$ % # > ❯ ➜ →`).
   That is an **idle shell at a ready prompt** — the opposite of "blocked
   waiting for me." And it **misses the states that actually matter**:
   `Proceed? [y/N]`, `Password:`, `Overwrite? (y/n)` — none end in those chars.
   This is the single most important signal for the product (a backgrounded
   pane blocked on a confirm/password) and it is detected wrong.

2. **`isLikelyErrorState` (line ~206) has huge false positives.** Substring
   match on `"error"`, `"fail"`, `"cannot"`, `"not found"`, etc. anywhere in the
   text fires on `npm WARN`, a filename in `ls`, a test named "should fail
   when…", `git log` messages, help text. It will mark many idle panes as
   "blocked," destroying trust.

3. **`isLikelyLongRunning` (line ~172) never clears.** Substring match on
   `"npm "`, `"running"`, `"cargo "`, etc. A *finished* `npm install` still
   reads as "running" forever because it keys off leftover text, not whether
   anything is actually executing.

4. **`isLikelyTUI` (line ~157) is the only solid one** — and notice *why*: it
   checks the real alt-screen escape `\e[?1049h`, i.e. a true terminal signal,
   not a word guess. This is the model to follow.

Meanwhile the emulator already tracks the ground truth and Foreman **ignores it
entirely** (grep Foreman for `133`, `semantic`, `exitCode`, `shellIntegration`
→ zero hits beyond SwiftUI `.foregroundStyle` colors).

---

## What the emulator already knows (and the bridge gap)

**Parsed and available in core:**
- **OSC 133 semantic prompts** — `src/terminal/osc/parsers/semantic_prompt.zig`;
  every row carries `row.semantic_prompt` (see `src/terminal/PageList.zig`,
  `src/terminal/page.zig`). This marks prompt-start / command-start /
  command-output / command-end, i.e. true command boundaries.
- **Exit codes** ride on OSC 133 command-end (`D;<exit>`). This gives
  success/failure as a **fact**, no regex.
- These are exposed in the **libghostty-vt** C API:
  `include/ghostty/vt/screen.h` (see the `semantic_content` / `semantic_prompt`
  docs around lines 100, 186, 211, 278).

**Already exposed to the macOS app, usable right now:**
- `ghostty_surface_process_exited(surface)` — `src/apprt/embedded.zig` (~line
  1598), and it is **already called** in Swift
  (`macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` ~line 139).
  This tells you the surface's child (the shell) has exited — i.e. the session
  ended. Note: for a normal shell pane this does NOT fire between commands
  (the shell process stays alive), so it is *not* per-command granularity.

**The gap (this is the real foundational task):**
- The macOS app reads pane text via `ghostty_surface_read_text` /
  `ghostty_surface_free_text` (`src/apprt/embedded.zig` ~line 1629; consumed in
  `SurfaceView_AppKit.swift` via `cachedVisibleContents`, ~lines 205/240/2226).
  **This returns plain text only — no semantic prompt state, no exit code.**
- So OSC 133 boundaries + exit codes exist in core but are **not bridged**
  through the embedded surface API the macOS app uses. Closing that bridge is
  the highest-leverage piece of work.

---

## The plan (phased — ship trust before intelligence)

### Phase 0 — pure-Swift trust fixes (no Zig, do this first)
Goal: stop lying to the user with what's already reachable.
- **Fix the `isLikelyWaitingForInput` inversion.** Distinguish an *idle ready
  prompt* from a *blocking prompt*. Detect blocking by question/affordance
  patterns on the last non-empty line: `[y/n]`, `(yes/no)`, trailing `?`,
  `password:`, `passphrase:`, `continue?`, `overwrite?`, `[Y/n]`/`[y/N]`,
  `Press any key`, etc. An idle shell prompt is a *separate* state (`idle`),
  not `waiting`.
- **Tighten `isLikelyErrorState`.** Restrict to last-N lines, require stronger
  markers (`^error:`, `fatal:`, `panic:`, `Traceback (most recent call last)`,
  non-zero "exit code"/"exited with"), exclude obvious noise (`warn`, `--help`,
  matches inside paths). Better: defer this signal to Phase 1 (exit code) and
  keep only high-precision markers now.
- **Make `isLikelyLongRunning` decay.** It must clear. Until Phase 1, at least
  require the long-running token to be in the *most recent* lines, and treat a
  fresh prompt line appearing after it as "done."
- Add/adjust unit tests in `macos/Tests/Terminal/` for each (there are existing
  Foreman test files there — match their style).

This phase alone is dogfoodable and meaningfully more honest.

### Phase 1 — bridge the ground truth (the real unlock)
- Add an embedding C API in `src/apprt/embedded.zig` (mirror the shape of
  `ghostty_surface_read_text`) that returns, for the focused/last command
  region: the OSC 133 prompt/command/output boundaries and the **last command's
  exit code**, plus whether the cursor is currently in an input region.
  Suggested name: `ghostty_surface_read_semantic_state`. Walk
  `row.semantic_prompt` over the active screen rows.
- Declare it in the macOS bridging header and consume it in
  `SurfaceView_AppKit.swift` as new `terminalSnapshot…` properties on the
  `TerminalSnapshotSource` protocol (`TerminalController.swift` ~line 1610).
- Rewrite the four signals in `TerminalSnapshot.swift` to prefer semantic data
  and fall back to the Phase-0 heuristics only when OSC 133 is absent (user has
  no shell integration). Degrade gracefully — never regress when data is
  missing.
- Use `ghostty_surface_process_exited` to mark a pane `session ended`.

### Phase 2 — the honest sidebar + one notification
- Sidebar shows, per pane, the true state: `idle` · `running 0:12` · `✅ done`
  · `❌ failed (exit 1)` · `⛔ waiting for input` · `session ended`.
  (`ForemanSidebarStore.snapshotState`, ~line 317, is where state→label lives.)
- Fire **one** local notification when a **backgrounded** (non-focused) pane
  transitions to `failed` or `waiting for input`. `ForemanNotifier.swift`
  already exists — wire it to real transitions, respect focus/DND.
- **No LLM, no dispatch, no autonomous mode in this milestone.**

### The test (do not skip)
Dogfood it: the owner runs this build for ~a week across their normal split
panes. If an accurate, AI-free monitor doesn't earn its keep in daily use,
nothing stacked on top would have. Only after it does should the AI layer
(summaries, cross-pane context graph, dispatch) get built back up.

---

## Start here (first task)
Phase 0, bug #1: fix the `isLikelyWaitingForInput` inversion in
`macos/Sources/Features/AIForeman/TerminalSnapshot.swift` and add tests. It is
the bug that most undermines trust and it needs no Zig. Land it green, then
continue down Phase 0.

---

## File map
- `macos/Sources/Features/AIForeman/TerminalSnapshot.swift` — the signals (the
  heart of the rebuild).
- `macos/Sources/Features/AIForeman/TerminalContentAnalyzer.swift` — text→summary.
- `macos/Sources/Features/AIForeman/TerminalOutcomeEngine.swift` — post-send
  outcome monitoring (consumes signals).
- `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift` — state→UI model;
  `snapshotState` maps signals to labels (~line 317).
- `macos/Sources/Features/AIForeman/ForemanSidebarView.swift` — the sidebar UI.
- `macos/Sources/Features/AIForeman/ForemanNotifier.swift` — notifications.
- `macos/Sources/Features/AIForeman/ForemanAgent.swift` / `ForemanService.swift`
  / `AnthropicClient.swift` / `OpenAIClient.swift` — the (deprioritized) agent.
- `macos/Sources/Features/Terminal/TerminalController.swift` — snapshot capture
  (`captureTerminalSnapshots`, `TerminalSnapshotSource`, ~line 1610+).
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — libghostty
  text bridge (`cachedVisibleContents`, `ghostty_surface_process_exited`).
- `src/apprt/embedded.zig` — the C embedding API (where the semantic bridge goes).
- `src/terminal/osc/parsers/semantic_prompt.zig`, `include/ghostty/vt/screen.h`
  — OSC 133 source of truth.
- `macos/Tests/Terminal/Foreman*Tests.swift` — existing Foreman tests.
- `FOREMAN_ROADMAP.md` — the original (more ambitious) roadmap; treat as
  aspirational, not the current plan.

## Build / test / constraints (from `AGENTS.md`)
- Build (skip macOS app bundle for fast Zig iteration):
  `zig build -Demit-macos-app=false`
- Zig tests (targeted): `zig build test -Dtest-filter=<name>`
- Swift format: `swiftlint lint --strict --fix`
- Zig format: `zig fmt .`
- The macOS app itself builds via Xcode/the macOS target; Foreman is Swift in
  `macos/`. Run the Foreman unit tests after every change.
- **Constraints:** never open a PR or issue against upstream; this is a private
  fork. Develop on `claude/ghostly-app-viability-32ketc`. Disclose AI usage per
  `AI_POLICY.md` if anything ever goes outward.

## Open questions to resolve as you go
1. Does `ghostty_surface_read_text` already have access to per-row
   `semantic_prompt` internally, or does the new API need to reach into the
   screen/pagelist? (Check `src/apprt/embedded.zig` around the read_text impl.)
2. How is the **last command's exit code** retained after the prompt returns —
   is it queryable from the screen state, or must it be captured at the OSC 133
   `D` event and cached per surface? May need a small cache in the surface.
3. Foreground process name (what's actually running: `vim` vs `npm`) — is there
   an existing libghostty accessor, or is `process_exited` the only process
   signal exposed today? Nice-to-have for richer state, not required for v1.
4. Does the owner run a shell with OSC 133 shell integration enabled? If not,
   Phase 1 silently falls back to Phase 0 heuristics — confirm the degrade path.

## Definition of done (first milestone = Phase 0 + 2, heuristic-only)
- All four signals reworked; `waiting` means *blocked on input*, not idle.
- Sidebar shows honest per-pane state with the new labels.
- One notification fires on a backgrounded pane going `failed`/`waiting`.
- Foreman unit tests green; app builds and launches.
- Owner can dogfood it across real split panes.
</content>
</invoke>
