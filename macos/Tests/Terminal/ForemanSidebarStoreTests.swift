import Testing
@testable import Ghostty

struct ForemanSidebarStoreTests {
    @MainActor
    @Test
    func sidebarStartsHiddenUntilUserOpensIt() {
        let store = ForemanSidebarStore()

        #expect(store.isSidebarVisible == false)

        store.showSidebar()
        #expect(store.isSidebarVisible == true)

        store.hideSidebar()
        #expect(store.isSidebarVisible == false)
    }

    @MainActor
    @Test
    func applyingSummariesUsesAISummaryAndKeepsSnapshotMetadata() {
        let store = ForemanSidebarStore()
        let snapshots = [
            TerminalSnapshot(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "api tests",
                cwd: "/tmp/project",
                isFocused: true,
                captureMode: "shell",
                visibleText: "raw shell text",
                recentScrollback: "line one\nline two",
                lastInputPreview: "pnpm test",
                runtime: .init(
                    foregroundProcessID: nil,
                    foregroundProcessName: nil,
                    cursorIsAtPrompt: false,
                    usingAlternateScreen: false
                ),
                signals: .init(
                    likelyWaitingForInput: false,
                    likelyLongRunning: false,
                    likelyErrorState: true,
                    likelyTUI: false
                )
            )
        ]
        let summariesByTerminalID = [
            "term-1": TerminalSummary(
                terminalID: "term-1",
                summary: "Blocked on auth middleware assertion.",
                state: "blocked",
                confidence: 0.94,
                needsUserAttention: true,
                suggestedNextStep: "Rerun the targeted auth test."
            )
        ]

        store.applySnapshots(snapshots, summariesByTerminalID: summariesByTerminalID)

        #expect(store.terminalRows.count == 1)
        #expect(store.terminalRows[0].terminalID == "term-1")
        #expect(store.terminalRows[0].title == "api tests")
        #expect(store.terminalRows[0].cwd == "/tmp/project")
        #expect(store.terminalRows[0].isFocused == true)
        #expect(store.terminalRows[0].state == "blocked")
        #expect(store.terminalRows[0].summary == "Blocked on auth middleware assertion.")
        #expect(store.selectedTerminalID == "term-1")
    }

    @MainActor
    @Test
    func applySnapshotsUsesStructuredUnderstandingStateAndExplanation() {
        let store = ForemanSidebarStore()
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "api",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "error: module not found",
                recentScrollbackLines: [],
                lastInputPreview: "npm test"
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-2",
                windowID: "win-1",
                tabID: "tab-2",
                title: "server",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "Server listening on http://localhost:3000",
                recentScrollbackLines: [],
                lastInputPreview: "npm run dev"
            ),
        ]
        let summariesByTerminalID = [
            "term-1": TerminalSummary(
                terminalID: "term-1",
                summary: "Tests failed because a module is missing.",
                state: "failed",
                confidence: 0.93,
                needsUserAttention: true,
                suggestedNextStep: "Install or fix the missing module import."
            ),
            "term-2": TerminalSummary(
                terminalID: "term-2",
                summary: "The dev server is healthy.",
                state: "running",
                confidence: 0.91,
                needsUserAttention: false,
                suggestedNextStep: "Continue watching for requests."
            ),
        ]

        store.applySnapshots(snapshots, summariesByTerminalID: summariesByTerminalID)

        #expect(store.terminalRows.count == 2)
        #expect(store.terminalRows[0].state == "failed")
        #expect(store.terminalRows[0].summary == "Tests failed because a module is missing.")
        #expect(store.terminalRows[1].state == "running")
        #expect(store.terminalRows[1].summary == "The dev server is healthy.")
    }

    @MainActor
    @Test
    func applySnapshotsCarriesAgentMetadataIntoTerminalRows() {
        let store = ForemanSidebarStore()
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "Claude Code",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "What do you want to do?",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude"
            )
        ]
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Claude Code is waiting for your selection.",
            lastMeaningfulEvent: "What do you want to do?",
            importantDetails: [],
            suggestedNextActions: [],
            agentIdentity: .claudeCode,
            agentInteractionState: .waitingChoice,
            supportLevel: .firstClass,
            evidence: [
                .init(source: .screenHeuristic, detail: "Detected numbered menu", confidence: 0.86)
            ]
        )

        store.applySnapshots(
            snapshots,
            understandingsByTerminalID: ["term-1": understanding]
        )

        #expect(store.terminalRows[0].agentIdentity == "claude_code")
        #expect(store.terminalRows[0].agentInteractionState == "waiting_choice")
        #expect(store.terminalRows[0].supportLevel == "first_class")
        #expect(store.terminalRows[0].evidenceSummary == "screen_heuristic")
    }

    @MainActor
    @Test
    func storeBuildsVisibleRowsAndSelectsNextPendingDraft() {
        let store = ForemanSidebarStore.preview
        store.dispatchQueue = [
            .init(terminalID: "term-1", message: "first", state: .pending),
            .init(terminalID: "term-2", message: "second", state: .pending)
        ]

        let next = store.sendAndAdvance(currentTerminalID: "term-1")

        #expect(store.dispatchQueue[0].state == .sent)
        #expect(next == "term-2")
        #expect(store.selectedTerminalID == "term-2")
    }

    @MainActor
    @Test
    func updatingDraftMessageEditsPendingQueueItem() {
        let store = ForemanSidebarStore.preview
        let itemID = try! #require(store.dispatchQueue.first?.id)

        store.updateDraftMessage(itemID: itemID, message: "Ask for a concise blocker update.")

        #expect(store.dispatchQueue[0].message == "Ask for a concise blocker update.")
    }

    @MainActor
    @Test
    func updatingDraftMessageLeavesSentQueueItemUnchanged() {
        let store = ForemanSidebarStore.preview
        let sentItemID = try! #require(store.dispatchQueue.last?.id)
        store.dispatchQueue[1].state = .sent

        store.updateDraftMessage(itemID: sentItemID, message: "Do not overwrite sent copy.")

        #expect(store.dispatchQueue[1].message == "Post a short progress update and keep running.")
    }

    @MainActor
    @Test
    func applyingDispatchPlanReplacesQueueAndSelectsFirstDraft() {
        let store = ForemanSidebarStore.preview

        store.applyDispatchPlan(
            DispatchPlan(
                planSummary: "One terminal needs a retry.",
                drafts: [
                    .init(
                        terminalID: "term-2",
                        reason: "Blocked run",
                        message: "Rerun the targeted test and report what changed."
                    )
                ]
            ),
            validTerminalIDs: ["term-1", "term-2"]
        )

        #expect(store.dispatchQueue.count == 1)
        #expect(store.dispatchQueue[0].terminalID == "term-2")
        #expect(store.dispatchQueue[0].message == "Rerun the targeted test and report what changed.")
        #expect(store.dispatchQueue[0].state == .pending)
        #expect(store.selectedTerminalID == "term-2")
    }

    @MainActor
    @Test
    func applyingDispatchPlanDropsUnknownTerminalDraftsAndExplainsWhy() {
        let store = ForemanSidebarStore.preview

        store.applyDispatchPlan(
            DispatchPlan(
                planSummary: "Two terminals need input.",
                drafts: [
                    .init(
                        terminalID: "term-2",
                        reason: "Blocked run",
                        message: "Rerun the targeted test and report what changed."
                    ),
                    .init(
                        terminalID: "term-99",
                        reason: "Hallucinated target",
                        message: "This should not stay in the queue."
                    )
                ]
            ),
            validTerminalIDs: ["term-1", "term-2"]
        )

        #expect(store.dispatchQueue.count == 1)
        #expect(store.dispatchQueue[0].terminalID == "term-2")
        #expect(store.errorMessage == "Skipped 1 draft for a terminal that is no longer available.")
        #expect(store.selectedTerminalID == "term-2")
    }

    @MainActor
    @Test
    func sendAndAdvanceAppendsActivityLogEntry() {
        let store = ForemanSidebarStore.preview
        store.dispatchQueue = [
            .init(terminalID: "term-1", message: "first", state: .pending),
            .init(terminalID: "term-2", message: "second", state: .pending)
        ]

        _ = store.sendAndAdvance(currentTerminalID: "term-1")

        #expect(store.activityLog.count == 1)
        #expect(store.activityLog[0].terminalID == "term-1")
        #expect(store.activityLog[0].message == "first")
        #expect(store.activityLog[0].state == .sent)
    }

    @MainActor
    @Test
    func skipAndAdvanceAppendsSkippedActivityLogEntry() {
        let store = ForemanSidebarStore.preview
        store.dispatchQueue = [
            .init(terminalID: "term-1", message: "first", state: .pending)
        ]

        _ = store.skipAndAdvance(currentTerminalID: "term-1")

        #expect(store.activityLog.count == 1)
        #expect(store.activityLog[0].terminalID == "term-1")
        #expect(store.activityLog[0].state == .skipped)
    }

    @MainActor
    @Test
    func activityLogTrimsToMaxEntries() {
        let store = ForemanSidebarStore()
        for i in 0..<55 {
            store.activityLog.append(
                DispatchActivityLogEntry(
                    terminalID: "term-\(i)",
                    message: "msg-\(i)",
                    state: .sent
                )
            )
        }

        store.dispatchQueue = [
            .init(terminalID: "term-extra", message: "extra", state: .pending)
        ]
        _ = store.sendAndAdvance(currentTerminalID: "term-extra")

        #expect(store.activityLog.count == 50)
        #expect(store.activityLog.last?.terminalID == "term-extra")
    }

    @MainActor
    @Test
    func clearActivityLogRemovesAllEntries() {
        let store = ForemanSidebarStore.preview
        store.dispatchQueue = [
            .init(terminalID: "term-1", message: "first", state: .pending)
        ]
        _ = store.sendAndAdvance(currentTerminalID: "term-1")
        #expect(store.activityLog.count == 1)

        store.clearActivityLog()

        #expect(store.activityLog.isEmpty)
    }

    @MainActor
    @Test
    func sendAndAdvanceSetsLastActionMessage() {
        let store = ForemanSidebarStore.preview
        store.dispatchQueue = [
            .init(terminalID: "term-1", message: "first", state: .pending)
        ]

        _ = store.sendAndAdvance(currentTerminalID: "term-1")

        #expect(store.lastActionMessage == "Sent to term-1.")
    }

    @MainActor
    @Test
    func skipAndAdvanceSetsLastActionMessage() {
        let store = ForemanSidebarStore.preview
        store.dispatchQueue = [
            .init(terminalID: "term-1", message: "first", state: .pending)
        ]

        _ = store.skipAndAdvance(currentTerminalID: "term-1")

        #expect(store.lastActionMessage == "Skipped term-1.")
    }

    @MainActor
    @Test
    func clearLastActionMessageRemovesIt() {
        let store = ForemanSidebarStore.preview
        store.dispatchQueue = [
            .init(terminalID: "term-1", message: "first", state: .pending)
        ]
        _ = store.sendAndAdvance(currentTerminalID: "term-1")
        #expect(store.lastActionMessage != nil)

        store.clearLastActionMessage()

        #expect(store.lastActionMessage == nil)
    }

    @MainActor
    @Test
    func applySnapshotsPrefersTerminalUnderstandingOverSummary() {
        let store = ForemanSidebarStore()
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "api",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "error: module not found",
                recentScrollbackLines: [],
                lastInputPreview: "npm test"
            )
        ]
        let summariesByTerminalID = [
            "term-1": TerminalSummary(
                terminalID: "term-1",
                summary: "Old summary from LLM.",
                state: "blocked",
                confidence: 0.93,
                needsUserAttention: true,
                suggestedNextStep: "Fix it."
            )
        ]
        let understandingsByTerminalID = [
            "term-1": TerminalUnderstanding(
                terminalID: "term-1",
                title: "api",
                cwd: "/tmp/project",
                state: .failed,
                agentIdentity: .none,
                agentInteractionState: .unknown,
                supportLevel: .genericFallback,
                lastMeaningfulEvent: "npm test failed with module not found",
                shortExplanation: "The terminal failed: npm test failed with module not found",
                importantDetails: ["error: module not found"],
                evidence: [],
                suggestedNextActions: [
                    .init(title: "Install missing module", command: "npm install", reason: "Missing dependency", isRecommended: true)
                ]
            )
        ]

        store.applySnapshots(snapshots, summariesByTerminalID: summariesByTerminalID, understandingsByTerminalID: understandingsByTerminalID)

        #expect(store.terminalRows.count == 1)
        #expect(store.terminalRows[0].state == "failed")
        #expect(store.terminalRows[0].summary == "The terminal failed: npm test failed with module not found")
        #expect(store.terminalRows[0].suggestedActions.count == 1)
        #expect(store.terminalRows[0].suggestedActions[0].title == "Install missing module")
    }

    @MainActor
    @Test
    func applySnapshotsFallsBackToSummaryWhenNoUnderstanding() {
        let store = ForemanSidebarStore()
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "api",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "error: module not found",
                recentScrollbackLines: [],
                lastInputPreview: "npm test"
            )
        ]
        let summariesByTerminalID = [
            "term-1": TerminalSummary(
                terminalID: "term-1",
                summary: "Tests failed because a module is missing.",
                state: "failed",
                confidence: 0.93,
                needsUserAttention: true,
                suggestedNextStep: "Install or fix the missing module import."
            )
        ]

        store.applySnapshots(snapshots, summariesByTerminalID: summariesByTerminalID)

        #expect(store.terminalRows.count == 1)
        #expect(store.terminalRows[0].state == "failed")
        #expect(store.terminalRows[0].summary == "Tests failed because a module is missing.")
        #expect(store.terminalRows[0].suggestedActions.isEmpty)
    }
}
