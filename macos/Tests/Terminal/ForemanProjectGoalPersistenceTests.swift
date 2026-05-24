import Foundation
import Testing
@testable import Ghostty

struct ForemanProjectGoalPersistenceTests {
    @Test
    func projectGoalCompletionRoundTripsAcrossRuntimeRehydration() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("ghostty")
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")

        try fileManager.createDirectory(
            at: repo.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: root)
        }

        let completedAt = Date(timeIntervalSince1970: 1_700)
        let evidence = "term-1 succeeded: Goal evaluator shipped and focused tests passed."

        let store = ForemanMemoryStore(dbPath: dbURL)
        let runtime = ForemanProjectGoalRuntime(
            memoryStore: store,
            loadPersistedGoals: true
        )
        await runtime.saveGoal("Ship the Foreman goal evaluator.", for: repo.path)
        await runtime.recordEvaluation(
            .init(
                progress: .completed,
                evidenceSnapshot: evidence,
                evaluatedAt: completedAt
            ),
            for: repo.path
        )
        await store.close()

        let rehydratedStore = ForemanMemoryStore(dbPath: dbURL)
        let rehydratedRuntime = ForemanProjectGoalRuntime(
            memoryStore: rehydratedStore,
            loadPersistedGoals: true
        )
        let restoredGoal = await rehydratedRuntime.goal(for: repo.path)

        #expect(restoredGoal?.goalText == "Ship the Foreman goal evaluator.")
        #expect(restoredGoal?.status == .completed)
        #expect(restoredGoal?.completedAt == completedAt)
        #expect(restoredGoal?.lastEvaluatedAt == completedAt)
        #expect(restoredGoal?.lastEvidenceSnapshot == evidence)
    }

    @Test
    func unrelatedProjectsKeepIndependentStatusAndEvidenceSnapshots() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ghostty = root.appendingPathComponent("ghostty")
        let mend = root.appendingPathComponent("mend")
        let dbURL = root.appendingPathComponent("foreman-memory.sqlite3")

        try fileManager.createDirectory(
            at: ghostty.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: mend.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: root)
        }

        let store = ForemanMemoryStore(dbPath: dbURL)
        let runtime = ForemanProjectGoalRuntime(
            memoryStore: store,
            loadPersistedGoals: true
        )
        await runtime.saveGoal("Ship the goal evaluator.", for: ghostty.path)
        await runtime.saveGoal("Debug the pending-attention card.", for: mend.path)
        await runtime.recordEvaluation(
            .init(
                progress: .completed,
                evidenceSnapshot: "ghostty-term succeeded: evaluator landed cleanly.",
                evaluatedAt: Date(timeIntervalSince1970: 100)
            ),
            for: ghostty.path
        )
        await runtime.recordEvaluation(
            .init(
                progress: .needsHumanInput(.blocked),
                evidenceSnapshot: "mend-term is waiting for approval before it can continue.",
                evaluatedAt: Date(timeIntervalSince1970: 200)
            ),
            for: mend.path
        )
        await store.close()

        let rehydratedStore = ForemanMemoryStore(dbPath: dbURL)
        let rehydratedRuntime = ForemanProjectGoalRuntime(
            memoryStore: rehydratedStore,
            loadPersistedGoals: true
        )
        let restoredGhosttyGoal = await rehydratedRuntime.goal(for: ghostty.path)
        let restoredMendGoal = await rehydratedRuntime.goal(for: mend.path)

        #expect(restoredGhosttyGoal?.status == .completed)
        #expect(restoredGhosttyGoal?.lastEvidenceSnapshot == "ghostty-term succeeded: evaluator landed cleanly.")
        #expect(restoredGhosttyGoal?.completedAt == Date(timeIntervalSince1970: 100))

        #expect(restoredMendGoal?.status == .active)
        #expect(restoredMendGoal?.completedAt == nil)
        #expect(restoredMendGoal?.lastEvaluatedAt == Date(timeIntervalSince1970: 200))
        #expect(restoredMendGoal?.lastEvidenceSnapshot == "mend-term is waiting for approval before it can continue.")
    }
}
