# Reactive Agent Reply Schema Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make reactive AI-agent waiting-text handling produce explicit reply, ask-human, or no-action outcomes.

**Architecture:** Add a dedicated `draftAgentReply` LLM contract beside `agentStep`. `ForemanAgent.draftPendingAttention` uses this narrower contract for `waitingText` events and maps each outcome to a sidebar card or no card.

**Tech Stack:** Swift, Swift Testing, existing Foreman OpenAI/Anthropic client abstractions.

---

### Task 1: Model The Draft Reply Contract

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanModels.swift`

**Steps:**
1. Add `AgentReplyDraftResponse`.
2. Add `AgentReplyDraftSuggestion` with Codable cases `reply_to_agent`, `ask_human`, and `no_action`.
3. Keep flexible terminal-id decoding consistent with `AgentAction`.

### Task 2: Add Service And Client Methods

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanService.swift`
- Modify: `macos/Sources/Features/AIForeman/OpenAIClient.swift`
- Modify: `macos/Sources/Features/AIForeman/AnthropicClient.swift`
- Test: `macos/Tests/Terminal/ForemanServiceTests.swift`
- Test: `macos/Tests/Terminal/AnthropicClientTests.swift`

**Steps:**
1. Extend `ForemanLLMClient` with `draftAgentReply`.
2. Add a fallback implementation that derives from `agentStep` only for legacy tests.
3. Add provider-specific prompt builders for the new schema.
4. Verify prompts name the three suggestion types and explain that `reply_to_agent` sends raw text to an AI agent.

### Task 3: Wire The Waiting-Text Path

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanAgent.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

**Steps:**
1. Replace `agentStep` usage in `draftPendingAttention` with `draftAgentReply`.
2. Map `reply_to_agent` to a pending attention card with one action.
3. Map `ask_human` to a visible pending attention card with no send action.
4. Map `no_action` or wrong-terminal replies to nil.
5. Add tests for all three outcomes.

### Task 4: Verify

**Run:**

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug \
  -destination 'platform=macOS,arch=arm64' SYMROOT="$PWD/macos/build" \
  -derivedDataPath "$PWD/macos/build/DerivedData" -skip-testing GhosttyUITests \
  -only-testing:GhosttyTests/ForemanAgentTests \
  -only-testing:GhosttyTests/ForemanServiceTests \
  -only-testing:GhosttyTests/AnthropicClientTests test
```

Expected: all selected tests pass.

