import Foundation
import Testing
@testable import Ghostty

struct ForemanProjectScopeTests {
    @Test
    func projectPathResolverFindsNearestGitRoot() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("ghostty")
        let nested = repo.appendingPathComponent("macos/Sources")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: repo.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: root)
        }

        let projectPath = ForemanProjectPathResolver.projectPath(from: nested.path)

        #expect(projectPath == repo.path)
    }

    @Test
    func goalRuntimeStoresIndependentGoalsPerProject() async {
        let runtime = ForemanProjectGoalRuntime()

        await runtime.saveGoal(
            "Support ChatGPT first without breaking other agents.",
            for: "/tmp/mend"
        )
        await runtime.saveGoal(
            "Build a project goal runtime for Foreman.",
            for: "/tmp/ghostty"
        )

        let mendGoal = await runtime.goal(for: "/tmp/mend")
        let ghosttyGoal = await runtime.goal(for: "/tmp/ghostty")

        #expect(mendGoal?.objective == "Support ChatGPT first without breaking other agents.")
        #expect(ghosttyGoal?.objective == "Build a project goal runtime for Foreman.")
        #expect(mendGoal?.projectID == "/tmp/mend")
        #expect(ghosttyGoal?.projectID == "/tmp/ghostty")
    }

    @Test
    func goalRuntimeResolvesSavedGoalFromTerminalSnapshots() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("ghostty")
        let nested = repo.appendingPathComponent("macos/Tests")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: repo.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: root)
        }

        let runtime = ForemanProjectGoalRuntime()
        await runtime.saveGoal("Investigate the failing terminal tests.", for: repo.path)

        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "term-1",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: nested.path,
                isFocused: true,
                visibleText: "$ ",
                recentScrollbackLines: [],
                lastInputPreview: nil
            ),
        ]

        let resolvedGoal = await runtime.goal(forTerminalID: "term-1", in: snapshots)

        #expect(resolvedGoal?.projectID == repo.path)
        #expect(resolvedGoal?.objective == "Investigate the failing terminal tests.")
    }
}
