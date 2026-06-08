# Foreman Terminal-Authority Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Foreman redesign so terminal-local worker state is the authoritative control plane, while Foreman becomes a thin narrator/router/voice layer with consistent manual and autonomous behavior.

**Architecture:** Introduce an explicit `TerminalWorkerSnapshot` contract that is produced from first-class worker runtimes and carried through observed context, pending attention, routing, and UI. Keep the new per-sidebar session and routing work, extract shared runtime policy for mode/completion/autonomy, and thin `ForemanAgent` plus `ForemanConversation` so they stop acting like a second local worker brain.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, existing AIForeman runtime detectors and session monitors, `xcodebuild` test targets under `macos/Tests/Terminal`.

---

## File Structure

- Create: `macos/Sources/Features/AIForeman/TerminalWorkerSnapshot.swift`
  Responsibility: authoritative per-terminal control-plane contract, including lifecycle, attention, request, suggestion, execution policy, and freshness metadata.
- Create: `macos/Sources/Features/AIForeman/TerminalWorkerSnapshotProjector.swift`
  Responsibility: project first-class worker runtime data into `TerminalWorkerSnapshot` for Kimi, Codex, Claude Code, and fallback legacy terminals.
- Create: `macos/Sources/Features/AIForeman/ForemanRuntimePolicy.swift`
  Responsibility: shared decisions for continuation, plan-mode blocking, completed-goal latching, and explicit reopen/extend behavior.
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`
  Responsibility: carry the authoritative worker snapshot alongside the UI-friendly understanding.
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstandingProjector.swift`
  Responsibility: adapt an authoritative worker snapshot into `TerminalUnderstanding` instead of inventing competing suggestions when authoritative state exists.
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`
  Responsibility: accept authoritative worker snapshots during understanding and generate a voice-friendly overview that preserves terminal referents.
- Modify: `macos/Sources/Features/AIForeman/ForemanObservedTerminalContext.swift`
  Responsibility: carry `workerSnapshots` in the shared observed context.
- Modify: `macos/Sources/Features/AIForeman/ForemanObservedContextBuilder.swift`
  Responsibility: build authoritative worker snapshots and pass them through to the rest of the runtime.
- Modify: `macos/Sources/Features/AIForeman/AgentInteractionContext.swift`
  Responsibility: expose request metadata and planning/runtime flags needed to build authoritative worker snapshots.
- Modify: `macos/Sources/Features/AIForeman/AgentInteractionContextResolver.swift`
  Responsibility: extract structured request, plan-mode, and session metadata from native worker runtime signals.
- Modify: `macos/Sources/Features/AIForeman/KimiWireTypes.swift`
  Responsibility: preserve `plan_mode` and request identifiers in a form that can drive the snapshot projector.
- Modify: `macos/Sources/Features/AIForeman/PendingAgentAttentionFactory.swift`
  Responsibility: build approval, choice, and reply UI from authoritative requests and suggestions before falling back to heuristic parsing.
- Modify: `macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift`
  Responsibility: allow snapshot-backed request fingerprints to survive prompt text churn.
- Modify: `macos/Sources/Features/AIForeman/AgentStateMonitor.swift`
  Responsibility: treat changed request identity as new attention even when the coarse interaction state stays the same.
- Modify: `macos/Sources/Features/AIForeman/ForemanReactiveEventRouter.swift`
  Responsibility: route authoritative pending attention directly and avoid redundant Foreman-authored drafts when the worker already provided one.
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarRouting.swift`
  Responsibility: route using authoritative worker snapshots, execution policy, and shared runtime policy instead of only conversation state.
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarSession.swift`
  Responsibility: preserve mode across recreation and reduce the session wrapper to coordinator behavior over authoritative observed state.
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
  Responsibility: expose authoritative worker suggestions, resolved targets, and completion/autonomy gating to the UI.
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
  Responsibility: keep transcript and UI status only; stop being the long-term source of truth for active goal and observed terminal semantics.
- Modify: `macos/Sources/Features/AIForeman/ForemanAgent.swift`
  Responsibility: stop freelancing next-step planning when authoritative worker suggestions exist; retain only project-level guidance and narrow narration work.
- Modify: `macos/Sources/Features/AIForeman/ForemanService.swift`
  Responsibility: accept immutable observed state and narration context rather than relying on a mutable conversation as the semantic source of truth.
- Modify: `macos/Sources/Features/AIForeman/OpenAIClient.swift`
  Responsibility: update LLM prompts so Foreman narrates and guides rather than re-planning terminal-local work.
- Modify: `macos/Sources/Features/AIForeman/ForemanNotifier.swift`
  Responsibility: use voice-ready rollup summaries with explicit terminal referents.
- Modify: `macos/Sources/Features/AIForeman/ForemanChatView.swift`
  Responsibility: show authoritative worker suggestion provenance, plan-mode blocking, and explicit completion controls.
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarView.swift`
  Responsibility: expose rollup status and multi-terminal attention summary cleanly.
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
  Responsibility: keep shared observation infrastructure, pass worker snapshots through the app runtime, and stop using Foreman conversation state as the hidden semantic authority.
- Create: `macos/Tests/Terminal/TerminalWorkerSnapshotTests.swift`
  Responsibility: unit coverage for the worker snapshot contract and execution-policy semantics.
- Create: `macos/Tests/Terminal/TerminalWorkerSnapshotProjectorTests.swift`
  Responsibility: unit coverage for native-runtime-to-snapshot projection.
- Create: `macos/Tests/Terminal/ForemanRuntimePolicyTests.swift`
  Responsibility: unit coverage for plan mode, completion latching, reopen rules, and autonomy blocking.
- Modify: `macos/Tests/Terminal/TerminalUnderstandingTests.swift`
  Responsibility: verify `TerminalUnderstanding` carries authoritative worker state correctly.
- Modify: `macos/Tests/Terminal/TerminalUnderstandingProjectorTests.swift`
  Responsibility: verify authoritative worker state suppresses competing heuristic suggestions.
- Modify: `macos/Tests/Terminal/AgentInteractionContextResolverTests.swift`
  Responsibility: verify request metadata and plan mode extraction from first-class agent runtimes.
- Modify: `macos/Tests/Terminal/KimiWireIntegrationTests.swift`
  Responsibility: verify Kimi `plan_mode` and question data project into worker snapshots.
- Modify: `macos/Tests/Terminal/PendingAgentAttentionFactoryTests.swift`
  Responsibility: verify authoritative requests and suggestions become actionable UI without parsing freeform text.
- Modify: `macos/Tests/Terminal/AgentStateMonitorTests.swift`
  Responsibility: verify changed request identity creates new attention events.
- Modify: `macos/Tests/Terminal/ForemanReactiveEventRouterTests.swift`
  Responsibility: verify snapshot-backed pending attention bypasses redundant Foreman drafting.
- Modify: `macos/Tests/Terminal/ForemanSidebarRoutingTests.swift`
  Responsibility: verify plan-mode blocking, stale request invalidation, and execution-policy gating.
- Modify: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`
  Responsibility: verify authoritative worker suggestions surface consistently in the UI state.
- Modify: `macos/Tests/Terminal/ForemanAgentTests.swift`
  Responsibility: verify Foreman no longer authors local-worker next steps when a worker snapshot already does.
- Modify: `macos/Tests/Terminal/ForemanServiceTests.swift`
  Responsibility: verify Foreman prompt building is narration/guidance-oriented.
- Modify: `macos/Tests/Terminal/AppDelegateForemanSidebarSessionTests.swift`
  Responsibility: verify session recreation preserves mode and independent sidebars keep independent semantic state.
- Modify: `macos/Tests/Terminal/AppDelegateGoalCommandTests.swift`
  Responsibility: verify completed goals only reopen through explicit goal commands.
- Modify: `macos/Tests/Terminal/ForemanObservedContextBuilderTests.swift`
  Responsibility: verify the observed context carries worker snapshots and voice-ready overviews.

### Task 1: Introduce The Authoritative Worker Snapshot Contract

**Files:**
- Create: `macos/Sources/Features/AIForeman/TerminalWorkerSnapshot.swift`
- Create: `macos/Tests/Terminal/TerminalWorkerSnapshotTests.swift`
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstanding.swift`
- Modify: `macos/Tests/Terminal/TerminalUnderstandingTests.swift`

- [ ] **Step 1: Write the failing contract tests**

```swift
import Foundation
import Testing
@testable import Ghostty

struct TerminalWorkerSnapshotTests {
    @Test
    func recommendedSuggestionPrefersExplicitRecommendedFlag() throws {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-1",
            revision: 7,
            observedAt: Date(timeIntervalSince1970: 1_748_000_000),
            ttlMilliseconds: 15_000,
            workerGoal: "investigate auth failures",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for a reply.",
                details: ["Asked whether the API should stay stable."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-7",
                kind: .reply,
                prompt: "Should I preserve the current API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "s1",
                    kind: .reply,
                    title: "Preserve the API",
                    payload: .text("Preserve the current API and adapt the internals."),
                    rationale: "Lowest migration risk.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-7"
                ),
            ]
        )

        #expect(snapshot.recommendedSuggestion?.id == "s1")
        #expect(snapshot.attentionFingerprint == "codex-session-1|7|req-7")
    }

    @Test
    func snapshotRoundTripsThroughJSON() throws {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-2",
            workerSessionID: "kimi-session-9",
            revision: 12,
            observedAt: Date(timeIntervalSince1970: 1_748_111_111),
            ttlMilliseconds: 10_000,
            workerGoal: "compare the refactor options",
            agent: .init(identity: .kimi),
            state: .init(
                lifecycle: .blocked,
                attention: .choiceRequired,
                summary: "Kimi needs a refactor choice.",
                details: ["Two API directions are available."],
                runtimeFlags: [.planning]
            ),
            request: .init(
                id: "req-12",
                kind: .choice,
                prompt: "Which direction should I take?",
                options: [
                    .init(id: "keep_api", label: "Keep current API", recommended: true),
                    .init(id: "break_api", label: "Allow breaking change", recommended: false),
                ]
            ),
            suggestions: []
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalWorkerSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }
}
```

- [ ] **Step 2: Run the contract tests and confirm they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalWorkerSnapshotTests \
  -only-testing:GhosttyTests/TerminalUnderstandingTests
```

Expected: FAIL with missing `TerminalWorkerSnapshot` types and unknown `workerSnapshot` support on `TerminalUnderstanding`.

- [ ] **Step 3: Implement the worker snapshot contract**

```swift
import Foundation

enum TerminalWorkerLifecycle: String, Codable, Equatable, Sendable {
    case idle
    case running
    case blocked
    case completed
    case failed
}

enum TerminalWorkerAttention: String, Codable, Equatable, Sendable {
    case none
    case replyRequired = "reply_required"
    case choiceRequired = "choice_required"
    case approvalRequired = "approval_required"
    case error
}

enum TerminalWorkerRuntimeFlag: String, Codable, Equatable, Sendable {
    case planning
}

enum TerminalWorkerSuggestionKind: String, Codable, Equatable, Sendable {
    case reply
    case command
    case choice
    case approval
    case foremanPrompt = "foreman_prompt"
}

enum TerminalWorkerSuggestionExecution: String, Codable, Equatable, Sendable {
    case manualOnly = "manual_only"
    case autonomousOK = "autonomous_ok"
}

struct TerminalWorkerSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let terminalID: String
    let workerSessionID: String
    let revision: Int
    let observedAt: Date
    let ttlMilliseconds: Int
    let workerGoal: String?
    let agent: AgentDescriptor
    let state: State
    let request: Request?
    let suggestions: [Suggestion]

    struct AgentDescriptor: Codable, Equatable, Sendable {
        let identity: AgentIdentity
    }

    struct State: Codable, Equatable, Sendable {
        let lifecycle: TerminalWorkerLifecycle
        let attention: TerminalWorkerAttention
        let summary: String
        let details: [String]
        let runtimeFlags: [TerminalWorkerRuntimeFlag]
    }

    struct Request: Codable, Equatable, Sendable {
        let id: String
        let kind: Kind
        let prompt: String
        let options: [Option]
    }

    struct Option: Codable, Equatable, Sendable {
        let id: String
        let label: String
        let recommended: Bool
    }

    struct Suggestion: Codable, Equatable, Sendable {
        let id: String
        let kind: TerminalWorkerSuggestionKind
        let title: String
        let payload: Payload
        let rationale: String
        let recommended: Bool
        let execution: TerminalWorkerSuggestionExecution
        let requestID: String?
    }

    enum Kind: String, Codable, Equatable, Sendable {
        case reply
        case choice
        case approval
        case command
    }

    enum Payload: Codable, Equatable, Sendable {
        case text(String)
        case command(String)
        case option(String)
        case approval(String)
    }

    var recommendedSuggestion: Suggestion? {
        suggestions.first(where: \.recommended)
    }

    var attentionFingerprint: String {
        if let request {
            return "\(workerSessionID)|\(revision)|\(request.id)"
        }
        return "\(workerSessionID)|\(revision)"
    }
}
```

- [ ] **Step 4: Extend `TerminalUnderstanding` to carry the authoritative snapshot**

```swift
struct TerminalUnderstanding: Codable, Equatable, Sendable, Identifiable {
    let terminalID: String
    let title: String
    let cwd: String?
    let state: TerminalUnderstandingState
    let agentIdentity: AgentIdentity
    let agentInteractionState: AgentInteractionState
    let supportLevel: AgentSupportLevel
    let lastMeaningfulEvent: String
    let shortExplanation: String
    let importantDetails: [String]
    let evidence: [UnderstandingEvidence]
    let suggestedNextActions: [TerminalSuggestedAction]
    let agentInteractionContext: AgentInteractionContext
    let workerSnapshot: TerminalWorkerSnapshot?

    init(
        terminalID: String,
        title: String,
        cwd: String? = nil,
        state: TerminalUnderstandingState,
        agentIdentity: AgentIdentity = .none,
        agentInteractionState: AgentInteractionState = .unknown,
        supportLevel: AgentSupportLevel = .genericFallback,
        lastMeaningfulEvent: String,
        shortExplanation: String,
        importantDetails: [String] = [],
        evidence: [UnderstandingEvidence] = [],
        suggestedNextActions: [TerminalSuggestedAction] = [],
        agentInteractionContext: AgentInteractionContext = .none,
        workerSnapshot: TerminalWorkerSnapshot? = nil
    ) {
        self.terminalID = terminalID
        self.title = title
        self.cwd = cwd
        self.state = state
        self.agentIdentity = agentIdentity
        self.agentInteractionState = agentInteractionState
        self.supportLevel = supportLevel
        self.lastMeaningfulEvent = lastMeaningfulEvent
        self.shortExplanation = shortExplanation
        self.importantDetails = importantDetails
        self.evidence = evidence
        self.suggestedNextActions = suggestedNextActions
        self.agentInteractionContext = agentInteractionContext
        self.workerSnapshot = workerSnapshot
    }
}
```

- [ ] **Step 5: Re-run the contract tests and confirm they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalWorkerSnapshotTests \
  -only-testing:GhosttyTests/TerminalUnderstandingTests
```

Expected: PASS.

- [ ] **Step 6: Commit the contract layer**

```bash
git add macos/Sources/Features/AIForeman/TerminalWorkerSnapshot.swift \
  macos/Sources/Features/AIForeman/TerminalUnderstanding.swift \
  macos/Tests/Terminal/TerminalWorkerSnapshotTests.swift \
  macos/Tests/Terminal/TerminalUnderstandingTests.swift
git commit -m "feat: add terminal worker snapshot contract"
```

### Task 2: Build Authoritative Worker Snapshots From Runtime Signals

**Files:**
- Create: `macos/Sources/Features/AIForeman/TerminalWorkerSnapshotProjector.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanObservedTerminalContext.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanObservedContextBuilder.swift`
- Modify: `macos/Sources/Features/AIForeman/AgentInteractionContext.swift`
- Modify: `macos/Sources/Features/AIForeman/AgentInteractionContextResolver.swift`
- Modify: `macos/Sources/Features/AIForeman/KimiWireTypes.swift`
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`
- Create: `macos/Tests/Terminal/TerminalWorkerSnapshotProjectorTests.swift`
- Modify: `macos/Tests/Terminal/AgentInteractionContextResolverTests.swift`
- Modify: `macos/Tests/Terminal/KimiWireIntegrationTests.swift`
- Modify: `macos/Tests/Terminal/ForemanObservedContextBuilderTests.swift`

- [ ] **Step 1: Write failing projector and plan-mode tests**

```swift
import Foundation
import Testing
@testable import Ghostty

struct TerminalWorkerSnapshotProjectorTests {
    @Test
    func kimiPlanModeProjectsPlanningFlagAndChoiceRequest() throws {
        let projector = TerminalWorkerSnapshotProjector()
        let snapshot = TerminalSnapshot(
            terminalID: "term-1",
            title: "kimi",
            cwd: "/tmp/repo",
            visibleText: "Which direction should I take?",
            isFocused: true,
            lastInputPreview: nil,
            signals: .init()
        )
        let context = AgentInteractionContext.waitingChoice(
            question: "Which direction should I take?",
            options: ["Keep current API", "Allow breaking change"],
            requestID: "req-12",
            sessionID: "kimi-session-12",
            revision: 12,
            isPlanning: true
        )

        let projected = projector.project(
            snapshot: snapshot,
            workerGoal: "compare API strategies",
            identity: .kimi,
            context: context,
            fallbackState: .running
        )

        #expect(projected?.state.runtimeFlags == [.planning])
        #expect(projected?.request?.id == "req-12")
        #expect(projected?.state.attention == .choiceRequired)
    }
}
```

- [ ] **Step 2: Run the targeted tests and confirm they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalWorkerSnapshotProjectorTests \
  -only-testing:GhosttyTests/AgentInteractionContextResolverTests \
  -only-testing:GhosttyTests/KimiWireIntegrationTests \
  -only-testing:GhosttyTests/ForemanObservedContextBuilderTests
```

Expected: FAIL with missing `TerminalWorkerSnapshotProjector` and missing request/session/planning metadata on `AgentInteractionContext`.

- [ ] **Step 3: Extend `AgentInteractionContext` with request and planning metadata**

```swift
enum AgentInteractionContext: Codable, Equatable, Sendable {
    case none
    case running(stepDescription: String?, sessionID: String?, revision: Int?)
    case waitingApproval(description: String, tool: String?, requestID: String?, sessionID: String?, revision: Int?, isPlanning: Bool)
    case waitingChoice(question: String, options: [String], requestID: String?, sessionID: String?, revision: Int?, isPlanning: Bool)
    case waitingText(question: String?, requestID: String?, sessionID: String?, revision: Int?, isPlanning: Bool)
    case completed(summary: String?, sessionID: String?, revision: Int?)
    case error(description: String, sessionID: String?, revision: Int?)

    var requestID: String? {
        switch self {
        case .waitingApproval(_, _, let requestID, _, _, _): return requestID
        case .waitingChoice(_, _, let requestID, _, _, _): return requestID
        case .waitingText(_, let requestID, _, _, _): return requestID
        default: return nil
        }
    }

    var sessionID: String? {
        switch self {
        case .running(_, let sessionID, _): return sessionID
        case .waitingApproval(_, _, _, let sessionID, _, _): return sessionID
        case .waitingChoice(_, _, _, let sessionID, _, _): return sessionID
        case .waitingText(_, _, let sessionID, _, _): return sessionID
        case .completed(_, let sessionID, _): return sessionID
        case .error(_, let sessionID, _): return sessionID
        case .none: return nil
        }
    }

    var revision: Int? {
        switch self {
        case .running(_, _, let revision): return revision
        case .waitingApproval(_, _, _, _, let revision, _): return revision
        case .waitingChoice(_, _, _, _, let revision, _): return revision
        case .waitingText(_, _, _, let revision, _): return revision
        case .completed(_, _, let revision): return revision
        case .error(_, _, let revision): return revision
        case .none: return nil
        }
    }

    var isPlanning: Bool {
        switch self {
        case .waitingApproval(_, _, _, _, _, let isPlanning): return isPlanning
        case .waitingChoice(_, _, _, _, _, let isPlanning): return isPlanning
        case .waitingText(_, _, _, _, let isPlanning): return isPlanning
        default: return false
        }
    }
}
```

- [ ] **Step 4: Implement the projector and observed-context plumbing**

```swift
import Foundation

struct TerminalWorkerSnapshotProjector {
    func project(
        snapshot: TerminalSnapshot,
        workerGoal: String?,
        identity: AgentIdentity,
        context: AgentInteractionContext,
        fallbackState: TerminalUnderstandingState
    ) -> TerminalWorkerSnapshot? {
        guard identity != .none else { return nil }

        let request = makeRequest(from: context)
        let runtimeFlags: [TerminalWorkerRuntimeFlag] = context.isPlanning ? [.planning] : []

        return TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: snapshot.terminalID,
            workerSessionID: context.sessionID ?? "\(identity.rawValue)-\(snapshot.terminalID)",
            revision: context.revision ?? 0,
            observedAt: Date(),
            ttlMilliseconds: 15_000,
            workerGoal: workerGoal,
            agent: .init(identity: identity),
            state: .init(
                lifecycle: lifecycle(for: context, fallbackState: fallbackState),
                attention: attention(for: context),
                summary: summary(for: snapshot, context: context),
                details: details(for: context),
                runtimeFlags: runtimeFlags
            ),
            request: request,
            suggestions: defaultSuggestions(for: context, request: request)
        )
    }
}
```

```swift
struct ForemanObservedTerminalContext: Equatable, Sendable {
    let terminals: [TerminalSnapshot]
    let understandings: [TerminalUnderstanding]
    let workerSnapshots: [String: TerminalWorkerSnapshot]
}
```

```swift
let workerSnapshot = workerSnapshotProjector.project(
    snapshot: snapshot,
    workerGoal: nil,
    identity: understanding.agentIdentity,
    context: understanding.agentInteractionContext,
    fallbackState: understanding.state
)
```

- [ ] **Step 5: Re-run the targeted tests and confirm they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalWorkerSnapshotProjectorTests \
  -only-testing:GhosttyTests/AgentInteractionContextResolverTests \
  -only-testing:GhosttyTests/KimiWireIntegrationTests \
  -only-testing:GhosttyTests/ForemanObservedContextBuilderTests
```

Expected: PASS.

- [ ] **Step 6: Commit snapshot projection**

```bash
git add macos/Sources/Features/AIForeman/TerminalWorkerSnapshotProjector.swift \
  macos/Sources/Features/AIForeman/ForemanObservedTerminalContext.swift \
  macos/Sources/Features/AIForeman/ForemanObservedContextBuilder.swift \
  macos/Sources/Features/AIForeman/AgentInteractionContext.swift \
  macos/Sources/Features/AIForeman/AgentInteractionContextResolver.swift \
  macos/Sources/Features/AIForeman/KimiWireTypes.swift \
  macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift \
  macos/Tests/Terminal/TerminalWorkerSnapshotProjectorTests.swift \
  macos/Tests/Terminal/AgentInteractionContextResolverTests.swift \
  macos/Tests/Terminal/KimiWireIntegrationTests.swift \
  macos/Tests/Terminal/ForemanObservedContextBuilderTests.swift
git commit -m "feat: project authoritative worker snapshots"
```

### Task 3: Make Pending Attention And Suggestions Snapshot-Driven

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstandingProjector.swift`
- Modify: `macos/Sources/Features/AIForeman/PendingAgentAttentionFactory.swift`
- Modify: `macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift`
- Modify: `macos/Sources/Features/AIForeman/AgentStateMonitor.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanReactiveEventRouter.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Modify: `macos/Tests/Terminal/TerminalUnderstandingProjectorTests.swift`
- Modify: `macos/Tests/Terminal/PendingAgentAttentionFactoryTests.swift`
- Modify: `macos/Tests/Terminal/AgentStateMonitorTests.swift`
- Modify: `macos/Tests/Terminal/ForemanReactiveEventRouterTests.swift`
- Modify: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Write failing tests for authoritative suggestions and changed-request attention**

```swift
import Foundation
import Testing
@testable import Ghostty

struct PendingAgentAttentionFactoryTests {
    @Test
    func authoritativeReplySuggestionBecomesPrimaryAction() {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-41",
            revision: 41,
            observedAt: Date(timeIntervalSince1970: 1_748_222_222),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for a reply.",
                details: ["Asked whether the API should stay stable."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-41",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "preserve-api",
                    kind: .reply,
                    title: "Preserve the API",
                    payload: .text("Preserve the current API and adapt the internals."),
                    rationale: "Lowest migration risk.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-41"
                ),
            ]
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "Should I preserve the API?",
            importantDetails: [],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            workerSnapshot: snapshot
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            deltaText: "Should I preserve the API?",
            timestamp: Date(),
            fingerprint: snapshot.attentionFingerprint
        )

        let attention = PendingAgentAttentionFactory.make(from: event, understanding: understanding)

        #expect(attention?.actions.first?.title == "Preserve the API")
        #expect(attention?.fingerprint == snapshot.attentionFingerprint)
    }
}
```

- [ ] **Step 2: Run the suggestion and attention tests to confirm they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalUnderstandingProjectorTests \
  -only-testing:GhosttyTests/PendingAgentAttentionFactoryTests \
  -only-testing:GhosttyTests/AgentStateMonitorTests \
  -only-testing:GhosttyTests/ForemanReactiveEventRouterTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: FAIL because the current path still builds suggestions and pending attention from heuristics and freeform parsing.

- [ ] **Step 3: Make `TerminalUnderstandingProjector` adapt authoritative snapshots first**

```swift
struct TerminalUnderstandingProjector {
    func project(
        current: TerminalSnapshot,
        classification: AgentMeaningDetector.Detection?,
        lastOutcome: TerminalOutcomeReport?,
        lastEvent: String,
        workerSnapshot: TerminalWorkerSnapshot? = nil
    ) -> TerminalUnderstanding {
        if let workerSnapshot {
            return TerminalUnderstanding(
                terminalID: current.terminalID,
                title: current.title,
                cwd: current.cwd,
                state: mapState(from: workerSnapshot.state.lifecycle),
                agentIdentity: workerSnapshot.agent.identity,
                agentInteractionState: mapInteractionState(from: workerSnapshot.state.attention),
                supportLevel: .firstClass,
                lastMeaningfulEvent: workerSnapshot.request?.prompt ?? lastEvent,
                shortExplanation: workerSnapshot.state.summary,
                importantDetails: workerSnapshot.state.details,
                evidence: [.init(source: .runtime, detail: "authoritative_worker_snapshot", confidence: 1.0)],
                suggestedNextActions: workerSnapshot.suggestions.map(makeSuggestedAction),
                agentInteractionContext: makeContext(from: workerSnapshot),
                workerSnapshot: workerSnapshot
            )
        }

        return projectHeuristically(
            current: current,
            classification: classification,
            lastOutcome: lastOutcome,
            lastEvent: lastEvent
        )
    }
}
```

- [ ] **Step 4: Derive pending attention and event fingerprints from authoritative requests**

```swift
if let snapshot = understanding?.workerSnapshot,
   let request = snapshot.request {
    return PendingAgentAttention(
        terminalID: snapshot.terminalID,
        agentIdentity: snapshot.agent.identity,
        interactionState: understanding?.agentInteractionState ?? .waitingText,
        fingerprint: snapshot.attentionFingerprint,
        title: request.kind == .choice ? "Choose an option" : "Suggested reply",
        description: request.prompt,
        detail: snapshot.state.details.joined(separator: "\n"),
        actions: snapshot.suggestions.map { suggestion in
            PendingAgentAction(
                id: suggestion.id,
                title: suggestion.title,
                payload: suggestion.payload.primaryText,
                style: suggestion.recommended ? .primary : .secondary
            )
        }
    )
}
```

```swift
private static func eventText(from understanding: TerminalUnderstanding) -> String {
    if let snapshot = understanding.workerSnapshot, let request = snapshot.request {
        return "\(snapshot.workerSessionID)|\(snapshot.revision)|\(request.id)"
    }
    if understanding.agentInteractionState == .waitingText,
       let question = understanding.agentInteractionContext.descriptionString,
       !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return question
    }
    return understanding.importantDetails.joined(separator: "\n")
}
```

- [ ] **Step 5: Re-run the targeted tests and confirm they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalUnderstandingProjectorTests \
  -only-testing:GhosttyTests/PendingAgentAttentionFactoryTests \
  -only-testing:GhosttyTests/AgentStateMonitorTests \
  -only-testing:GhosttyTests/ForemanReactiveEventRouterTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit snapshot-driven UI state**

```bash
git add macos/Sources/Features/AIForeman/TerminalUnderstandingProjector.swift \
  macos/Sources/Features/AIForeman/PendingAgentAttentionFactory.swift \
  macos/Sources/Features/AIForeman/AgentNeedsAttentionEvent.swift \
  macos/Sources/Features/AIForeman/AgentStateMonitor.swift \
  macos/Sources/Features/AIForeman/ForemanReactiveEventRouter.swift \
  macos/Sources/Features/AIForeman/ForemanSidebarStore.swift \
  macos/Tests/Terminal/TerminalUnderstandingProjectorTests.swift \
  macos/Tests/Terminal/PendingAgentAttentionFactoryTests.swift \
  macos/Tests/Terminal/AgentStateMonitorTests.swift \
  macos/Tests/Terminal/ForemanReactiveEventRouterTests.swift \
  macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "feat: drive foreman attention from worker snapshots"
```

### Task 4: Extract Shared Runtime Policy For Mode, Completion, And Autonomy

**Files:**
- Create: `macos/Sources/Features/AIForeman/ForemanRuntimePolicy.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarRouting.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarSession.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanProjectScope.swift`
- Create: `macos/Tests/Terminal/ForemanRuntimePolicyTests.swift`
- Modify: `macos/Tests/Terminal/ForemanSidebarRoutingTests.swift`
- Modify: `macos/Tests/Terminal/AppDelegateGoalCommandTests.swift`
- Modify: `macos/Tests/Terminal/AppDelegateForemanSidebarSessionTests.swift`

- [ ] **Step 1: Write failing policy tests**

```swift
import Testing
@testable import Ghostty

struct ForemanRuntimePolicyTests {
    @Test
    func planningSnapshotBlocksAutonomousContinuation() {
        let policy = ForemanRuntimePolicy()
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "kimi-session-12",
            revision: 12,
            observedAt: Date(timeIntervalSince1970: 1_748_333_333),
            ttlMilliseconds: 15_000,
            workerGoal: "compare API directions",
            agent: .init(identity: .kimi),
            state: .init(
                lifecycle: .running,
                attention: .choiceRequired,
                summary: "Kimi is waiting in plan mode.",
                details: ["Two API directions are available."],
                runtimeFlags: [.planning]
            ),
            request: .init(
                id: "req-12",
                kind: .choice,
                prompt: "Which direction should I take?",
                options: [
                    .init(id: "keep_api", label: "Keep current API", recommended: true),
                    .init(id: "break_api", label: "Allow breaking change", recommended: false),
                ]
            ),
            suggestions: [
                .init(
                    id: "keep-api",
                    kind: .choice,
                    title: "Keep current API",
                    payload: .option("keep_api"),
                    rationale: "Lowest migration risk.",
                    recommended: true,
                    execution: .autonomousOK,
                    requestID: "req-12"
                ),
            ]
        )

        let decision = policy.continuationDecision(
            mode: .autonomous,
            activeGoalStatus: .active,
            resolvedTarget: .terminalReply(terminalID: "term-1", fingerprint: snapshot.attentionFingerprint),
            selectedSnapshot: snapshot
        )

        #expect(decision == .requireUser("The worker is in plan mode. Choose whether to resume after the plan is reviewed."))
    }

    @Test
    func completedGoalDoesNotReopenOnGenericChatInput() {
        let policy = ForemanRuntimePolicy()

        #expect(policy.shouldReopenCompletedGoal(for: "continue") == false)
        #expect(policy.shouldReopenCompletedGoal(for: "/goal reopen") == true)
    }
}
```

- [ ] **Step 2: Run the policy tests and confirm they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ForemanRuntimePolicyTests \
  -only-testing:GhosttyTests/ForemanSidebarRoutingTests \
  -only-testing:GhosttyTests/AppDelegateGoalCommandTests \
  -only-testing:GhosttyTests/AppDelegateForemanSidebarSessionTests
```

Expected: FAIL because there is no shared runtime policy, sessions still fall back to `.interactive`, and generic text still reopens completed goals.

- [ ] **Step 3: Implement the shared runtime policy**

```swift
import Foundation

enum ForemanContinuationDecision: Equatable, Sendable {
    case allowAutonomousDispatch
    case requireUser(String)
    case blockCompletedGoal(String)
}

struct ForemanRuntimePolicy {
    func continuationDecision(
        mode: AgentMode,
        activeGoalStatus: ForemanProjectGoalStatus?,
        resolvedTarget: ForemanSidebarTarget,
        selectedSnapshot: TerminalWorkerSnapshot?
    ) -> ForemanContinuationDecision {
        if activeGoalStatus == .completed {
            return .blockCompletedGoal("The saved project goal is complete. Reopen or extend it before dispatching more work.")
        }

        guard mode == .autonomous else {
            return .requireUser("Manual mode requires explicit send or approval.")
        }

        if selectedSnapshot?.state.runtimeFlags.contains(.planning) == true {
            return .requireUser("The worker is in plan mode. Choose whether to resume after the plan is reviewed.")
        }

        if case .ambiguous = resolvedTarget {
            return .requireUser("Choose a terminal before continuing.")
        }

        return .allowAutonomousDispatch
    }

    func shouldReopenCompletedGoal(for input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/goal reopen")
    }
}
```

- [ ] **Step 4: Preserve mode across session recreation and remove implicit goal reopen**

```swift
@MainActor
final class ForemanSidebarSession: ForemanSidebarSessionControlling {
    private var preservedMode: AgentMode = .interactive

    func start(goal: String, mode: AgentMode) {
        preservedMode = mode
        let agent = ensureAgent(preferredTerminalID: preferredTerminalID())
        Task {
            await agent.start(
                goal: goal,
                mode: mode,
                captureSnapshots: captureSnapshots,
                captureObservedContext: captureObservedContext
            )
        }
    }

    func receiveUserMessage(_ text: String) {
        guard let agent else {
            let agent = ensureAgent(preferredTerminalID: preferredTerminalID())
            let initialGoal = conversation.effectiveGoal ?? text
            Task {
                await agent.start(
                    goal: initialGoal,
                    mode: preservedMode,
                    captureSnapshots: captureSnapshots,
                    captureObservedContext: captureObservedContext
                )
                if initialGoal != text {
                    await agent.receiveUserMessage(text)
                }
            }
            return
        }

        Task {
            await agent.receiveUserMessage(text)
        }
    }
}
```

- [ ] **Step 5: Re-run the targeted tests and confirm they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ForemanRuntimePolicyTests \
  -only-testing:GhosttyTests/ForemanSidebarRoutingTests \
  -only-testing:GhosttyTests/AppDelegateGoalCommandTests \
  -only-testing:GhosttyTests/AppDelegateForemanSidebarSessionTests
```

Expected: PASS.

- [ ] **Step 6: Commit the policy layer**

```bash
git add macos/Sources/Features/AIForeman/ForemanRuntimePolicy.swift \
  macos/Sources/Features/AIForeman/ForemanSidebarRouting.swift \
  macos/Sources/Features/AIForeman/ForemanSidebarSession.swift \
  macos/Sources/Features/AIForeman/ForemanSidebarStore.swift \
  macos/Sources/Features/AIForeman/ForemanConversation.swift \
  macos/Sources/Features/AIForeman/ForemanProjectScope.swift \
  macos/Tests/Terminal/ForemanRuntimePolicyTests.swift \
  macos/Tests/Terminal/ForemanSidebarRoutingTests.swift \
  macos/Tests/Terminal/AppDelegateGoalCommandTests.swift \
  macos/Tests/Terminal/AppDelegateForemanSidebarSessionTests.swift
git commit -m "feat: add foreman runtime policy"
```

### Task 5: Thin `ForemanAgent` And `ForemanService` Into Narration And Project Guidance

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanAgent.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanService.swift`
- Modify: `macos/Sources/Features/AIForeman/OpenAIClient.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
- Modify: `macos/Tests/Terminal/ForemanAgentTests.swift`
- Modify: `macos/Tests/Terminal/ForemanServiceTests.swift`
- Modify: `macos/Tests/Terminal/ForemanAgentDeltaIntegrationTests.swift`

- [ ] **Step 1: Write failing tests for the thinned Foreman role**

```swift
import Foundation
import Testing
@testable import Ghostty

struct ForemanAgentTests {
    @Test
    func draftPendingAttentionUsesWorkerSuggestionBeforeLLMReplyDraft() async throws {
        let conversation = await MainActor.run { ForemanConversation() }
        let llm = RecordingLLMClient()
        let service = ForemanService(client: llm)
        let runtime = ForemanProjectGoalRuntime(store: ForemanMemoryStore.inMemory())
        let agent = ForemanAgent(
            conversation: conversation,
            foremanService: service,
            goalRuntime: runtime,
            preferredTerminalID: "term-1",
            onSendCommand: { _, _ in true },
            onStatusChange: { _ in },
            onAction: { _, _ in }
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            deltaText: "Should I preserve the API?",
            timestamp: Date(),
            fingerprint: "codex-session-1|7|req-7"
        )
        let terminalSnapshot = TerminalSnapshot(
            terminalID: "term-1",
            title: "codex",
            cwd: "/tmp/repo",
            visibleText: "Should I preserve the API?",
            isFocused: true,
            lastInputPreview: nil,
            signals: .init()
        )
        let workerSnapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-1",
            revision: 7,
            observedAt: Date(timeIntervalSince1970: 1_748_444_444),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for a reply.",
                details: ["Asked whether the API should stay stable."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-7",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "preserve-api",
                    kind: .reply,
                    title: "Preserve the API",
                    payload: .text("Preserve the current API and adapt the internals."),
                    rationale: "Lowest migration risk.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-7"
                ),
            ]
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "Should I preserve the API?",
            importantDetails: [],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            workerSnapshot: workerSnapshot
        )

        let attention = try await agent.draftPendingAttention(
            for: event,
            observedContext: ForemanObservedTerminalContext(
                terminals: [terminalSnapshot],
                understandings: [understanding],
                workerSnapshots: ["term-1": workerSnapshot]
            ),
            captureSnapshots: { [terminalSnapshot] }
        )

        #expect(attention?.actions.first?.title == "Preserve the API")
        #expect(await llm.draftReplyCallCount == 0)
    }
}

actor RecordingLLMClient: ForemanLLMClient {
    private(set) var draftReplyCallCount = 0

    func summarize(snapshot: TerminalSnapshot) async throws -> TerminalSummary {
        fatalError("not used by this test")
    }

    func planDispatch(instruction: String, summaries: [TerminalSummary]) async throws -> DispatchPlan {
        fatalError("not used by this test")
    }

    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse {
        fatalError("not used by this test")
    }

    func draftAgentReply(
        conversation: ForemanConversation,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse {
        draftReplyCallCount += 1
        return .init(
            thought: "fallback",
            suggestion: .noAction(reason: "should not be called", confidence: 0.0)
        )
    }
}
```

- [ ] **Step 2: Run the agent tests and confirm they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ForemanAgentTests \
  -only-testing:GhosttyTests/ForemanServiceTests \
  -only-testing:GhosttyTests/ForemanAgentDeltaIntegrationTests
```

Expected: FAIL because `ForemanAgent` still drafts local-worker next steps itself.

- [ ] **Step 3: Add a fast path for authoritative worker suggestions**

```swift
func draftPendingAttention(
    for event: AgentNeedsAttentionEvent,
    observedContext: ForemanObservedTerminalContext? = nil,
    captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot]
) async throws -> PendingAgentAttention? {
    if let snapshot = observedContext?.workerSnapshots[event.terminalID],
       let understanding = observedContext?.understandings.first(where: { $0.terminalID == event.terminalID }),
       let attention = PendingAgentAttentionFactory.make(
            from: AgentNeedsAttentionEvent(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                deltaText: event.deltaText,
                timestamp: event.timestamp,
                fingerprint: snapshot.attentionFingerprint
            ),
            understanding: understanding
       ) {
        return attention
    }

    let contextMessage = makeContextMessage(for: event)
    await MainActor.run {
        conversation.addHiddenContext(contextMessage)
    }

    let observedTerminals = await observeTerminals(
        captureSnapshots: captureSnapshots,
        observedContext: observedContext
    )
    let terminals = observedTerminals.terminals
    let understandings = observedTerminals.understandings
    let workerSnapshots = observedContext?.workerSnapshots ?? [:]
    let overview = understandingEngine.makeOverview(
        current: understandings,
        previous: previousUnderstandings
    )
    let deltaTerminals = makeDeltaTerminals(from: terminals)

    storeObservedTerminals(observedTerminals)

    let response = try await foremanService.draftAgentReply(
        conversation: conversation,
        event: event,
        terminals: deltaTerminals,
        understandings: understandings,
        workerSnapshots: workerSnapshots,
        overview: overview,
        lastOutcome: lastOutcome
    )

    switch response.suggestion {
    case .replyToAgent(let terminalID, let message, let reason, _):
        guard terminalID == event.terminalID else { return nil }
        return PendingAgentAttention(
            terminalID: event.terminalID,
            agentIdentity: event.agentIdentity,
            interactionState: event.interactionState,
            fingerprint: event.fingerprint,
            title: "Suggested reply",
            description: reason.isEmpty ? event.deltaText : reason,
            detail: event.deltaText.isEmpty ? nil : event.deltaText,
            actions: [
                .init(
                    id: "suggested_reply",
                    title: message,
                    payload: message,
                    style: .primary
                )
            ]
        )

    case .askHuman(let terminalID, let message, let reason, _):
        guard terminalID == event.terminalID else { return nil }
        return PendingAgentAttention(
            terminalID: event.terminalID,
            agentIdentity: event.agentIdentity,
            interactionState: event.interactionState,
            fingerprint: event.fingerprint,
            title: "Needs direction",
            description: message.isEmpty ? "The agent is waiting for your direction." : message,
            detail: reason.isEmpty ? event.deltaText : reason,
            actions: []
        )

    case .noAction:
        return nil
    }
}
```

- [ ] **Step 4: Reframe the OpenAI prompt toward narration and project guidance**

```swift
private static func makeAgentStepInstructions() -> String {
    """
    You are a terminal foreman narrator and router. You do not replace an active terminal-local worker's plan.
    Return JSON only. Do not wrap the JSON in markdown code blocks.
    Choose exactly ONE action.
    Prefer summarizing progress, asking the user to resolve ambiguity, or giving project-level guidance.
    If a terminal-local worker already supplied a structured next-step suggestion, do not invent a competing suggestion.
    Use raw terminal snapshots only as supporting evidence when structured worker state is insufficient.
    """
}
```

```swift
protocol ForemanLLMClient: Sendable {
    func agentStep(
        conversation: ForemanConversation,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentStepResponse

    func draftAgentReply(
        conversation: ForemanConversation,
        event: AgentNeedsAttentionEvent,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot],
        overview: TerminalOverview,
        lastOutcome: TerminalOutcomeReport?
    ) async throws -> AgentReplyDraftResponse
}
```

- [ ] **Step 5: Re-run the targeted tests and confirm they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ForemanAgentTests \
  -only-testing:GhosttyTests/ForemanServiceTests \
  -only-testing:GhosttyTests/ForemanAgentDeltaIntegrationTests
```

Expected: PASS.

- [ ] **Step 6: Commit the agent/service thinning**

```bash
git add macos/Sources/Features/AIForeman/ForemanAgent.swift \
  macos/Sources/Features/AIForeman/ForemanService.swift \
  macos/Sources/Features/AIForeman/OpenAIClient.swift \
  macos/Sources/Features/AIForeman/ForemanConversation.swift \
  macos/Tests/Terminal/ForemanAgentTests.swift \
  macos/Tests/Terminal/ForemanServiceTests.swift \
  macos/Tests/Terminal/ForemanAgentDeltaIntegrationTests.swift
git commit -m "refactor: thin foreman agent into narrator"
```

### Task 6: Wire Voice-Ready Rollups And End-To-End Sidebar Behavior

**Files:**
- Modify: `macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanNotifier.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanChatView.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarView.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
- Modify: `macos/Tests/Terminal/ForemanObservedContextBuilderTests.swift`
- Modify: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`
- Modify: `macos/Tests/Terminal/AppDelegateForemanSidebarSessionTests.swift`

- [ ] **Step 1: Write failing tests for voice-ready rollups and plan-mode UI**

```swift
import Foundation
import Testing
@testable import Ghostty

struct ForemanObservedContextBuilderTests {
    @Test
    func overviewNamesMultipleWaitingTerminalsInsteadOfCollapsingToOne() {
        let engine = TerminalUnderstandingEngine()
        let current = [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Codex is waiting for a reply.",
                lastMeaningfulEvent: "Reply needed.",
                importantDetails: [],
                suggestedNextActions: []
            ),
            TerminalUnderstanding.preview(
                terminalID: "term-2",
                state: .waiting,
                shortExplanation: "Kimi needs approval.",
                lastMeaningfulEvent: "Approval needed.",
                importantDetails: [],
                suggestedNextActions: []
            ),
        ]

        let overview = engine.makeOverview(current: current, previous: [])

        #expect(overview.summary == "2 terminals need attention: term-1 reply required; term-2 approval required.")
    }
}
```

- [ ] **Step 2: Run the UI/runtime tests and confirm they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ForemanObservedContextBuilderTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests \
  -only-testing:GhosttyTests/AppDelegateForemanSidebarSessionTests
```

Expected: FAIL because the current overview still privileges one changed terminal and the UI does not surface authoritative suggestion provenance or planning blocks.

- [ ] **Step 3: Make the overview and notifier preserve referents**

```swift
func makeOverview(
    current: [TerminalUnderstanding],
    previous: [TerminalUnderstanding]
) -> TerminalOverview {
    let waiting = current.filter { $0.agentInteractionState == .waitingApproval || $0.agentInteractionState == .waitingChoice || $0.agentInteractionState == .waitingText }
    if waiting.count > 1 {
        let fragments = waiting.map { understanding in
            let need: String
            switch understanding.agentInteractionState {
            case .waitingApproval: need = "approval required"
            case .waitingChoice: need = "choice required"
            case .waitingText: need = "reply required"
            default: need = "attention required"
            }
            return "\(understanding.terminalID) \(need)"
        }
        return TerminalOverview(
            summary: "\(waiting.count) terminals need attention: \(fragments.joined(separator: "; ")).",
            changedTerminalIDs: waiting.map(\.terminalID),
            primaryTerminalID: nil
        )
    }

    let currentIDs = Set(current.map(\.terminalID))
    let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.terminalID, $0) })
    let changedCurrent = current.filter { previousByID[$0.terminalID] != $0 }.map(\.terminalID)
    let removed = previous.map(\.terminalID).filter { !currentIDs.contains($0) }
    let changed = changedCurrent + removed

    if let changedTerminal = current.first(where: { changedCurrent.contains($0.terminalID) }) {
        return TerminalOverview(
            summary: "\(changedTerminal.terminalID): \(changedTerminal.shortExplanation)",
            changedTerminalIDs: changed,
            primaryTerminalID: changedTerminal.terminalID
        )
    }

    if let removedTerminalID = removed.first {
        return TerminalOverview(
            summary: "\(removedTerminalID) is no longer available.",
            changedTerminalIDs: changed,
            primaryTerminalID: removedTerminalID
        )
    }

    let summary = current.isEmpty
        ? "No terminals are currently available."
        : current.map { "\($0.terminalID): \($0.shortExplanation)" }.joined(separator: " ")

    return TerminalOverview(
        summary: summary,
        changedTerminalIDs: [],
        primaryTerminalID: current.first?.terminalID
    )
}
```

```swift
content.title = "Foreman Update"
content.body = overview.summary
```

- [ ] **Step 4: Surface authoritative provenance in the chat and sidebar UI**

```swift
@Published private(set) var workerSnapshotsByTerminalID: [String: TerminalWorkerSnapshot] = [:]

var selectedTerminalWorkerSnapshot: TerminalWorkerSnapshot? {
    guard let selectedTerminalID else { return nil }
    return workerSnapshotsByTerminalID[selectedTerminalID]
}

if let snapshot = store.selectedTerminalWorkerSnapshot,
   let suggestion = snapshot.recommendedSuggestion {
    Text("Suggested by \(snapshot.agent.identity.displayName ?? "worker")")
        .font(.caption)
        .foregroundStyle(.secondary)

    Text(suggestion.title)
        .font(.body)
}

if store.selectedTerminalWorkerSnapshot?.state.runtimeFlags.contains(.planning) == true {
    Text("This worker is in plan mode. Review the plan before continuing.")
        .font(.caption)
        .foregroundStyle(.orange)
}
```

- [ ] **Step 5: Run the focused tests, then run the full redesign verification set**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/TerminalWorkerSnapshotTests \
  -only-testing:GhosttyTests/TerminalWorkerSnapshotProjectorTests \
  -only-testing:GhosttyTests/ForemanRuntimePolicyTests \
  -only-testing:GhosttyTests/TerminalUnderstandingProjectorTests \
  -only-testing:GhosttyTests/PendingAgentAttentionFactoryTests \
  -only-testing:GhosttyTests/AgentStateMonitorTests \
  -only-testing:GhosttyTests/ForemanReactiveEventRouterTests \
  -only-testing:GhosttyTests/ForemanSidebarRoutingTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests \
  -only-testing:GhosttyTests/ForemanAgentTests \
  -only-testing:GhosttyTests/ForemanServiceTests \
  -only-testing:GhosttyTests/AppDelegateForemanSidebarSessionTests \
  -only-testing:GhosttyTests/AppDelegateGoalCommandTests \
  -only-testing:GhosttyTests/ForemanObservedContextBuilderTests \
  -only-testing:GhosttyTests/KimiWireIntegrationTests
```

Expected: PASS.

Run:

```bash
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit the UI/runtime integration**

```bash
git add macos/Sources/Features/AIForeman/TerminalUnderstandingEngine.swift \
  macos/Sources/Features/AIForeman/ForemanNotifier.swift \
  macos/Sources/Features/AIForeman/ForemanChatView.swift \
  macos/Sources/Features/AIForeman/ForemanSidebarView.swift \
  macos/Sources/App/macOS/AppDelegate.swift \
  macos/Tests/Terminal/ForemanObservedContextBuilderTests.swift \
  macos/Tests/Terminal/ForemanSidebarStoreTests.swift \
  macos/Tests/Terminal/AppDelegateForemanSidebarSessionTests.swift
git commit -m "feat: complete foreman terminal authority redesign"
```

## Self-Review

### Spec Coverage

- Authority shift: covered by Tasks 1-5.
- Worker-authored state contract: covered by Tasks 1-3.
- Manual vs autonomous consistency: covered by Tasks 3-4.
- Stale-target safety and changed-request invalidation: covered by Tasks 2-4.
- Plan-mode handling and mode persistence: covered by Tasks 2 and 4.
- Voice-ready summaries and referent preservation: covered by Task 6.
- Migration away from the monolithic `ForemanAgent`: covered by Tasks 4 and 5.

### Placeholder Scan

- No `TODO`, `TBD`, or “implement later” markers appear in this plan.
- Each code-writing step includes concrete type names or function bodies.
- Each test step includes exact commands.

### Type Consistency

- `TerminalWorkerSnapshot`, `TerminalWorkerSuggestionExecution`, `ForemanRuntimePolicy`, and `TerminalWorkerSnapshotProjector` are named consistently across tasks.
- `workerSessionID`, `revision`, and `requestID` are the freshness keys used everywhere in routing, pending attention, and policy.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-25-foreman-terminal-authority-redesign.md`. Two execution options:

1. Subagent-Driven (recommended) - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. Inline Execution - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
