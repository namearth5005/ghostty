# Foreman Project Goal Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a project-scoped goal runtime to Foreman so each repo can hold its own long-lived mission, while terminal reply cards stay local and `Needs direction` remains a plain reply flow.

**Architecture:** Introduce a small pure project-scope layer that resolves project roots from terminal `cwd`, groups terminals into projects, and stores one in-memory goal runtime per project. Keep the existing terminal attention model, but route goal editing through project-aware chat targets and hide decision-guidance UI for `waiting_text` replies.

**Tech Stack:** Swift, SwiftUI, Foundation, Swift Testing, macOS Ghostty/Foreman app.

---

**Execution Context:** Run this plan from a dedicated worktree and branch before touching code.

```bash
git worktree add .worktrees/foreman-project-goal-runtime -b foreman-project-goal-runtime
cd .worktrees/foreman-project-goal-runtime
```

## File Structure

- Create `macos/Sources/Features/AIForeman/ForemanProjectScope.swift`
  - Owns pure project-scoped types:
    - `ForemanProjectPathResolver`
    - `ForemanProjectRecord`
    - `ForemanProjectGoalStatus`
    - `ForemanProjectGoal`
    - `ForemanProjectRegistry`
  - No SwiftUI or AppKit dependency.

- Create `macos/Tests/Terminal/ForemanProjectScopeTests.swift`
  - Covers path resolution, terminal grouping, and per-project goal lifecycle in `ForemanConversation`.

- Modify `macos/Sources/Features/AIForeman/ForemanMemoryStore.swift`
  - Reuse the shared project-path resolver instead of keeping a private copy.

- Modify `macos/Sources/Features/AIForeman/ForemanConversation.swift`
  - Replace the single mutable `goal` slot with project-scoped goal storage plus a selected-project compatibility shim.

- Modify `macos/Sources/Features/AIForeman/ForemanInputRouting.swift`
  - Rename the legacy goal intent to a project-aware goal intent.
  - Add a project-aware chat target for goal editing.

- Modify `macos/Tests/Terminal/ForemanInputRoutingTests.swift`
  - Cover the new `setProjectGoal` target semantics.

- Modify `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
  - Track the project registry alongside terminal rows.
  - Resolve the current project from the selected terminal.
  - Keep reply routing local to terminals and goal editing local to projects.
  - Add a pure attention classification so `waiting_text` does not show decision-guidance UI.

- Modify `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`
  - Cover project grouping, goal routing, and guidance gating.

- Modify `macos/Sources/Features/AIForeman/ForemanChatView.swift`
  - Surface project goal controls separately from terminal reply cards.
  - Hide the reevaluation panel for `Needs direction` cards.

- Modify `macos/Sources/App/macOS/AppDelegate.swift`
  - Handle the new project-goal input intent.
  - Pause the selected project goal when Foreman is explicitly stopped.

- Modify `macos/Sources/Features/AIForeman/ForemanAgent.swift`
  - Start against a concrete project ID.
  - Update project-goal status when the loop completes or gets stuck.

- Modify `macos/Tests/Terminal/ForemanAgentTests.swift`
  - Verify project-goal status changes on complete/stuck transitions.

## Task 1: Add Pure Project Scope Types

**Files:**
- Create: `macos/Sources/Features/AIForeman/ForemanProjectScope.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanMemoryStore.swift`
- Test: `macos/Tests/Terminal/ForemanProjectScopeTests.swift`

- [ ] **Step 1: Write the failing project-scope tests**

Create `macos/Tests/Terminal/ForemanProjectScopeTests.swift`:

```swift
import Foundation
import Testing
@testable import Ghostty

struct ForemanProjectScopeTests {
    @Test
    func projectPathResolverFindsNearestGitRoot() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("mend")
        let nested = repo.appendingPathComponent("Sources/App")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true, attributes: nil)

        let projectPath = ForemanProjectPathResolver.projectPath(from: nested.path)

        #expect(projectPath == repo.path)
    }

    @Test
    func projectRegistryGroupsTerminalsByResolvedProjectPath() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mend = root.appendingPathComponent("mend")
        let ghostty = root.appendingPathComponent("ghostty")
        try fileManager.createDirectory(at: mend.appendingPathComponent(".git"), withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: ghostty.appendingPathComponent(".git"), withIntermediateDirectories: true, attributes: nil)

        var registry = ForemanProjectRegistry()
        registry.rebuild(from: [
            .init(terminalID: "term-1", title: "Kimi", cwd: mend.appendingPathComponent("docs").path),
            .init(terminalID: "term-2", title: "Codex", cwd: mend.appendingPathComponent("src").path),
            .init(terminalID: "term-3", title: "Claude", cwd: ghostty.appendingPathComponent("macos").path),
        ])

        #expect(registry.projectsByID.keys.sorted() == [ghostty.path, mend.path].sorted())
        #expect(registry.projectID(forTerminalID: "term-1") == mend.path)
        #expect(registry.projectID(forTerminalID: "term-2") == mend.path)
        #expect(registry.projectID(forTerminalID: "term-3") == ghostty.path)
        #expect(registry.projectsByID[mend.path]?.terminalIDs == ["term-1", "term-2"])
    }

    @MainActor
    @Test
    func conversationStoresGoalPerProjectAndExposesSelectedProjectGoal() {
        let conversation = ForemanConversation()

        conversation.setProjectGoal(
            projectID: "/tmp/mend",
            objective: "Support ChatGPT first.",
            mode: .interactive
        )
        conversation.setProjectGoal(
            projectID: "/tmp/ghostty",
            objective: "Add a project goal runtime.",
            mode: .interactive
        )

        conversation.selectProject("/tmp/mend")
        #expect(conversation.goal == "Support ChatGPT first.")

        conversation.updateProjectGoalStatus(.paused, for: "/tmp/mend")
        #expect(conversation.projectGoal(for: "/tmp/mend")?.status == .paused)

        conversation.selectProject("/tmp/ghostty")
        #expect(conversation.goal == "Add a project goal runtime.")
        #expect(conversation.projectGoal(for: "/tmp/ghostty")?.status == .active)
    }
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanProjectScopeTests
```

Expected: test compilation fails because `ForemanProjectPathResolver`, `ForemanProjectRegistry`, `setProjectGoal`, and `projectGoal(for:)` do not exist yet.

- [ ] **Step 3: Add the shared project-scope layer**

Create `macos/Sources/Features/AIForeman/ForemanProjectScope.swift`:

```swift
import Foundation

enum ForemanProjectGoalStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case complete
    case stuck

    var isTerminal: Bool {
        switch self {
        case .complete, .stuck:
            return true
        case .active, .paused:
            return false
        }
    }
}

struct ForemanProjectGoal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let projectID: String
    var objective: String
    var status: ForemanProjectGoalStatus
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectID: String,
        objective: String,
        status: ForemanProjectGoalStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.objective = objective
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ForemanProjectRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let rootPath: String
    var title: String
    var terminalIDs: [String]

    init(rootPath: String, title: String, terminalIDs: [String] = []) {
        self.id = rootPath
        self.rootPath = rootPath
        self.title = title
        self.terminalIDs = terminalIDs
    }
}

struct ForemanProjectTerminalContext: Equatable, Sendable {
    let terminalID: String
    let title: String
    let cwd: String?
}

enum ForemanProjectPathResolver {
    static func projectPath(from cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }

        var url = URL(fileURLWithPath: cwd)
        while url.path != "/" {
            let gitDir = url.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                return url.path
            }
            url.deleteLastPathComponent()
        }

        return cwd
    }

    static func projectTitle(from projectPath: String) -> String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }
}

struct ForemanProjectRegistry: Equatable, Sendable {
    private(set) var projectsByID: [String: ForemanProjectRecord] = [:]
    private(set) var terminalProjectIDs: [String: String] = [:]

    mutating func rebuild(from terminals: [ForemanProjectTerminalContext]) {
        projectsByID = [:]
        terminalProjectIDs = [:]

        for terminal in terminals {
            guard let projectPath = ForemanProjectPathResolver.projectPath(from: terminal.cwd) else {
                continue
            }

            terminalProjectIDs[terminal.terminalID] = projectPath

            var record = projectsByID[projectPath] ?? ForemanProjectRecord(
                rootPath: projectPath,
                title: ForemanProjectPathResolver.projectTitle(from: projectPath)
            )
            if !record.terminalIDs.contains(terminal.terminalID) {
                record.terminalIDs.append(terminal.terminalID)
                record.terminalIDs.sort()
            }
            projectsByID[projectPath] = record
        }
    }

    func projectID(forTerminalID terminalID: String) -> String? {
        terminalProjectIDs[terminalID]
    }

    func project(forTerminalID terminalID: String) -> ForemanProjectRecord? {
        guard let projectID = terminalProjectIDs[terminalID] else { return nil }
        return projectsByID[projectID]
    }
}
```

Modify `macos/Sources/Features/AIForeman/ForemanMemoryStore.swift`:

```swift
    func query(cwd: String, visibleText: String, limit: Int = 5) throws -> [SituationOutcomeRecord] {
        let db = try openIfNeeded()
        let projectPath = ForemanProjectPathResolver.projectPath(from: cwd) ?? cwd
        let keywords = extractKeywords(from: visibleText).joined(separator: " ")
```

Remove the old private helper at the bottom of `ForemanMemoryStore.swift`:

```swift
-    private func projectPath(from cwd: String) -> String {
-        var url = URL(fileURLWithPath: cwd)
-        while url.path != "/" {
-            let gitDir = url.appendingPathComponent(".git")
-            if FileManager.default.fileExists(atPath: gitDir.path) {
-                return url.path
-            }
-            url.deleteLastPathComponent()
-        }
-        return cwd
-    }
```

- [ ] **Step 4: Run the project-scope tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanProjectScopeTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit Task 1**

```bash
git add macos/Sources/Features/AIForeman/ForemanProjectScope.swift macos/Sources/Features/AIForeman/ForemanMemoryStore.swift macos/Tests/Terminal/ForemanProjectScopeTests.swift
git commit -m "macos: add foreman project scope model"
```

## Task 2: Make Conversation and Routing Project-Aware

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanConversation.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanInputRouting.swift`
- Test: `macos/Tests/Terminal/ForemanProjectScopeTests.swift`
- Test: `macos/Tests/Terminal/ForemanInputRoutingTests.swift`

- [ ] **Step 1: Add failing routing tests for project-goal targets**

Append to `macos/Tests/Terminal/ForemanInputRoutingTests.swift`:

```swift
    @Test
    func projectGoalTargetUsesProjectTitleAndGoalCopy() {
        let target = ForemanChatTarget.setProjectGoal(
            projectID: "/tmp/mend",
            projectTitle: "mend"
        )

        #expect(target.title == "Set project goal")
        #expect(target.subtitle == "mend")
        #expect(target.placeholder == "What should Foreman achieve in mend?")
    }

    @Test
    func projectGoalIntentCarriesProjectIdentity() {
        let intent = ForemanInputIntent.setProjectGoal(
            projectID: "/tmp/mend",
            objective: "Support ChatGPT first."
        )

        #expect(intent == .setProjectGoal(
            projectID: "/tmp/mend",
            objective: "Support ChatGPT first."
        ))
    }
```

- [ ] **Step 2: Run the conversation and routing tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanProjectScopeTests -only-testing:GhosttyTests/ForemanInputRoutingTests
```

Expected: compile failures because `ForemanConversation` still exposes a single `goal` slot and `ForemanInputRouting` still uses `startGoal`.

- [ ] **Step 3: Replace the single goal slot with project-aware conversation state**

Modify `macos/Sources/Features/AIForeman/ForemanConversation.swift`:

```swift
@MainActor
final class ForemanConversation: ObservableObject {
    static let legacyProjectID = "__foreman_default__"
    private static let maxHiddenContextEntries = 8

    @Published var messages: [ConversationMessage] = []
    @Published private(set) var projectGoalsByProjectID: [String: ForemanProjectGoal] = [:]
    @Published private(set) var selectedProjectID: String?
    @Published var mode: AgentMode = .interactive
    @Published var isRunning: Bool = false
    @Published var status: AgentStatus = .idle
    @Published var iterationCount: Int = 0
    @Published var errorMessage: String?
    @Published var lastOverview: TerminalOverview?
    @Published var lastUnderstandings: [TerminalUnderstanding] = []
    @Published private(set) var hiddenContext: [String] = []

    let maxIterations = 20

    var goal: String? {
        currentProjectGoal?.objective
    }

    var currentProjectGoal: ForemanProjectGoal? {
        guard let selectedProjectID else { return nil }
        return projectGoalsByProjectID[selectedProjectID]
    }

    func selectProject(_ projectID: String?) {
        selectedProjectID = projectID
    }

    func projectGoal(for projectID: String) -> ForemanProjectGoal? {
        projectGoalsByProjectID[projectID]
    }

    func setProjectGoal(
        projectID: String,
        objective: String,
        mode: AgentMode = .interactive
    ) {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = projectGoalsByProjectID[projectID]
        let now = Date()
        projectGoalsByProjectID[projectID] = ForemanProjectGoal(
            id: existing?.id ?? UUID(),
            projectID: projectID,
            objective: trimmed,
            status: .active,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        selectedProjectID = projectID
        self.mode = mode
        self.isRunning = true
        self.status = .observing
        self.iterationCount = 0
        self.errorMessage = nil
        self.lastOverview = nil
        self.lastUnderstandings = []
        self.hiddenContext = []
        addMessage(role: .user, content: trimmed)
    }

    func updateProjectGoalStatus(_ status: ForemanProjectGoalStatus, for projectID: String) {
        guard var goal = projectGoalsByProjectID[projectID] else { return }
        goal.status = status
        goal.updatedAt = Date()
        projectGoalsByProjectID[projectID] = goal
    }

    func clearProjectGoal(for projectID: String) {
        projectGoalsByProjectID[projectID] = nil
        if selectedProjectID == projectID {
            selectedProjectID = nil
        }
    }

    func start(
        goal: String,
        projectID: String = Self.legacyProjectID,
        mode: AgentMode = .interactive
    ) {
        setProjectGoal(projectID: projectID, objective: goal, mode: mode)
    }

    func stop() {
        isRunning = false
        status = .idle
        lastOverview = nil
        lastUnderstandings = []
        hiddenContext = []
    }
```

Modify `macos/Sources/Features/AIForeman/ForemanInputRouting.swift`:

```swift
enum ForemanInputIntent: Equatable, Sendable {
    case setProjectGoal(projectID: String, objective: String)
    case guideForeman(String)
    case replyToWaitingAgent(
        terminalID: String,
        fingerprint: String,
        message: String
    )
    case chooseAgentOption(
        terminalID: String,
        fingerprint: String,
        payload: String
    )
    case approveForemanAction(AgentAction)
}

enum ForemanChatTarget: Equatable, Sendable {
    case replyToAgent(PendingAgentAttention, terminalTitle: String)
    case guideForeman
    case setProjectGoal(projectID: String, projectTitle: String)
    case chooseTarget([ForemanTargetOption])

    var title: String {
        switch self {
        case .replyToAgent(let attention, _):
            return "Replying to \(ForemanTargetOption(attention: attention, terminalTitle: "").agentLabel)"
        case .guideForeman:
            return "Guiding Foreman"
        case .setProjectGoal:
            return "Set project goal"
        case .chooseTarget:
            return "Choose a terminal"
        }
    }

    var subtitle: String? {
        switch self {
        case .replyToAgent(let attention, let terminalTitle):
            let option = ForemanTargetOption(attention: attention, terminalTitle: terminalTitle)
            return "\(option.label) · \(option.agentLabel)"
        case .setProjectGoal(_, let projectTitle):
            return projectTitle
        case .chooseTarget(let options):
            return "\(options.count) terminals need input"
        case .guideForeman:
            return nil
        }
    }

    var placeholder: String {
        switch self {
        case .replyToAgent(let attention, _):
            let option = ForemanTargetOption(attention: attention, terminalTitle: "")
            return "Reply to \(option.agentLabel)..."
        case .guideForeman:
            return "Guide Foreman..."
        case .setProjectGoal(_, let projectTitle):
            return "What should Foreman achieve in \(projectTitle)?"
        case .chooseTarget:
            return "Choose a terminal first..."
        }
    }
}
```

- [ ] **Step 4: Run the project-scope and routing tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanProjectScopeTests -only-testing:GhosttyTests/ForemanInputRoutingTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit Task 2**

```bash
git add macos/Sources/Features/AIForeman/ForemanConversation.swift macos/Sources/Features/AIForeman/ForemanInputRouting.swift macos/Tests/Terminal/ForemanProjectScopeTests.swift macos/Tests/Terminal/ForemanInputRoutingTests.swift
git commit -m "macos: make foreman goals project aware"
```

## Task 3: Teach the Sidebar Store About Projects and Plain `Needs direction`

**Files:**
- Modify: `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanChatView.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`

- [ ] **Step 1: Add failing store tests for project routing and guidance gating**

Append to `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`:

```swift
    @MainActor
    @Test
    func routeChatMessageSetsGoalForSelectedProjectWhenNoProjectGoalExists() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("mend")
        try fileManager.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true, attributes: nil)

        let store = ForemanSidebarStore()
        store.applySnapshots([
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "Kimi Code",
                cwd: repo.appendingPathComponent("docs").path,
                isFocused: true,
                visibleText: "What should I do next?",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "kimi"
            )
        ])
        store.selectTerminal("term-1")

        let resolution = store.routeChatMessage("Support ChatGPT first.")

        #expect(resolution == .intent(.setProjectGoal(
            projectID: repo.path,
            objective: "Support ChatGPT first."
        )))
        #expect(store.chatTarget == .setProjectGoal(
            projectID: repo.path,
            projectTitle: "mend"
        ))
    }

    @MainActor
    @Test
    func applySnapshotsBuildsProjectRegistryFromTerminalCwds() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mend = root.appendingPathComponent("mend")
        try fileManager.createDirectory(at: mend.appendingPathComponent(".git"), withIntermediateDirectories: true, attributes: nil)

        let store = ForemanSidebarStore()
        store.applySnapshots([
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "Kimi",
                cwd: mend.appendingPathComponent("src").path,
                isFocused: true,
                visibleText: "Reading README",
                recentScrollbackLines: [],
                lastInputPreview: nil
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-2",
                windowID: "win-1",
                tabID: "tab-2",
                title: "Codex",
                cwd: mend.appendingPathComponent("tests").path,
                isFocused: false,
                visibleText: "Collecting files",
                recentScrollbackLines: [],
                lastInputPreview: nil
            )
        ])

        #expect(store.projectRegistry.projectID(forTerminalID: "term-1") == mend.path)
        #expect(store.projectRegistry.projectID(forTerminalID: "term-2") == mend.path)
        #expect(store.currentProject?.rootPath == mend.path)
    }

    @MainActor
    @Test
    func waitingTextAttentionDoesNotSupportDecisionGuidance() {
        let attention = PendingAgentAttention(
            terminalID: "term-1",
            agentIdentity: .kimi,
            interactionState: .waitingText,
            fingerprint: "fp-1",
            title: "Kimi is waiting",
            description: "Tell Kimi what to do next.",
            actions: []
        )

        #expect(attention.supportsDecisionGuidance == false)
    }

    @MainActor
    @Test
    func waitingApprovalAttentionStillSupportsDecisionGuidance() {
        let attention = PendingAgentAttention(
            terminalID: "term-1",
            agentIdentity: .claudeCode,
            interactionState: .waitingApproval,
            fingerprint: "fp-1",
            title: "Claude needs approval",
            description: "Approve the shell command.",
            actions: []
        )

        #expect(attention.supportsDecisionGuidance == true)
    }
```

- [ ] **Step 2: Run the sidebar-store tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: compile failures because the store has no project registry, no `setProjectGoal` route, and `PendingAgentAttention` has no `supportsDecisionGuidance`.

- [ ] **Step 3: Add project-aware store state and hide guidance for `waiting_text` cards**

Modify `macos/Sources/Features/AIForeman/ForemanSidebarStore.swift`:

```swift
struct PendingAgentAttention: Identifiable, Equatable, Sendable {
    var id: String { "\(terminalID)|\(fingerprint)" }

    let terminalID: String
    let agentIdentity: AgentIdentity
    let interactionState: AgentInteractionState
    let fingerprint: String
    var title: String
    var description: String
    var detail: String?
    var actions: [PendingAgentAction]
    var status: PendingAgentAttentionStatus
    var errorMessage: String?

    var supportsDecisionGuidance: Bool {
        switch interactionState {
        case .waitingText:
            return false
        case .waitingApproval, .waitingChoice, .error, .unknown, .running, .completed:
            return true
        }
    }
}

@MainActor
final class ForemanSidebarStore: ObservableObject {
    @Published private(set) var projectRegistry: ForemanProjectRegistry = .init()
    @Published private(set) var goalEditorProjectID: String?

    var currentProjectID: String? {
        if let selectedTerminalID, let projectID = projectRegistry.projectID(forTerminalID: selectedTerminalID) {
            return projectID
        }
        if let selectedProjectID = conversation.selectedProjectID {
            return selectedProjectID
        }
        if let firstPending = orderedPendingAttentions.first {
            return projectRegistry.projectID(forTerminalID: firstPending.terminalID)
        }
        return terminalRows.compactMap { projectRegistry.projectID(forTerminalID: $0.terminalID) }.first
    }

    var currentProject: ForemanProjectRecord? {
        guard let currentProjectID else { return nil }
        return projectRegistry.projectsByID[currentProjectID]
    }

    var currentProjectGoal: ForemanProjectGoal? {
        guard let currentProjectID else { return nil }
        return conversation.projectGoal(for: currentProjectID)
    }

    var chatTarget: ForemanChatTarget {
        if let goalEditorProjectID,
           let project = projectRegistry.projectsByID[goalEditorProjectID] {
            return .setProjectGoal(projectID: project.id, projectTitle: project.title)
        }

        if isForemanGuidanceSelectedForNextMessage {
            return .guideForeman
        }

        if !pendingChatTargetOptions.isEmpty {
            return .chooseTarget(pendingChatTargetOptions)
        }

        let pending = orderedPendingAttentions
        if let attention = selectedPendingAttention,
           explicitlySelectedTerminalID == selectedTerminalID || pending.count == 1 {
            return .replyToAgent(
                attention,
                terminalTitle: title(forTerminalID: attention.terminalID)
            )
        }

        if pending.count > 1 {
            return .chooseTarget(targetOptions(for: pending))
        }

        if let project = currentProject, currentProjectGoal == nil {
            return .setProjectGoal(projectID: project.id, projectTitle: project.title)
        }

        return .guideForeman
    }

    func chooseProjectGoalEditor() {
        guard let project = currentProject else { return }
        conversation.selectProject(project.id)
        goalEditorProjectID = project.id
        isForemanGuidanceSelectedForNextMessage = false
        pendingChatTargetOptions = []
    }

    func routeChatMessage(_ text: String) -> ForemanInputResolution {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        if let goalEditorProjectID {
            return .intent(.setProjectGoal(projectID: goalEditorProjectID, objective: trimmed))
        }

        if isForemanGuidanceSelectedForNextMessage {
            return .intent(.guideForeman(trimmed))
        }

        if explicitlySelectedTerminalID == selectedTerminalID,
           let attention = selectedPendingAttention {
            return .intent(.replyToWaitingAgent(
                terminalID: attention.terminalID,
                fingerprint: attention.fingerprint,
                message: trimmed
            ))
        }

        let pending = orderedPendingAttentions
        if pending.count == 1, let attention = pending.first {
            selectedTerminalID = attention.terminalID
            return .intent(.replyToWaitingAgent(
                terminalID: attention.terminalID,
                fingerprint: attention.fingerprint,
                message: trimmed
            ))
        }

        if pending.count > 1 {
            let options = pending.map {
                ForemanTargetOption(attention: $0, terminalTitle: title(forTerminalID: $0.terminalID))
            }
            pendingChatTargetOptions = options
            return .needsTarget(message: trimmed, options: options)
        }

        if let project = currentProject, currentProjectGoal == nil {
            goalEditorProjectID = project.id
            return .intent(.setProjectGoal(projectID: project.id, objective: trimmed))
        }

        return .intent(.guideForeman(trimmed))
    }

    private func syncProjects(with snapshots: [TerminalSnapshot]) {
        projectRegistry.rebuild(from: snapshots.map {
            ForemanProjectTerminalContext(
                terminalID: $0.terminalID,
                title: $0.title,
                cwd: $0.cwd
            )
        })

        if let selectedTerminalID {
            conversation.selectProject(projectRegistry.projectID(forTerminalID: selectedTerminalID))
        } else {
            conversation.selectProject(currentProjectID)
        }
    }
```

Update the end of `applySnapshots(...)` in `ForemanSidebarStore.swift` to synchronize project membership after row projection:

```swift
        terminalRows = rows
        syncProjects(with: snapshots)
```

Update `selectTerminal(_:)` and `clearChatTargetSelectionAfterSuccessfulIntent()` in `ForemanSidebarStore.swift`:

```swift
    func selectTerminal(_ terminalID: String) {
        guard terminalRows.contains(where: { $0.terminalID == terminalID }) else {
            return
        }
        selectedTerminalID = terminalID
        explicitlySelectedTerminalID = terminalID
        conversation.selectProject(projectRegistry.projectID(forTerminalID: terminalID))
        isForemanGuidanceSelectedForNextMessage = false
        goalEditorProjectID = nil
        pendingChatTargetOptions = []
    }

    private func clearChatTargetSelectionAfterSuccessfulIntent() {
        pendingChatTargetOptions = []
        goalEditorProjectID = nil
        isForemanGuidanceSelectedForNextMessage = false
    }
```

Modify `macos/Sources/Features/AIForeman/ForemanChatView.swift`:

```swift
    @ViewBuilder
    private var activeProjectGoalHeader: some View {
        if let project = store.currentProject {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title)
                        .font(.system(size: 12, weight: .semibold))
                    if let goal = store.currentProjectGoal {
                        Text(goal.objective)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("No project goal yet")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Button(store.currentProjectGoal == nil ? "Set Goal" : "Edit Goal") {
                    store.chooseProjectGoalEditor()
                }
                .controlSize(.small)
            }
        }
    }
```

Insert `activeProjectGoalHeader` above `activeTerminalAttentionCard` in the main body of `ForemanChatView`, and gate the guidance panel in `ActiveTerminalAttentionCard`:

```swift
            if attention.supportsDecisionGuidance {
                TerminalDecisionGuidancePanel(
                    guidance: guidance,
                    onGuidanceChanged: onGuidanceChanged,
                    onReevaluate: onReevaluateGuidance,
                    onExecuteRecommendation: onExecuteRecommendation,
                    onCancel: onCancelGuidance
                )
                .id(attention.id)
            }
```

- [ ] **Step 4: Run the sidebar-store tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanSidebarStoreTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit Task 3**

```bash
git add macos/Sources/Features/AIForeman/ForemanSidebarStore.swift macos/Sources/Features/AIForeman/ForemanChatView.swift macos/Tests/Terminal/ForemanSidebarStoreTests.swift
git commit -m "macos: add project-aware foreman sidebar routing"
```

## Task 4: Wire Project Goals Through AppDelegate and Agent Lifecycle

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
- Modify: `macos/Sources/Features/AIForeman/ForemanAgent.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

- [ ] **Step 1: Add failing agent tests for complete/stuck project-goal status**

Append to `macos/Tests/Terminal/ForemanAgentTests.swift`:

```swift
@Test
func declareCompleteMarksSelectedProjectGoalComplete() async throws {
    let conversation = await MainActor.run { ForemanConversation() }
    let client = ScriptedForemanClient(
        agentSteps: [
            makeAgentStepResponse(
                action: .declareComplete(summary: "Recommendation delivered."),
                thought: "The goal is complete."
            )
        ]
    )
    let agent = makeAgent(
        conversation: conversation,
        client: client,
        commandRecorder: CommandRecorder()
    )

    await agent.start(
        projectID: "/tmp/project",
        goal: "Deliver a recommendation.",
        captureSnapshots: sampleSnapshots
    )
    try await waitForStatus(.complete, in: conversation)

    let goal = await MainActor.run { conversation.projectGoal(for: "/tmp/project") }
    #expect(goal?.status == .complete)
}

@Test
func declareStuckMarksSelectedProjectGoalStuck() async throws {
    let conversation = await MainActor.run { ForemanConversation() }
    let client = ScriptedForemanClient(
        agentSteps: [
            makeAgentStepResponse(
                action: .declareStuck(reason: "Missing repository access."),
                thought: "I cannot continue safely."
            )
        ]
    )
    let agent = makeAgent(
        conversation: conversation,
        client: client,
        commandRecorder: CommandRecorder()
    )

    await agent.start(
        projectID: "/tmp/project",
        goal: "Deliver a recommendation.",
        captureSnapshots: sampleSnapshots
    )
    try await waitForStatus(.stuck, in: conversation)

    let goal = await MainActor.run { conversation.projectGoal(for: "/tmp/project") }
    #expect(goal?.status == .stuck)
}
```

- [ ] **Step 2: Run the agent tests and verify they fail**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: compile failures because `ForemanAgent.start` has no `projectID`, and the loop does not update project-goal status.

- [ ] **Step 3: Wire the new project-goal intent into AppDelegate and ForemanAgent**

Modify `macos/Sources/App/macOS/AppDelegate.swift`:

```swift
    @MainActor
    func startForemanAgent(
        projectID: String,
        goal: String,
        mode: AgentMode,
        store: ForemanSidebarStore
    ) {
        store.conversation.setProjectGoal(
            projectID: projectID,
            objective: goal,
            mode: mode
        )

        let agent = ForemanAgent(
            conversation: store.conversation,
            foremanService: foremanService,
            onSendCommand: { [weak self] terminalID, command in
                guard let self else { return false }
                return await MainActor.run {
                    self.executeSuggestedAction(terminalID: terminalID, command: command)
                    return true
                }
            },
            onStatusChange: { [weak store] status in
                await MainActor.run {
                    store?.conversation.setStatus(status)
                }
            },
            onAction: { _, _ in }
        )

        self.foremanAgent = agent
        self.foremanAgentStore = store

        Task {
            await agent.start(
                projectID: projectID,
                goal: goal,
                mode: mode,
                captureSnapshots: { [weak self] in
                    guard let self else { return [] }
                    return self.captureForemanTerminalSnapshots()
                }
            )
        }
    }

    @MainActor
    func handleForemanInputIntent(_ intent: ForemanInputIntent, store: ForemanSidebarStore) {
        switch intent {
        case .setProjectGoal(let projectID, let objective):
            startForemanAgent(projectID: projectID, goal: objective, mode: .interactive, store: store)
        case .guideForeman(let message):
            sendChatMessage(message, store: store)
        case .replyToWaitingAgent(let terminalID, let fingerprint, let message):
            guard let attention = store.pendingAttentionByTerminalID[terminalID],
                  attention.fingerprint == fingerprint else {
                let errorMessage = "That terminal state changed before the reply could be sent."
                store.chatInput = message
                store.errorMessage = errorMessage
                store.conversation.errorMessage = errorMessage
                return
            }

            let action = PendingAgentAction(
                id: "custom_reply_\(fingerprint)",
                title: "Send custom reply",
                payload: message,
                style: .primary
            )
            if executePendingAttentionAction(attention, action: action, store: store) {
                store.conversation.addMessage(role: .user, content: message, terminalID: terminalID)
            }
        case .chooseAgentOption(let terminalID, let fingerprint, let payload):
            guard let attention = store.pendingAttentionByTerminalID[terminalID],
                  attention.fingerprint == fingerprint else {
                let errorMessage = "That terminal option is no longer available."
                store.errorMessage = errorMessage
                store.conversation.errorMessage = errorMessage
                return
            }

            let action = PendingAgentAction(
                id: "selected_option_\(fingerprint)",
                title: "Send selected option",
                payload: payload,
                style: .primary
            )
            executePendingAttentionAction(attention, action: action, store: store)
        case .approveForemanAction:
            approveForemanAction()
        }
    }

    @MainActor
    func stopForemanAgent(store: ForemanSidebarStore) {
        if let projectID = store.conversation.selectedProjectID {
            store.conversation.updateProjectGoalStatus(.paused, for: projectID)
        }

        Task { [weak self] in
            await self?.foremanAgent?.stop()
            self?.foremanAgent = nil
            self?.foremanAgentStore = nil
        }
    }
```

Modify `macos/Sources/Features/AIForeman/ForemanAgent.swift`:

```swift
    func start(
        projectID: String,
        goal: String,
        mode: AgentMode = .interactive,
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot]
    ) async {
        cancelCurrentTask()
        self.captureSnapshots = captureSnapshots

        await MainActor.run {
            conversation.setProjectGoal(
                projectID: projectID,
                objective: goal,
                mode: mode
            )
        }

        await resumeLoop()
    }

    func start(
        goal: String,
        mode: AgentMode = .interactive,
        captureSnapshots: @escaping @MainActor () -> [TerminalSnapshot]
    ) async {
        await start(
            projectID: ForemanConversation.legacyProjectID,
            goal: goal,
            mode: mode,
            captureSnapshots: captureSnapshots
        )
    }
```

Update the completion and stuck branches in `ForemanAgent.handleAction(...)`:

```swift
        case .declareComplete(let summary):
            await MainActor.run {
                if let projectID = conversation.selectedProjectID {
                    conversation.updateProjectGoalStatus(.complete, for: projectID)
                }
                conversation.addMessage(
                    role: .agent,
                    content: "✅ \(summary)",
                    terminalID: messageTerminalID
                )
                conversation.setStatus(.complete)
            }
            return false

        case .declareStuck(let reason):
            await MainActor.run {
                if let projectID = conversation.selectedProjectID {
                    conversation.updateProjectGoalStatus(.stuck, for: projectID)
                }
                conversation.addMessage(
                    role: .agent,
                    content: "⚠️ I'm stuck: \(reason)",
                    terminalID: messageTerminalID
                )
                conversation.setStatus(.stuck)
            }
            return false
```

- [ ] **Step 4: Run the agent tests and verify they pass**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit Task 4**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift macos/Sources/Features/AIForeman/ForemanAgent.swift macos/Tests/Terminal/ForemanAgentTests.swift
git commit -m "macos: wire foreman project goal lifecycle"
```

## Task 5: Run Focused Verification and Manual Project Routing Checks

**Files:**
- Modify: none
- Test: `macos/Tests/Terminal/ForemanProjectScopeTests.swift`
- Test: `macos/Tests/Terminal/ForemanInputRoutingTests.swift`
- Test: `macos/Tests/Terminal/ForemanSidebarStoreTests.swift`
- Test: `macos/Tests/Terminal/ForemanAgentTests.swift`

- [ ] **Step 1: Run the focused Foreman test set**

Run:

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -only-testing:GhosttyTests/ForemanProjectScopeTests \
  -only-testing:GhosttyTests/ForemanInputRoutingTests \
  -only-testing:GhosttyTests/ForemanSidebarStoreTests \
  -only-testing:GhosttyTests/ForemanAgentTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: Build the macOS app**

Run:

```bash
macos/build.nu
```

Expected: build completes and produces `macos/build/Debug/Foreman.app`.

- [ ] **Step 3: Manually verify project-goal routing in the app**

Run:

```bash
open -a macos/build/Debug/Foreman.app
```

Verify this exact sequence:

```text
1. Open two terminals in the same repo and one terminal in a different repo.
2. Select a terminal in repo A and confirm the chat target reads "Set project goal" when repo A has no goal yet.
3. Set repo A's goal from chat and confirm the project header shows repo A plus the saved objective.
4. Trigger a waiting_text attention card and confirm the card still shows action buttons + reply input, but no guidance / reevaluate panel.
5. Trigger a waiting_approval or waiting_choice card and confirm the guidance panel still appears there.
6. Stop Foreman and confirm the selected project's goal remains visible instead of disappearing with the terminal card.
7. Switch to a terminal in repo B and confirm the goal editor targets repo B instead of reusing repo A's goal.
```

Expected: the reply-card interaction remains local to the terminal, while goal editing follows the selected project.

- [ ] **Step 4: Commit the verification checkpoint**

```bash
git add -A
git commit -m "test: verify foreman project goal runtime"
```

## Self-Review

- Spec coverage:
  - Project registry and cwd-based project assignment: Task 1 and Task 3.
  - Project-scoped goal runtime with active/paused/complete/stuck states: Task 1, Task 2, and Task 4.
  - `Needs direction` stays a plain reply flow: Task 3.
  - Goal control separate from reply cards: Task 3 and Task 5.
  - Codex-style runtime backbone without replacing terminal attention: Task 2, Task 3, and Task 4.

- Placeholder scan:
  - No `TODO`, `TBD`, or “implement later” placeholders remain.
  - Every task contains exact file paths, concrete code, commands, and expected outcomes.

- Type consistency:
  - The new goal-setting intent is `ForemanInputIntent.setProjectGoal(projectID:objective:)` everywhere.
  - The chat target for goal editing is `ForemanChatTarget.setProjectGoal(projectID:projectTitle:)` everywhere.
  - Project state is always keyed by `projectID == rootPath`.
