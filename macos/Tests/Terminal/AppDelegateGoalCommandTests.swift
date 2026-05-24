import AppKit
import Testing
@testable import Ghostty

@Suite(.serialized)
struct AppDelegateGoalCommandTests {
    @MainActor
    @Test
    func goalCommandsPersistAndUpdateConversationState() async throws {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")
        let projectID = "/tmp/ghostty-goal-command-\(UUID().uuidString)"
        let conversation = ForemanConversation()
        let placeholderGoal = ForemanProjectGoal(
            projectID: projectID,
            objective: "Bootstrap the project goal."
        )
        conversation.setActiveProjectGoal(placeholderGoal)
        let store = ForemanSidebarStore(conversation: conversation)
        appDelegate.setForemanProjectGoalRuntimeForTests(makePersistedGoalRuntime(dbURL: dbURL))

        defer {
            conversation.setActiveProjectGoal(placeholderGoal)
            appDelegate.setForemanProjectGoalRuntimeForTests(
                ForemanProjectGoalRuntime(loadPersistedGoals: true)
            )
            try? fileManager.removeItem(at: root)
        }

        appDelegate.sendChatMessage("/goal set Ship the final goal-runtime hardening slice.", store: store)

        try await waitForGoalCommand {
            await MainActor.run {
                store.conversation.activeProjectGoal?.goalText == "Ship the final goal-runtime hardening slice."
            }
        }

        let savedGoal = await makePersistedGoalRuntime(dbURL: dbURL).goal(for: projectID)
        #expect(savedGoal?.goalText == "Ship the final goal-runtime hardening slice.")
        #expect(savedGoal?.status == .active)

        appDelegate.sendChatMessage("/goal complete", store: store)

        try await waitForGoalCommand {
            await MainActor.run {
                store.conversation.activeProjectGoal?.status == .completed
            }
        }

        let completedGoal = await makePersistedGoalRuntime(dbURL: dbURL).goal(for: projectID)
        #expect(completedGoal?.status == .completed)
        #expect(completedGoal?.lastEvidenceSnapshot == "Marked complete from the Foreman sidebar.")

        appDelegate.sendChatMessage("/goal clear", store: store)

        try await waitForGoalCommand {
            await MainActor.run {
                store.conversation.activeProjectGoal == nil
            }
        }

        let clearedGoal = await makePersistedGoalRuntime(dbURL: dbURL).goal(for: projectID)
        #expect(clearedGoal == nil)
        #expect(await MainActor.run { store.conversation.status } == .idle)
    }

    @MainActor
    @Test
    func goalReopenWorksFromRehydratedCompletedGoalState() async throws {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")
        let projectID = "/tmp/ghostty-goal-rehydrate-\(UUID().uuidString)"
        let setupConversation = ForemanConversation()
        let setupGoal = ForemanProjectGoal(projectID: projectID, objective: "Seed a completed goal.")
        setupConversation.setActiveProjectGoal(setupGoal)
        let setupStore = ForemanSidebarStore(conversation: setupConversation)
        appDelegate.setForemanProjectGoalRuntimeForTests(makePersistedGoalRuntime(dbURL: dbURL))

        defer {
            setupConversation.setActiveProjectGoal(setupGoal)
            appDelegate.setForemanProjectGoalRuntimeForTests(
                ForemanProjectGoalRuntime(loadPersistedGoals: true)
            )
            try? fileManager.removeItem(at: root)
        }

        appDelegate.sendChatMessage("/goal set Verify the rehydrated goal command path.", store: setupStore)
        try await waitForGoalCommand {
            await MainActor.run {
                setupStore.conversation.activeProjectGoal?.goalText == "Verify the rehydrated goal command path."
            }
        }

        appDelegate.sendChatMessage("/goal complete", store: setupStore)
        try await waitForGoalCommand {
            await MainActor.run {
                setupStore.conversation.activeProjectGoal?.status == .completed
            }
        }

        let restoredGoal = try #require(await makePersistedGoalRuntime(dbURL: dbURL).goal(for: projectID))
        #expect(restoredGoal.status == .completed)

        let reopenedConversation = ForemanConversation()
        reopenedConversation.setActiveProjectGoal(restoredGoal)
        let reopenedStore = ForemanSidebarStore(conversation: reopenedConversation)

        appDelegate.sendChatMessage("/goal reopen", store: reopenedStore)

        try await waitForGoalCommand(
            failureContext: {
                let persistedGoal = await makePersistedGoalRuntime(dbURL: dbURL).goal(for: projectID)
                return await MainActor.run {
                    let activeStatus = reopenedStore.conversation.activeProjectGoal?.status
                    let lastMessage = reopenedStore.conversation.messages.last?.content ?? "<none>"
                    let errorMessage = reopenedStore.conversation.errorMessage ?? "<none>"
                    return """
                    activeStatus=\(String(describing: activeStatus)) \
                    persistedStatus=\(String(describing: persistedGoal?.status)) \
                    errorMessage=\(errorMessage) \
                    lastMessage=\(lastMessage)
                    """
                }
            }
        ) {
            await MainActor.run {
                reopenedStore.conversation.activeProjectGoal?.status == .active
            }
        }

        let reopenedGoal = await makePersistedGoalRuntime(dbURL: dbURL).goal(for: projectID)
        #expect(reopenedGoal?.status == .active)
        #expect(reopenedGoal?.lastEvidenceSnapshot == "Reopened from the Foreman sidebar.")
    }

    @MainActor
    @Test
    func completedGoalRehydrationSuppressesRowActionsUntilReopen() async throws {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")
        let projectID = "/tmp/ghostty-goal-suppression-\(UUID().uuidString)"
        let setupConversation = ForemanConversation()
        let setupGoal = ForemanProjectGoal(projectID: projectID, objective: "Seed a completed goal.")
        setupConversation.setActiveProjectGoal(setupGoal)
        let setupStore = ForemanSidebarStore(conversation: setupConversation)
        appDelegate.setForemanProjectGoalRuntimeForTests(makePersistedGoalRuntime(dbURL: dbURL))

        defer {
            setupConversation.setActiveProjectGoal(setupGoal)
            appDelegate.setForemanProjectGoalRuntimeForTests(
                ForemanProjectGoalRuntime(loadPersistedGoals: true)
            )
            try? fileManager.removeItem(at: root)
        }

        appDelegate.sendChatMessage("/goal set Verify completed-goal row suppression.", store: setupStore)
        try await waitForGoalCommand {
            await MainActor.run {
                setupStore.conversation.activeProjectGoal?.goalText == "Verify completed-goal row suppression."
            }
        }

        appDelegate.sendChatMessage("/goal complete", store: setupStore)
        try await waitForGoalCommand {
            await MainActor.run {
                setupStore.conversation.activeProjectGoal?.status == .completed
            }
        }

        let restoredGoal = try #require(await makePersistedGoalRuntime(dbURL: dbURL).goal(for: projectID))
        let restoredConversation = ForemanConversation()
        restoredConversation.setActiveProjectGoal(restoredGoal)
        let restoredStore = ForemanSidebarStore(conversation: restoredConversation)

        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "tests",
                cwd: projectID,
                isFocused: true,
                visibleText: "Tests failed.",
                recentScrollbackLines: [],
                lastInputPreview: "xcodebuild test"
            ),
        ]
        let understandings = [
            "term-1": TerminalUnderstanding.preview(
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
            ),
        ]

        restoredStore.applySnapshots(
            snapshots,
            understandingsByTerminalID: understandings
        )

        #expect(restoredStore.terminalRows.count == 1)
        #expect(restoredStore.terminalRows[0].suggestedActions.isEmpty)

        appDelegate.sendChatMessage("/goal reopen", store: restoredStore)
        try await waitForGoalCommand {
            await MainActor.run {
                restoredStore.conversation.activeProjectGoal?.status == .active
            }
        }

        restoredStore.applySnapshots(
            snapshots,
            understandingsByTerminalID: understandings
        )

        #expect(restoredStore.terminalRows[0].suggestedActions.map(\.title) == ["Rerun tests"])
    }
}

private func makePersistedGoalRuntime(dbURL: URL) -> ForemanProjectGoalRuntime {
    ForemanProjectGoalRuntime(
        memoryStore: ForemanMemoryStore(dbPath: dbURL),
        loadPersistedGoals: true
    )
}

private func waitForGoalCommand(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    failureContext: (@Sendable () async -> String)? = nil,
    _ condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    let failureSuffix: String
    if let failureContext {
        failureSuffix = await failureContext()
    } else {
        failureSuffix = "no additional context"
    }

    Issue.record("Timed out waiting for Foreman goal command state. \(failureSuffix)")
    throw CancellationError()
}
