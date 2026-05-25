import Combine
import Foundation

@MainActor
final class ForemanRuntimeState: ObservableObject {
    @Published var lastOverview: TerminalOverview?
    @Published var lastUnderstandings: [TerminalUnderstanding] = []
    @Published var lastWorkerSnapshots: [String: TerminalWorkerSnapshot] = [:]
    @Published private(set) var activeProjectGoal: ForemanProjectGoal?

    func resetForNewConversation() {
        resetObservedTerminalContext()
        activeProjectGoal = nil
    }

    func resetObservedTerminalContext() {
        lastOverview = nil
        lastUnderstandings = []
        lastWorkerSnapshots = [:]
    }

    func updateTerminalContext(
        overview: TerminalOverview,
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot] = [:]
    ) {
        lastOverview = overview
        lastUnderstandings = understandings
        lastWorkerSnapshots = workerSnapshots
    }

    func setActiveProjectGoal(_ goal: ForemanProjectGoal?) {
        activeProjectGoal = goal
    }

    func effectiveGoal(fallbackGoal: String?) -> String? {
        if let activeProjectGoal, activeProjectGoal.status.isActive {
            return activeProjectGoal.objective
        }

        return fallbackGoal
    }
}
