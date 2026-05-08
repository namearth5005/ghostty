# Foreman Agent Adapter Handoff

Date: 2026-05-04
Repo: `/Users/nambouchara/speed2/ghostty`
Branch: `main`

## Purpose

This document is a handoff for the next AI agent continuing the Foreman work. It explains:

- the architectural direction
- what has already been implemented on `main`
- what is intentionally still incomplete
- which files matter
- what to verify before extending the system

The current slice is the first real transition from a generic terminal-summary engine to an agent-aware Foreman architecture.

## Target Architecture

The intended architecture is a three-layer system:

1. Terminal/runtime facts
- deterministic signals only
- foreground process metadata
- semantic prompt/input state
- alternate-screen / TUI posture
- visible screen snapshot

2. Agent adapter layer
- per-agent classification
- normalize into shared states
- use structured side channels when available
- fall back to screen heuristics only when necessary

3. Foreman orchestration
- summarize only after state is established
- suggest next actions
- eventually support managed launch + one-time setup for supported agents

The key principle is:

- terminal core decides posture
- adapters decide meaning
- Foreman decides what to tell the user or do next

## What Was Implemented

### 1. Runtime prompt signal from Ghostty core

Ghostty semantic prompt state is now exported from the embedded layer into Swift and used by Foreman snapshots.

Files changed:

- [include/ghostty.h](/Users/nambouchara/speed2/ghostty/include/ghostty.h)
- [src/apprt/embedded.zig](/Users/nambouchara/speed2/ghostty/src/apprt/embedded.zig)
- [macos/Sources/Ghostty/Ghostty.Surface.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Ghostty/Ghostty.Surface.swift)
- [macos/Sources/Features/Terminal/TerminalController.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/Terminal/TerminalController.swift)
- [macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift)
- [macos/Sources/Features/AIForeman/TerminalSnapshot.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/TerminalSnapshot.swift)

Implemented behavior:

- exported `ghostty_surface_cursor_is_at_prompt(...)`
- exposed `Surface.cursorIsAtPrompt`
- snapshot source now includes:
  - `foregroundProcessID`
  - `foregroundProcessName`
  - `cursorIsAtPrompt`
  - `usingAlternateScreen`
- `TerminalSnapshot.Signals.likelyWaitingForInput` now prefers semantic prompt state when available

### 2. Richer understanding model

The old understanding model only had generic terminal state. It now includes agent-specific dimensions.

File changed:

- [macos/Sources/Features/AIForeman/TerminalUnderstanding.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/TerminalUnderstanding.swift)

Added:

- `AgentIdentity`
  - `none`
  - `claude_code`
  - `codex`
  - `kimi`
  - `unknown`
- `AgentInteractionState`
  - `unknown`
  - `running`
  - `waiting_approval`
  - `waiting_choice`
  - `waiting_text`
  - `completed`
  - `error`
- `AgentSupportLevel`
  - `generic_fallback`
  - `first_class`
- `UnderstandingEvidence`
  - source
  - detail
  - confidence

`TerminalUnderstanding` now carries:

- `agentIdentity`
- `agentInteractionState`
- `supportLevel`
- `evidence`

### 3. Adapter-driven understanding engine

The old engine was one generic heuristic file. It has been replaced with an adapter coordinator.

File changed:

- [macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift)

Implemented adapters:

- `ClaudeCodeTerminalAdapter`
- `CodexTerminalAdapter`
- `KimiTerminalAdapter`

Current adapter behavior:

- detect agent from:
  - foreground process name
  - title
  - visible text
  - last input preview
- classify into:
  - `waiting_choice`
  - `waiting_approval`
  - `waiting_text`
  - `running`
  - `error`
  - `completed`

Important:

- this is still heuristic-driven
- no structured Claude hooks
- no Codex JSON ingestion
- no Kimi wire/ACP ingestion

This is a scaffolded adapter layer, not the final side-channel integration.

### 4. Sidebar metadata surfacing

The terminal row model and UI now surface agent metadata from understandings.

Files changed:

- [macos/Sources/Features/AIForeman/ForemanSidebarStore.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/ForemanSidebarStore.swift)
- [macos/Sources/Features/AIForeman/TerminalSummaryRow.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/TerminalSummaryRow.swift)

`TerminalSummaryRowModel` now includes:

- `agentIdentity`
- `agentInteractionState`
- `supportLevel`
- `evidenceSummary`

The row UI renders that metadata under the summary line.

### 5. Managed agent scaffolding

The codebase now has first-class definitions for managed agents and an internal launch entry point.

Files changed:

- [macos/Sources/Features/AIForeman/ManagedAgentRegistry.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/ManagedAgentRegistry.swift)
- [macos/Sources/App/macOS/AppDelegate.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/App/macOS/AppDelegate.swift)

Implemented:

- `ManagedAgentDefinition`
- `ManagedAgentSetupRequirement`
- `ManagedAgentSetupStatus`
- `ManagedAgentLaunchRequest`
- `ManagedAgentRegistry`
- `AppDelegate.launchManagedAgent(_:)`

Current supported registry entries:

- `Claude Code`
  - executable: `claude`
  - setup requirement: `claude_hooks`
  - environment includes `CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1`
- `Codex`
  - executable: `codex`
  - no extra setup yet
- `Kimi`
  - executable: `kimi`
  - no extra setup yet

Important:

- there is no UI for managed launch yet
- there is no setup flow yet
- this is backend scaffolding only

## What Was Not Implemented Yet

These remain open:

### Structured side channels

Not implemented yet:

- Claude hooks ingestion
- Claude session-state event ingestion
- Claude stream-json ingestion
- Codex `exec --json` ingestion
- Kimi `--wire` ingestion
- Kimi ACP ingestion

The adapters currently classify from runtime + screen heuristics only.

### One-time setup UI

Not implemented yet:

- user-facing “Enable enhanced support” flow
- patching `~/.claude/settings.json`
- validating agent installation
- surfacing readiness states in the sidebar/chat UI

### Managed launch UI

Not implemented yet:

- a button or command in Foreman to launch Claude/Codex/Kimi
- any chat command that routes into `launchManagedAgent(_:)`

### Rich chat/orchestration behavior from adapter states

The sidebar reflects adapter metadata, but the broader orchestration layer has not yet been refactored to use state transitions like:

- `running -> waiting_approval`
- `running -> waiting_choice`
- `running -> waiting_text`

That is still a follow-up task.

## Files To Read First

If another AI continues this work, read these first in this order:

1. [macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift)
2. [macos/Sources/Features/AIForeman/TerminalUnderstanding.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/TerminalUnderstanding.swift)
3. [macos/Sources/Features/AIForeman/TerminalSnapshot.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/TerminalSnapshot.swift)
4. [macos/Sources/Features/AIForeman/ManagedAgentRegistry.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/ManagedAgentRegistry.swift)
5. [macos/Sources/App/macOS/AppDelegate.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/App/macOS/AppDelegate.swift)
6. [macos/Sources/Features/AIForeman/ForemanSidebarStore.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/ForemanSidebarStore.swift)
7. [macos/Sources/Features/AIForeman/TerminalSummaryRow.swift](/Users/nambouchara/speed2/ghostty/macos/Sources/Features/AIForeman/TerminalSummaryRow.swift)

Then read the tests:

1. [macos/Tests/Terminal/TerminalSnapshotTests.swift](/Users/nambouchara/speed2/ghostty/macos/Tests/Terminal/TerminalSnapshotTests.swift)
2. [macos/Tests/Terminal/TerminalUnderstandingTests.swift](/Users/nambouchara/speed2/ghostty/macos/Tests/Terminal/TerminalUnderstandingTests.swift)
3. [macos/Tests/Terminal/ForemanSidebarStoreTests.swift](/Users/nambouchara/speed2/ghostty/macos/Tests/Terminal/ForemanSidebarStoreTests.swift)
4. [macos/Tests/Terminal/ManagedAgentRegistryTests.swift](/Users/nambouchara/speed2/ghostty/macos/Tests/Terminal/ManagedAgentRegistryTests.swift)

## Verified Commands

These were run successfully after the implementation:

```bash
zig build -Demit-macos-app=false
```

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ManagedAgentRegistryTests \
  -only-testing:GhosttyTests/TerminalSnapshotTests \
  -only-testing:GhosttyTests/TerminalUnderstandingTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

```bash
xcodebuild build -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS'
```

## Recommended Next Step

The next meaningful slice should be:

### Claude first-class managed integration

Implement in this order:

1. Add a user-facing setup/readiness model
- expose registry readiness in Foreman UI
- represent:
  - installed
  - needs setup
  - ready
  - failed setup

2. Implement Claude one-time setup
- patch `~/.claude/settings.json`
- add Foreman hook commands or a socket/file sink
- make the operation idempotent

3. Wire Claude hook events into the adapter
- convert hook payloads into adapter event input
- make hook signal outrank heuristics

4. Add a managed launch UI path
- let the user start Claude from Foreman
- use the existing `launchManagedAgent(_:)`

5. Refactor chat/orchestration to react to adapter transitions
- surface `waiting_approval`
- surface `waiting_choice`
- surface `waiting_text`

This is the cleanest next slice because:

- the architecture already supports it
- Claude is the most user-visible supported agent
- it moves the system from heuristic-first to structured-first for at least one agent

## Constraints / Notes

- There is an unrelated untracked file in the repo:
  - `docs/superpowers/plans/2026-05-03-foreman-agent-orchestrator-interpretation.md`
  - it was intentionally left untouched
- The current work was done on `main`
- The branch already had prior unrelated commits and local state; nothing unrelated was reverted

## Short Summary For Another Agent

If you only need the shortest briefing:

- semantic prompt state from Ghostty core is now available in Foreman snapshots
- Foreman understandings now include agent identity, interaction state, support level, and evidence
- the understanding engine is now adapter-based for Claude/Codex/Kimi
- the sidebar shows that metadata
- managed-agent definitions and an internal launch hook exist
- structured hook/JSON/ACP integration does not exist yet
- the best next task is Claude one-time setup + hook ingestion + managed launch UI
