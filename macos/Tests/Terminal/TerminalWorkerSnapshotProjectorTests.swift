import Foundation
import Testing
@testable import Ghostty

struct TerminalWorkerSnapshotProjectorTests {
    @Test
    func kimiPlanModeProjectsPlanningFlagAndChoiceRequest() throws {
        let projector = TerminalWorkerSnapshotProjector()
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/repo",
            isFocused: true,
            visibleText: "Which direction should I take?",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
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
        let projectedSnapshot = try #require(projected)

        #expect(projectedSnapshot.state.runtimeFlags == [.planning])
        #expect(projectedSnapshot.request?.id == "req-12")
        #expect(projectedSnapshot.state.attention == .choiceRequired)
        #expect(projectedSnapshot.workerSessionID == "kimi-session-12")
        #expect(projectedSnapshot.revision == 12)
    }
}
