import Testing
@testable import Ghostty

struct ForemanSidebarStoreTests {
    @MainActor
    @Test
    func showingSidebarRefreshesAgentReadiness() {
        let key = "GHOSTTY_FOREMAN_TEST_FORCE_AGENT_READINESS"
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, "installed", 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }

        let store = ForemanSidebarStore()

        #expect(store.agentReadiness.isEmpty)

        store.showSidebar()

        #expect(store.isSidebarVisible == true)
        #expect(store.agentReadiness.map(\.0) == [.claudeCode, .codex, .kimi])
        #expect(store.agentReadiness.allSatisfy { $0.1 == .installed(loginStatus: .loggedIn) })
    }

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
    func runtimeStateDrivesRollupAndCompletedGoalSuppression() {
        let runtimeState = ForemanRuntimeState()
        let conversation = ForemanConversation(runtimeState: runtimeState)
        let store = ForemanSidebarStore(
            conversation: conversation,
            runtimeState: runtimeState
        )
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "tests",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "Tests failed.",
                recentScrollbackLines: [],
                lastInputPreview: "xcodebuild test"
            ),
        ]
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .failed,
            shortExplanation: "Tests failed.",
            lastMeaningfulEvent: "Tests failed.",
            importantDetails: ["Tests failed."],
            suggestedNextActions: [
                .init(
                    title: "Rerun tests",
                    command: "xcodebuild test",
                    reason: "Verify the fix.",
                    isRecommended: true
                ),
            ]
        )
        let overview = TerminalOverview(
            summary: "term-1 failed and needs a rerun.",
            changedTerminalIDs: ["term-1"],
            primaryTerminalID: "term-1"
        )

        store.applySnapshots(
            snapshots,
            understandingsByTerminalID: ["term-1": understanding]
        )

        #expect(store.runtimeState === runtimeState)
        #expect(store.terminalRows[0].suggestedActions.map(\.title) == ["Rerun tests"])

        runtimeState.updateTerminalContext(
            overview: overview,
            understandings: [understanding]
        )
        runtimeState.setActiveProjectGoal(
            ForemanProjectGoal(
                projectID: "/tmp/project",
                objective: "Ship this cleanly.",
                status: .completed
            )
        )

        #expect(store.rollupStatusText == "term-1 failed and needs a rerun.")
        #expect(store.terminalRows[0].suggestedActions.isEmpty)

        runtimeState.setActiveProjectGoal(
            ForemanProjectGoal(
                projectID: "/tmp/project",
                objective: "Ship this cleanly.",
                status: .active
            )
        )

        #expect(store.terminalRows[0].suggestedActions.map(\.title) == ["Rerun tests"])
    }

    @MainActor
    @Test
    func visibleConversationMessagesKeepsGlobalMessagesAndSelectedTerminalThread() {
        let conversation = ForemanConversation()
        conversation.addMessage(role: .user, content: "Coordinate these terminals.")
        conversation.addMessage(role: .agent, content: "Kimi is waiting.", terminalID: "term-1")
        conversation.addMessage(role: .agent, content: "Claude is waiting.", terminalID: "term-2")
        let store = ForemanSidebarStore(
            selectedTerminalID: "term-1",
            conversation: conversation
        )

        #expect(store.visibleConversationMessages.map(\.content) == [
            "Coordinate these terminals.",
            "Kimi is waiting.",
        ])

        store.selectedTerminalID = "term-2"

        #expect(store.visibleConversationMessages.map(\.content) == [
            "Coordinate these terminals.",
            "Claude is waiting.",
        ])

        store.selectedTerminalID = nil

        #expect(store.visibleConversationMessages.map(\.content) == [
            "Coordinate these terminals.",
        ])
    }

    @MainActor
    @Test
    func visibleConversationMessagesFollowResolvedReplyTarget() {
        let conversation = ForemanConversation()
        conversation.addMessage(role: .user, content: "Coordinate these terminals.")
        conversation.addMessage(role: .agent, content: "Codex is waiting.", terminalID: "term-1")
        conversation.addMessage(role: .agent, content: "Build finished.", terminalID: "term-3")
        let store = ForemanSidebarStore(
            terminalRows: [
                .init(
                    terminalID: "term-1",
                    title: "term-1",
                    cwd: "/tmp/project",
                    state: "waiting",
                    summary: "Waiting for input.",
                    agentIdentity: "codex",
                    agentInteractionState: "waiting_text",
                    supportLevel: "first_class",
                    evidenceSummary: "wire_signal",
                    isFocused: false,
                    suggestedActions: [],
                    pendingAttention: nil,
                    agentContextType: "waitingText",
                    agentContextTitle: "Needs a reply",
                    agentContextDescription: "Answer the active prompt.",
                    agentContextDetail: nil,
                    agentContextOptions: nil
                ),
                .init(
                    terminalID: "term-3",
                    title: "term-3",
                    cwd: "/tmp/project",
                    state: "running",
                    summary: "Healthy.",
                    agentIdentity: nil,
                    agentInteractionState: nil,
                    supportLevel: nil,
                    evidenceSummary: nil,
                    isFocused: true,
                    suggestedActions: [],
                    pendingAttention: nil,
                    agentContextType: nil,
                    agentContextTitle: nil,
                    agentContextDescription: nil,
                    agentContextDetail: nil
                ),
            ],
            selectedTerminalID: "term-3",
            conversation: conversation
        )
        store.upsertPendingAttention(
            makePendingAttention(terminalID: "term-1", fingerprint: "fp-1")
        )

        #expect(store.resolvedSidebarTarget == .terminalReply(terminalID: "term-1", fingerprint: "fp-1"))
        #expect(store.visibleConversationMessages.map(\.content) == [
            "Coordinate these terminals.",
            "Codex is waiting.",
        ])
    }

    @MainActor
    @Test
    func selectingProjectTargetOverridesAmbiguousWaitingThreads() {
        let conversation = ForemanConversation()
        conversation.addMessage(role: .user, content: "Coordinate these terminals.")
        conversation.addMessage(role: .agent, content: "Codex is waiting.", terminalID: "term-1")
        conversation.addMessage(role: .agent, content: "Claude is waiting.", terminalID: "term-2")
        let store = ForemanSidebarStore(
            terminalRows: [
                .init(
                    terminalID: "term-1",
                    title: "term-1",
                    cwd: "/tmp/project",
                    state: "waiting",
                    summary: "Waiting for input.",
                    agentIdentity: "codex",
                    agentInteractionState: "waiting_text",
                    supportLevel: "first_class",
                    evidenceSummary: "wire_signal",
                    isFocused: false,
                    suggestedActions: [],
                    pendingAttention: nil,
                    agentContextType: "waitingText",
                    agentContextTitle: "Needs a reply",
                    agentContextDescription: "Answer the active prompt.",
                    agentContextDetail: nil,
                    agentContextOptions: nil
                ),
                .init(
                    terminalID: "term-2",
                    title: "term-2",
                    cwd: "/tmp/project",
                    state: "waiting",
                    summary: "Waiting for input.",
                    agentIdentity: "claude_code",
                    agentInteractionState: "waiting_choice",
                    supportLevel: "first_class",
                    evidenceSummary: "wire_signal",
                    isFocused: false,
                    suggestedActions: [],
                    pendingAttention: nil,
                    agentContextType: "waitingChoice",
                    agentContextTitle: "Needs a choice",
                    agentContextDescription: "Choose the next step.",
                    agentContextDetail: nil,
                    agentContextOptions: nil
                ),
                .init(
                    terminalID: "term-3",
                    title: "term-3",
                    cwd: "/tmp/project",
                    state: "running",
                    summary: "Healthy.",
                    agentIdentity: nil,
                    agentInteractionState: nil,
                    supportLevel: nil,
                    evidenceSummary: nil,
                    isFocused: true,
                    suggestedActions: [],
                    pendingAttention: nil,
                    agentContextType: nil,
                    agentContextTitle: nil,
                    agentContextDescription: nil,
                    agentContextDetail: nil
                ),
            ],
            selectedTerminalID: "term-3",
            conversation: conversation
        )
        store.upsertPendingAttention(
            makePendingAttention(terminalID: "term-1", fingerprint: "fp-1")
        )
        store.upsertPendingAttention(
            makePendingAttention(terminalID: "term-2", fingerprint: "fp-2")
        )

        #expect(store.selectedTerminalID == "term-3")
        #expect(store.resolvedTargetOptions.count == 3)

        store.selectSidebarTargetOption(.project(title: "Guide Foreman"))

        #expect(store.resolvedSidebarTarget == .project(projectID: "/tmp/project"))
        #expect(store.visibleConversationMessages.map(\.content) == [
            "Coordinate these terminals.",
        ])
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

    @MainActor
    @Test
    func upsertingPendingAttentionSelectsTerminalAndShowsSidebar() {
        let store = ForemanSidebarStore()
        let attention = makePendingAttention(terminalID: "term-2")

        store.upsertPendingAttention(attention)

        #expect(store.pendingAttentionByTerminalID["term-2"] == attention)
        #expect(store.selectedTerminalID == "term-2")
        #expect(store.isSidebarVisible == true)
    }

    @MainActor
    @Test
    func applySnapshotsProjectsPendingAttentionIntoRows() {
        let store = ForemanSidebarStore()
        let attention = makePendingAttention(terminalID: "term-1")
        store.upsertPendingAttention(attention)

        store.applySnapshots([
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "Claude",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "Do you want to continue?",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude"
            )
        ])

        #expect(store.terminalRows.count == 1)
        #expect(store.terminalRows[0].pendingAttention == attention)
    }

    @MainActor
    @Test
    func applySnapshotsClearsPendingAttentionWhenAgentNoLongerNeedsAttention() {
        let store = ForemanSidebarStore()
        let attention = makePendingAttention(terminalID: "term-1")
        store.upsertPendingAttention(attention)
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Claude",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Working...",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "claude"
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .running,
            shortExplanation: "Claude is working.",
            lastMeaningfulEvent: "Working...",
            importantDetails: ["Working..."],
            suggestedNextActions: [],
            agentIdentity: .claudeCode,
            agentInteractionState: .running
        )

        store.applySnapshots(
            [snapshot],
            understandingsByTerminalID: ["term-1": understanding]
        )

        #expect(store.pendingAttentionByTerminalID["term-1"] == nil)
        #expect(store.terminalRows[0].pendingAttention == nil)
    }

    @MainActor
    @Test
    func resolvingPendingAttentionClearsDictionaryAndRow() {
        let store = ForemanSidebarStore()
        let attention = makePendingAttention(terminalID: "term-1", fingerprint: "fp-1")
        store.applySnapshots([
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "Claude",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "Do you want to continue?",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude"
            )
        ])
        store.upsertPendingAttention(attention)

        store.resolvePendingAttention(terminalID: "term-1", fingerprint: "fp-1")

        #expect(store.pendingAttentionByTerminalID["term-1"] == nil)
        #expect(store.terminalRows[0].pendingAttention == nil)
    }

    @MainActor
    @Test
    func failedPendingAttentionKeepsErrorMessageInDictionaryAndRow() {
        let store = ForemanSidebarStore()
        let attention = makePendingAttention(terminalID: "term-1", fingerprint: "fp-1")
        store.applySnapshots([
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "Claude",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "Do you want to continue?",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "claude"
            )
        ])
        store.upsertPendingAttention(attention)

        store.markPendingAttentionSending(terminalID: "term-1", fingerprint: "fp-1")
        store.markPendingAttentionFailed(
            terminalID: "term-1",
            fingerprint: "fp-1",
            errorMessage: "Terminal was no longer available."
        )

        let storedAttention = try! #require(store.pendingAttentionByTerminalID["term-1"])
        let rowAttention = try! #require(store.terminalRows[0].pendingAttention)
        #expect(storedAttention.status == .failed)
        #expect(storedAttention.errorMessage == "Terminal was no longer available.")
        #expect(rowAttention.status == .failed)
        #expect(rowAttention.errorMessage == "Terminal was no longer available.")
    }

    @MainActor
    @Test
    func executingPendingAttentionActionForwardsAttentionAndAction() {
        let store = ForemanSidebarStore()
        let action = PendingAgentAction(
            id: "continue",
            title: "Continue",
            payload: "1",
            style: .primary
        )
        let attention = makePendingAttention(terminalID: "term-1", actions: [action])
        var forwardedAttention: PendingAgentAttention?
        var forwardedAction: PendingAgentAction?
        store.onExecutePendingAttentionAction = { attention, action in
            forwardedAttention = attention
            forwardedAction = action
        }
        store.upsertPendingAttention(attention)

        store.executePendingAttentionAction(terminalID: "term-1", actionID: "continue")

        #expect(forwardedAttention == attention)
        #expect(forwardedAction == action)
    }

    @MainActor
    @Test
    func executingStalePendingAttentionActionDoesNotForward() {
        let store = ForemanSidebarStore()
        let currentAction = PendingAgentAction(
            id: "current",
            title: "Current",
            payload: "2",
            style: .primary
        )
        let staleAction = PendingAgentAction(
            id: "stale",
            title: "Stale",
            payload: "1",
            style: .primary
        )
        let currentAttention = makePendingAttention(
            terminalID: "term-1",
            fingerprint: "current-fp",
            actions: [currentAction]
        )
        let staleAttention = makePendingAttention(
            terminalID: "term-1",
            fingerprint: "stale-fp",
            actions: [staleAction]
        )
        var forwardedAction: PendingAgentAction?
        store.onExecutePendingAttentionAction = { _, action in
            forwardedAction = action
        }
        store.upsertPendingAttention(currentAttention)

        store.executePendingAttentionAction(staleAttention, action: staleAction)

        #expect(forwardedAction == nil)
    }

    @MainActor
    @Test
    func applySnapshotsDropsStalePendingAttentionWhenWorkerFingerprintChanges() {
        let store = ForemanSidebarStore()
        store.upsertPendingAttention(
            makePendingAttention(
                terminalID: "term-1",
                fingerprint: "codex-session-40|40|req-40",
                agentIdentity: .codex,
                interactionState: .waitingText
            )
        )

        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Should I preserve the API?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "codex"
        )
        let workerSnapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-41",
            revision: 41,
            observedAt: Date(timeIntervalSince1970: 1_748_222_222),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .blocked,
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
            importantDetails: workerSnapshot.state.details,
            suggestedNextActions: [
                .init(
                    title: "Preserve the API",
                    command: nil,
                    reason: "Lowest migration risk.",
                    isRecommended: true
                ),
            ],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            workerSnapshot: workerSnapshot
        )

        store.applySnapshots([snapshot], understandingsByTerminalID: ["term-1": understanding])

        #expect(store.pendingAttentionByTerminalID["term-1"] == nil)
        #expect(store.terminalRows.first?.pendingAttention == nil)
    }

    @MainActor
    @Test
    func applySnapshotsExposesSelectedWorkerSnapshotAndSuggestionProvenance() {
        let store = ForemanSidebarStore(selectedTerminalID: "term-1")
        let snapshot = makeWorkerTerminalSnapshot(terminalID: "term-1", title: "Codex")
        let workerSnapshot = makeWorkerSnapshot(
            terminalID: "term-1",
            workerSessionID: "codex-session-41",
            revision: 41,
            workerGoal: "stabilize the API",
            identity: .codex,
            attention: .replyRequired,
            summary: "Codex is waiting for a reply.",
            details: ["Asked whether the API should stay stable."],
            runtimeFlags: [.planning],
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
        let understanding = makeWorkerUnderstanding(
            terminalID: "term-1",
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "Should I preserve the API?",
            agentIdentity: .codex,
            interactionState: .waitingText,
            workerSnapshot: workerSnapshot
        )

        store.applySnapshots([snapshot], understandingsByTerminalID: ["term-1": understanding])

        #expect(store.selectedTerminalWorkerSnapshot == workerSnapshot)
        #expect(store.selectedTerminalSuggestedWorkerAction?.title == "Preserve the API")
        #expect(store.selectedTerminalSuggestionProvenance == "Suggested by Codex")
        #expect(store.terminalRows.first?.suggestedActions.first?.authoritativeFingerprint == workerSnapshot.attentionFingerprint)
        #expect(store.terminalRows.first?.suggestedActions.first?.authoritativePayload == "Preserve the current API and adapt the internals.")
        #expect(
            store.selectedTerminalPlanningNotice ==
            "This worker is in plan mode. Review the plan before continuing."
        )
    }

    @MainActor
    @Test
    func selectedWorkerSuggestionIgnoresRecommendedEntriesFromOlderRequests() {
        let store = ForemanSidebarStore(selectedTerminalID: "term-1")
        let snapshot = makeWorkerTerminalSnapshot(terminalID: "term-1", title: "Codex")
        let workerSnapshot = makeWorkerSnapshot(
            terminalID: "term-1",
            workerSessionID: "codex-session-55",
            revision: 55,
            workerGoal: "answer the latest question",
            identity: .codex,
            attention: .replyRequired,
            summary: "Codex is waiting for a reply.",
            details: ["A stale recommendation should not win."],
            request: .init(
                id: "req-current",
                kind: .reply,
                prompt: "What should I do next?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "stale",
                    kind: .reply,
                    title: "Follow the old plan",
                    payload: .text("Use the previous migration path."),
                    rationale: "This suggestion belongs to the old request.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-old"
                ),
                .init(
                    id: "current",
                    kind: .reply,
                    title: "Answer the current question",
                    payload: .text("Use the current migration path."),
                    rationale: "This matches the live request.",
                    recommended: false,
                    execution: .manualOnly,
                    requestID: "req-current"
                ),
            ]
        )
        let understanding = makeWorkerUnderstanding(
            terminalID: "term-1",
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "What should I do next?",
            agentIdentity: .codex,
            interactionState: .waitingText,
            workerSnapshot: workerSnapshot
        )

        store.applySnapshots([snapshot], understandingsByTerminalID: ["term-1": understanding])

        #expect(store.selectedTerminalSuggestedWorkerAction?.id == "current")
        #expect(store.selectedTerminalSuggestedWorkerAction?.title == "Answer the current question")
    }

    @MainActor
    @Test
    func terminalRowsIgnoreWorkerSuggestionsFromOlderRequests() {
        let store = ForemanSidebarStore(selectedTerminalID: "term-1")
        let snapshot = makeWorkerTerminalSnapshot(terminalID: "term-1", title: "Codex")
        let workerSnapshot = makeWorkerSnapshot(
            terminalID: "term-1",
            workerSessionID: "codex-session-55",
            revision: 55,
            workerGoal: "answer the latest question",
            identity: .codex,
            attention: .replyRequired,
            summary: "Codex is waiting for a reply.",
            details: ["A stale recommendation should not be rendered in the row."],
            request: .init(
                id: "req-current",
                kind: .reply,
                prompt: "What should I do next?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "stale",
                    kind: .reply,
                    title: "Follow the old plan",
                    payload: .text("Use the previous migration path."),
                    rationale: "This suggestion belongs to the old request.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-old"
                ),
                .init(
                    id: "current",
                    kind: .reply,
                    title: "Answer the current question",
                    payload: .text("Use the current migration path."),
                    rationale: "This matches the live request.",
                    recommended: false,
                    execution: .manualOnly,
                    requestID: "req-current"
                ),
            ]
        )
        let understanding = makeWorkerUnderstanding(
            terminalID: "term-1",
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "What should I do next?",
            agentIdentity: .codex,
            interactionState: .waitingText,
            workerSnapshot: workerSnapshot
        )

        store.applySnapshots([snapshot], understandingsByTerminalID: ["term-1": understanding])

        #expect(store.terminalRows.first?.suggestedActions.map(\.title) == ["Answer the current question"])
        #expect(store.terminalRows.first?.suggestedActions.first?.authoritativePayload == "Use the current migration path.")
    }

    @MainActor
    @Test
    func attentionSummaryTextNamesMultipleWaitingWorkers() {
        let store = ForemanSidebarStore()
        let replySnapshot = makeWorkerSnapshot(
            terminalID: "term-1",
            workerSessionID: "codex-session-41",
            revision: 41,
            workerGoal: "stabilize the API",
            identity: .codex,
            attention: .replyRequired,
            summary: "Codex is waiting for a reply.",
            details: ["Reply needed before the API work can continue."],
            request: .init(
                id: "req-41",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            )
        )
        let approvalSnapshot = makeWorkerSnapshot(
            terminalID: "term-2",
            workerSessionID: "kimi-session-9",
            revision: 9,
            workerGoal: "verify the deployment step",
            identity: .kimi,
            attention: .approvalRequired,
            summary: "Kimi needs approval.",
            details: ["Approval is required before running the command."],
            request: .init(
                id: "req-9",
                kind: .approval,
                prompt: "Approve the proposed command?",
                options: []
            )
        )
        let understandingsByTerminalID = [
            "term-1": makeWorkerUnderstanding(
                terminalID: "term-1",
                shortExplanation: "Codex is waiting for a reply.",
                lastMeaningfulEvent: "Reply needed.",
                agentIdentity: .codex,
                interactionState: .waitingText,
                workerSnapshot: replySnapshot
            ),
            "term-2": makeWorkerUnderstanding(
                terminalID: "term-2",
                shortExplanation: "Kimi needs approval.",
                lastMeaningfulEvent: "Approval needed.",
                agentIdentity: .kimi,
                interactionState: .waitingApproval,
                workerSnapshot: approvalSnapshot
            ),
        ]

        store.applySnapshots(
            [
                makeWorkerTerminalSnapshot(terminalID: "term-1", title: "Codex", isFocused: true),
                makeWorkerTerminalSnapshot(terminalID: "term-2", title: "Kimi", isFocused: false),
            ],
            understandingsByTerminalID: understandingsByTerminalID
        )

        #expect(
            store.attentionSummaryText ==
            "2 terminals need attention: term-1 reply required; term-2 approval required."
        )
    }

    @MainActor
    @Test
    func sendChatMessageRoutesTerminalRepliesThroughUnifiedIntent() {
        let store = ForemanSidebarStore(selectedTerminalID: "term-1")
        store.applySnapshots([
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "Codex",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "What should I do here?",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex"
            ),
        ])
        store.upsertPendingAttention(
            makePendingAttention(terminalID: "term-1", fingerprint: "fp-1")
        )

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        store.sendChatMessage("Continue with the current plan.")

        #expect(
            dispatchedIntent ==
            .sendTerminalReply(
                terminalID: "term-1",
                fingerprint: "fp-1",
                message: "Continue with the current plan."
            )
        )
    }

    @MainActor
    @Test
    func sendChatMessageRoutesAuthoritativeWorkerRepliesWithoutPendingAttention() {
        let store = ForemanSidebarStore(selectedTerminalID: "term-1")
        let snapshot = makeWorkerTerminalSnapshot(terminalID: "term-1", title: "Codex")
        let workerSnapshot = makeWorkerSnapshot(
            terminalID: "term-1",
            workerSessionID: "codex-session-41",
            revision: 41,
            workerGoal: "stabilize the API",
            identity: .codex,
            attention: .replyRequired,
            summary: "Codex is waiting for a reply.",
            details: ["Asked whether the API should stay stable."],
            request: .init(
                id: "req-41",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            )
        )
        let understanding = makeWorkerUnderstanding(
            terminalID: "term-1",
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "Should I preserve the API?",
            agentIdentity: .codex,
            interactionState: .waitingText,
            workerSnapshot: workerSnapshot
        )

        store.applySnapshots([snapshot], understandingsByTerminalID: ["term-1": understanding])

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        store.sendChatMessage("Preserve the current API and adapt the internals.")

        #expect(
            dispatchedIntent ==
            .sendTerminalReply(
                terminalID: "term-1",
                fingerprint: workerSnapshot.attentionFingerprint,
                message: "Preserve the current API and adapt the internals."
            )
        )
    }

    @MainActor
    @Test
    func executeSuggestionRoutesInformationalActionsThroughUnifiedIntent() {
        let store = ForemanSidebarStore()
        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        store.executeSuggestion(
            terminalID: "term-1",
            action: .init(
                title: "Ask Foreman to summarize the options",
                command: nil,
                reason: "Useful when the menu is noisy.",
                isRecommended: false
            )
        )

        #expect(
            dispatchedIntent ==
            .guideForeman(
                "Ask Foreman to summarize the options for terminal term-1. Useful when the menu is noisy."
            )
        )
    }

    @MainActor
    @Test
    func executeSuggestionRetargetsSelectionBeforeGuidanceDispatch() {
        let store = ForemanSidebarStore(selectedTerminalID: "term-1")
        store.applySnapshots([
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "Term 1",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex"
            ),
            TerminalSnapshot.makePreview(
                terminalID: "term-2",
                windowID: "win-1",
                tabID: "tab-2",
                title: "Term 2",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex"
            ),
        ])

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        store.executeSuggestion(
            terminalID: "term-2",
            action: .init(
                title: "Inspect the available choices",
                command: nil,
                reason: "The worker needs direction.",
                isRecommended: true
            )
        )

        #expect(store.selectedTerminalID == "term-2")
        #expect(
            dispatchedIntent ==
            .guideForeman(
                "Inspect the available choices for terminal Term 2. The worker needs direction."
            )
        )
    }

    @MainActor
    @Test
    func executeSuggestionRoutesAuthoritativeWorkerReplyWithoutPendingAttention() {
        let store = ForemanSidebarStore()
        let snapshot = makeWorkerTerminalSnapshot(terminalID: "term-1", title: "Codex", isFocused: true)
        let workerSnapshot = makeWorkerSnapshot(
            terminalID: "term-1",
            workerSessionID: "codex-session-41",
            revision: 41,
            workerGoal: "stabilize the API",
            identity: .codex,
            attention: .replyRequired,
            summary: "Codex is waiting for a reply.",
            details: ["Asked whether the API should stay stable."],
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
        let understanding = makeWorkerUnderstanding(
            terminalID: "term-1",
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "Should I preserve the API?",
            agentIdentity: .codex,
            interactionState: .waitingText,
            workerSnapshot: workerSnapshot
        )
        store.applySnapshots([snapshot], understandingsByTerminalID: ["term-1": understanding])

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        let action = try! #require(store.terminalRows.first?.suggestedActions.first)
        store.executeSuggestion(terminalID: "term-1", action: action)

        #expect(
            dispatchedIntent ==
            .sendTerminalReply(
                terminalID: "term-1",
                fingerprint: workerSnapshot.attentionFingerprint,
                message: "Preserve the current API and adapt the internals."
            )
        )
    }

    @MainActor
    @Test
    func authoritativeWorkerFallbackSuggestionPreservesGuidancePromptAndFingerprint() {
        let store = ForemanSidebarStore()
        let workerSnapshot = makeWorkerSnapshot(
            terminalID: "term-1",
            workerSessionID: "codex-session-52",
            revision: 52,
            workerGoal: "choose a migration path",
            identity: .codex,
            attention: .replyRequired,
            summary: "Codex needs direction.",
            details: ["Asked how to proceed."],
            request: .init(
                id: "req-52",
                kind: .reply,
                prompt: "What should I do here?",
                options: []
            ),
            suggestions: []
        )
        let understanding = makeWorkerUnderstanding(
            terminalID: "term-1",
            shortExplanation: "Codex needs direction.",
            lastMeaningfulEvent: "What should I do here?",
            agentIdentity: .codex,
            interactionState: .waitingText,
            workerSnapshot: workerSnapshot,
            suggestedNextActions: [
                .init(
                    title: "Reply to the agent",
                    command: nil,
                    reason: "What should I do here?",
                    isRecommended: true
                ),
            ]
        )
        store.applySnapshots(
            [makeWorkerTerminalSnapshot(terminalID: "term-1", title: "Codex", isFocused: true)],
            understandingsByTerminalID: ["term-1": understanding]
        )

        let action = try! #require(store.terminalRows.first?.suggestedActions.first)

        #expect(action.authoritativeFingerprint == workerSnapshot.attentionFingerprint)
        #expect(action.guidancePrompt == "What should I do here?")
    }

    @MainActor
    @Test
    func executeSuggestionRoutesMatchingPendingAttentionActionWhenAvailable() {
        let store = ForemanSidebarStore()
        store.upsertPendingAttention(
            PendingAgentAttention(
                terminalID: "term-1",
                agentIdentity: .codex,
                interactionState: .waitingText,
                fingerprint: "fp-1",
                title: "Suggested reply",
                description: "Should I preserve the API?",
                detail: nil,
                actions: [
                    .init(
                        id: "preserve-api",
                        title: "Preserve the API",
                        payload: "Preserve the current API and adapt the internals.",
                        style: .primary
                    ),
                ]
            )
        )

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        store.executeSuggestion(
            terminalID: "term-1",
            action: .init(
                title: "Preserve the API",
                command: nil,
                reason: "Lowest migration risk.",
                isRecommended: true
            )
        )

        #expect(
            dispatchedIntent ==
            .sendPendingAttentionAction(
                terminalID: "term-1",
                fingerprint: "fp-1",
                payload: "Preserve the current API and adapt the internals."
            )
        )
    }

    @MainActor
    @Test
    func executePendingAttentionActionRoutesThroughUnifiedIntentWhenConfigured() {
        let store = ForemanSidebarStore()
        let action = PendingAgentAction(
            id: "continue",
            title: "Continue",
            payload: "1",
            style: .primary
        )
        let attention = makePendingAttention(
            terminalID: "term-1",
            fingerprint: "fp-1",
            actions: [action]
        )
        store.upsertPendingAttention(attention)

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }

        store.executePendingAttentionAction(terminalID: "term-1", actionID: "continue")

        #expect(
            dispatchedIntent ==
            .sendPendingAttentionAction(
                terminalID: "term-1",
                fingerprint: "fp-1",
                payload: "1"
            )
        )
    }

    @MainActor
    @Test
    func completedGoalSuppressesPendingAttentionActionRouting() {
        let conversation = ForemanConversation()
        conversation.runtimeState.setActiveProjectGoal(
            ForemanProjectGoal(
                projectID: "/tmp/project",
                objective: "Ship the sidebar fix",
                status: .completed
            )
        )
        let store = ForemanSidebarStore(conversation: conversation)
        let action = PendingAgentAction(
            id: "continue",
            title: "Continue",
            payload: "1",
            style: .primary
        )
        let attention = makePendingAttention(
            terminalID: "term-1",
            fingerprint: "fp-1",
            actions: [action]
        )

        var dispatchedIntent: ForemanSidebarIntent?
        store.onDispatchSidebarIntent = { intent in
            dispatchedIntent = intent
        }
        store.upsertPendingAttention(attention)

        store.executePendingAttentionAction(terminalID: "term-1", actionID: "continue")

        #expect(dispatchedIntent == nil)
        #expect(
            store.errorMessage ==
            "The saved project goal is complete. Reopen or extend it before dispatching more work."
        )
    }

    private func makePendingAttention(
        terminalID: String,
        fingerprint: String = "fp-1",
        agentIdentity: AgentIdentity = .claudeCode,
        interactionState: AgentInteractionState = .waitingChoice,
        actions: [PendingAgentAction] = [
            .init(
                id: "continue",
                title: "Continue",
                payload: "1",
                style: .primary
            )
        ]
    ) -> PendingAgentAttention {
        PendingAgentAttention(
            terminalID: terminalID,
            agentIdentity: agentIdentity,
            interactionState: interactionState,
            fingerprint: fingerprint,
            title: "Claude needs a choice",
            description: "Select the continue option.",
            detail: "1. Continue\n2. Stop",
            actions: actions
        )
    }

    private func makeWorkerTerminalSnapshot(
        terminalID: String,
        title: String,
        isFocused: Bool = true
    ) -> TerminalSnapshot {
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-\(terminalID)",
            title: title,
            cwd: "/tmp/project",
            isFocused: isFocused,
            visibleText: "Worker output",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: title.lowercased()
        )
    }

    private func makeWorkerSnapshot(
        terminalID: String,
        workerSessionID: String,
        revision: Int,
        workerGoal: String?,
        identity: AgentIdentity,
        attention: TerminalWorkerAttention,
        summary: String,
        details: [String],
        runtimeFlags: [TerminalWorkerRuntimeFlag] = [],
        request: TerminalWorkerSnapshot.Request?,
        suggestions: [TerminalWorkerSnapshot.Suggestion] = []
    ) -> TerminalWorkerSnapshot {
        TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: terminalID,
            workerSessionID: workerSessionID,
            revision: revision,
            observedAt: Date(timeIntervalSince1970: 1_748_222_222),
            ttlMilliseconds: 15_000,
            workerGoal: workerGoal,
            agent: .init(identity: identity),
            state: .init(
                lifecycle: .blocked,
                attention: attention,
                summary: summary,
                details: details,
                runtimeFlags: runtimeFlags
            ),
            request: request,
            suggestions: suggestions
        )
    }

    private func makeWorkerUnderstanding(
        terminalID: String,
        shortExplanation: String,
        lastMeaningfulEvent: String,
        agentIdentity: AgentIdentity,
        interactionState: AgentInteractionState,
        workerSnapshot: TerminalWorkerSnapshot,
        suggestedNextActions: [TerminalSuggestedAction] = []
    ) -> TerminalUnderstanding {
        TerminalUnderstanding.preview(
            terminalID: terminalID,
            state: .waiting,
            shortExplanation: shortExplanation,
            lastMeaningfulEvent: lastMeaningfulEvent,
            importantDetails: workerSnapshot.state.details,
            suggestedNextActions: suggestedNextActions,
            agentIdentity: agentIdentity,
            agentInteractionState: interactionState,
            supportLevel: .firstClass,
            workerSnapshot: workerSnapshot
        )
    }

}
