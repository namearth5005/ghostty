import Foundation

enum ForemanProjectGoalStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case complete
    case stuck

    var isActive: Bool {
        self == .active
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
}

actor ForemanProjectGoalRuntime {
    private var goalsByProjectID: [String: ForemanProjectGoal] = [:]

    func saveGoal(
        _ objective: String,
        for projectID: String,
        status: ForemanProjectGoalStatus = .active
    ) {
        let normalizedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectID.isEmpty, !normalizedObjective.isEmpty else { return }

        if var existing = goalsByProjectID[normalizedProjectID] {
            existing.objective = normalizedObjective
            existing.status = status
            existing.updatedAt = Date()
            goalsByProjectID[normalizedProjectID] = existing
        } else {
            goalsByProjectID[normalizedProjectID] = ForemanProjectGoal(
                projectID: normalizedProjectID,
                objective: normalizedObjective,
                status: status
            )
        }
    }

    func goal(for projectID: String) -> ForemanProjectGoal? {
        goalsByProjectID[projectID]
    }

    func activeGoal(for projectID: String) -> ForemanProjectGoal? {
        guard let goal = goalsByProjectID[projectID], goal.status.isActive else {
            return nil
        }

        return goal
    }

    func goal(forTerminalID terminalID: String, in terminals: [TerminalSnapshot]) -> ForemanProjectGoal? {
        guard let projectID = projectID(forTerminalID: terminalID, in: terminals) else {
            return nil
        }

        return activeGoal(for: projectID)
    }

    func projectID(forTerminalID terminalID: String, in terminals: [TerminalSnapshot]) -> String? {
        guard let snapshot = terminals.first(where: { $0.terminalID == terminalID }) else {
            return nil
        }

        return ForemanProjectPathResolver.projectPath(from: snapshot.cwd)
    }
}
