import Foundation

enum ForemanProjectGoalStatus: Equatable, Sendable {
    case active
    case paused
    case completed
}

extension ForemanProjectGoalStatus: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "active":
            self = .active
        case "paused":
            self = .paused
        case "complete", "completed":
            self = .completed
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown ForemanProjectGoalStatus: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let rawValue: String
        switch self {
        case .active:
            rawValue = "active"
        case .paused:
            rawValue = "paused"
        case .completed:
            rawValue = "completed"
        }
        try container.encode(rawValue)
    }
}

extension ForemanProjectGoalStatus {
    var isActive: Bool {
        self == .active
    }

    var suppressesRecommendations: Bool {
        self == .completed
    }
}

enum ForemanProjectGoalHumanInputKind: String, Codable, Equatable, Sendable {
    case blocked
    case uncertain
}

enum ForemanProjectGoalProgress: Equatable, Sendable {
    case inProgress
    case completed
    case needsHumanInput(ForemanProjectGoalHumanInputKind)
}

struct ForemanProjectGoalEvaluation: Equatable, Sendable {
    let progress: ForemanProjectGoalProgress
    let evidenceSnapshot: String
    let evaluatedAt: Date
}

enum ForemanProjectGoalRecommendationOutcome: Equatable, Sendable {
    case agentAction(AgentAction)
    case replyDraft(AgentReplyDraftSuggestion)
}

struct ForemanProjectGoal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let projectID: String
    var goalText: String
    var status: ForemanProjectGoalStatus
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var lastEvaluatedAt: Date?
    var lastEvidenceSnapshot: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case goalText
        case objective
        case status
        case createdAt
        case updatedAt
        case completedAt
        case lastEvaluatedAt
        case lastEvidenceSnapshot
    }

    init(
        id: UUID = UUID(),
        projectID: String,
        objective: String,
        status: ForemanProjectGoalStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        lastEvaluatedAt: Date? = nil,
        lastEvidenceSnapshot: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.goalText = objective
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.lastEvaluatedAt = lastEvaluatedAt
        self.lastEvidenceSnapshot = lastEvidenceSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .projectID)
        goalText =
            try container.decodeIfPresent(String.self, forKey: .goalText) ??
            container.decode(String.self, forKey: .objective)
        status = try container.decode(ForemanProjectGoalStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        lastEvaluatedAt = try container.decodeIfPresent(Date.self, forKey: .lastEvaluatedAt)
        lastEvidenceSnapshot = try container.decodeIfPresent(String.self, forKey: .lastEvidenceSnapshot)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(goalText, forKey: .goalText)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(lastEvaluatedAt, forKey: .lastEvaluatedAt)
        try container.encodeIfPresent(lastEvidenceSnapshot, forKey: .lastEvidenceSnapshot)
    }

    var objective: String {
        get { goalText }
        set { goalText = newValue }
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

struct ForemanProjectGoalEvaluator {
    func evaluate(
        goal: ForemanProjectGoal,
        projectID: String,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding],
        recommendationOutcome: ForemanProjectGoalRecommendationOutcome? = nil,
        now: Date = Date()
    ) -> ForemanProjectGoalEvaluation {
        if let recommendationEvaluation = evaluateRecommendationOutcome(
            recommendationOutcome,
            now: now
        ) {
            return recommendationEvaluation
        }

        let relevantUnderstandings = projectUnderstandings(
            for: projectID,
            terminals: terminals,
            understandings: understandings
        )

        if let blockedUnderstanding = relevantUnderstandings.first(where: Self.isBlocked) {
            return ForemanProjectGoalEvaluation(
                progress: .needsHumanInput(.blocked),
                evidenceSnapshot: blockedEvidence(for: blockedUnderstanding),
                evaluatedAt: now
            )
        }

        if let uncertainUnderstanding = relevantUnderstandings.first(where: Self.isUncertain) {
            return ForemanProjectGoalEvaluation(
                progress: .needsHumanInput(.uncertain),
                evidenceSnapshot: uncertainEvidence(for: uncertainUnderstanding),
                evaluatedAt: now
            )
        }

        let hasCompletionSignal = relevantUnderstandings.contains(where: Self.hasCompletionSignal)
        let hasOngoingWork = relevantUnderstandings.contains(where: Self.hasOngoingWork)

        if hasCompletionSignal && !hasOngoingWork {
            return ForemanProjectGoalEvaluation(
                progress: .completed,
                evidenceSnapshot: completionEvidence(
                    goal: goal,
                    understandings: relevantUnderstandings
                ),
                evaluatedAt: now
            )
        }

        if let inProgressUnderstanding = relevantUnderstandings.first {
            return ForemanProjectGoalEvaluation(
                progress: .inProgress,
                evidenceSnapshot: inProgressEvidence(for: inProgressUnderstanding),
                evaluatedAt: now
            )
        }

        return ForemanProjectGoalEvaluation(
            progress: .inProgress,
            evidenceSnapshot: "No terminal evidence is available for the saved project goal yet.",
            evaluatedAt: now
        )
    }

    private func evaluateRecommendationOutcome(
        _ outcome: ForemanProjectGoalRecommendationOutcome?,
        now: Date
    ) -> ForemanProjectGoalEvaluation? {
        guard let outcome else { return nil }

        switch outcome {
        case .agentAction(let action):
            switch action {
            case .declareComplete(let summary):
                return .init(
                    progress: .completed,
                    evidenceSnapshot: sanitized(summary, fallback: "Foreman declared the project goal complete."),
                    evaluatedAt: now
                )
            case .declareStuck(let reason):
                return .init(
                    progress: .needsHumanInput(.blocked),
                    evidenceSnapshot: sanitized(reason, fallback: "Foreman could not continue safely."),
                    evaluatedAt: now
                )
            case .askUser(let question):
                return .init(
                    progress: .needsHumanInput(humanInputKind(for: question)),
                    evidenceSnapshot: sanitized(question, fallback: "Foreman needs human guidance before continuing."),
                    evaluatedAt: now
                )
            case .respond, .sendCommand:
                return nil
            }

        case .replyDraft(let suggestion):
            switch suggestion {
            case .askHuman(_, let message, let reason, _):
                let snapshot = sanitized(
                    reason,
                    fallback: sanitized(message, fallback: "Foreman needs human guidance before continuing.")
                )
                return .init(
                    progress: .needsHumanInput(humanInputKind(for: "\(message) \(reason)")),
                    evidenceSnapshot: snapshot,
                    evaluatedAt: now
                )
            case .replyToAgent, .noAction:
                return nil
            }
        }
    }

    private func projectUnderstandings(
        for projectID: String,
        terminals: [TerminalSnapshot],
        understandings: [TerminalUnderstanding]
    ) -> [TerminalUnderstanding] {
        let relevantTerminalIDs = Set(
            terminals
                .filter { ForemanProjectPathResolver.projectPath(from: $0.cwd) == projectID }
                .map(\.terminalID)
        )

        if relevantTerminalIDs.isEmpty {
            return understandings
        }

        return understandings.filter { relevantTerminalIDs.contains($0.terminalID) }
    }

    private func blockedEvidence(for understanding: TerminalUnderstanding) -> String {
        "\(terminalLabel(for: understanding)) needs human help: \(understanding.shortExplanation)"
    }

    private func uncertainEvidence(for understanding: TerminalUnderstanding) -> String {
        let detail = sanitized(
            understanding.lastMeaningfulEvent,
            fallback: understanding.shortExplanation
        )
        return "\(terminalLabel(for: understanding)) is waiting for direction: \(detail)"
    }

    private func completionEvidence(
        goal: ForemanProjectGoal,
        understandings: [TerminalUnderstanding]
    ) -> String {
        if let completionSignal = understandings.first(where: Self.hasCompletionSignal) {
            return "\(terminalLabel(for: completionSignal)) indicates the goal is complete: \(completionSignal.shortExplanation)"
        }

        return "Observed terminal state suggests the goal is complete: \(goal.goalText)"
    }

    private func inProgressEvidence(for understanding: TerminalUnderstanding) -> String {
        "\(terminalLabel(for: understanding)) is still in progress: \(understanding.shortExplanation)"
    }

    private func terminalLabel(for understanding: TerminalUnderstanding) -> String {
        if !understanding.title.isEmpty {
            return understanding.title
        }

        return understanding.terminalID
    }

    private func humanInputKind(for text: String) -> ForemanProjectGoalHumanInputKind {
        let normalized = text.lowercased()
        let blockedKeywords = [
            "approval",
            "approve",
            "blocked",
            "cannot",
            "can't",
            "failed",
            "error",
            "missing",
            "permission",
            "access",
            "auth",
        ]

        if blockedKeywords.contains(where: normalized.contains) {
            return .blocked
        }

        return .uncertain
    }

    private func sanitized(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func isBlocked(_ understanding: TerminalUnderstanding) -> Bool {
        switch understanding.agentInteractionState {
        case .waitingApproval, .waitingChoice, .error:
            return true
        case .unknown, .running, .waitingText, .completed:
            break
        }

        return understanding.state == .failed
    }

    private static func isUncertain(_ understanding: TerminalUnderstanding) -> Bool {
        understanding.agentInteractionState == .waitingText
    }

    private static func hasCompletionSignal(_ understanding: TerminalUnderstanding) -> Bool {
        understanding.agentInteractionState == .completed ||
            (understanding.agentIdentity != .none && understanding.state == .succeeded)
    }

    private static func hasOngoingWork(_ understanding: TerminalUnderstanding) -> Bool {
        switch understanding.agentInteractionState {
        case .running, .waitingApproval, .waitingChoice, .waitingText, .error:
            return true
        case .unknown, .completed:
            break
        }

        switch understanding.state {
        case .running, .failed, .waiting:
            return true
        case .idle, .succeeded, .noisyHealthy:
            return false
        }
    }
}

enum ForemanProjectGoalCommand: Equatable, Sendable {
    case help
    case complete
    case reopen
    case clear
    case set(String)

    static func parse(_ text: String) -> Self? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/goal") else { return nil }

        let suffix = trimmed.dropFirst("/goal".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return .help }

        if suffix == "complete" {
            return .complete
        }
        if suffix == "reopen" || suffix == "continue" {
            return .reopen
        }
        if suffix == "clear" || suffix == "close" {
            return .clear
        }
        if suffix.hasPrefix("set ") {
            let goal = suffix.dropFirst("set ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return goal.isEmpty ? .help : .set(goal)
        }
        if suffix.hasPrefix("extend ") {
            let goal = suffix.dropFirst("extend ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return goal.isEmpty ? .help : .set(goal)
        }

        return .help
    }
}

actor ForemanProjectGoalRuntime {
    private var goalsByProjectID: [String: ForemanProjectGoal] = [:]
    private var hasLoadedStoredGoals = false
    private let memoryStore: ForemanMemoryStore
    private let loadPersistedGoals: Bool

    init(
        memoryStore: ForemanMemoryStore = .shared,
        loadPersistedGoals: Bool = false
    ) {
        self.memoryStore = memoryStore
        self.loadPersistedGoals = loadPersistedGoals
    }

    func saveGoal(
        _ objective: String,
        for projectID: String,
        status: ForemanProjectGoalStatus = .active
    ) async {
        await ensureLoaded()

        let normalizedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectID.isEmpty, !normalizedObjective.isEmpty else { return }

        let now = Date()
        if var existing = goalsByProjectID[normalizedProjectID] {
            let goalChanged = existing.goalText != normalizedObjective
            let wasCompleted = existing.status == .completed

            existing.goalText = normalizedObjective
            existing.status = status
            existing.updatedAt = now

            if status == .completed {
                existing.completedAt = existing.completedAt ?? now
            } else {
                existing.completedAt = nil
            }

            if goalChanged || (wasCompleted && status != .completed) {
                existing.lastEvaluatedAt = nil
                existing.lastEvidenceSnapshot = nil
            }

            goalsByProjectID[normalizedProjectID] = existing
            await persist(existing)
            return
        }

        let goal = ForemanProjectGoal(
            projectID: normalizedProjectID,
            objective: normalizedObjective,
            status: status,
            createdAt: now,
            updatedAt: now,
            completedAt: status == .completed ? now : nil
        )
        goalsByProjectID[normalizedProjectID] = goal
        await persist(goal)
    }

    func recordEvaluation(
        _ evaluation: ForemanProjectGoalEvaluation,
        for projectID: String
    ) async {
        await ensureLoaded()

        guard var goal = goalsByProjectID[projectID] else { return }

        goal.updatedAt = evaluation.evaluatedAt
        goal.lastEvaluatedAt = evaluation.evaluatedAt
        goal.lastEvidenceSnapshot = evaluation.evidenceSnapshot

        switch evaluation.progress {
        case .completed:
            goal.status = .completed
            goal.completedAt = goal.completedAt ?? evaluation.evaluatedAt
        case .inProgress, .needsHumanInput:
            if goal.status == .active {
                goal.completedAt = nil
            }
        }

        goalsByProjectID[projectID] = goal
        await persist(goal)
    }

    func setStatus(
        _ status: ForemanProjectGoalStatus,
        for projectID: String,
        evidenceSnapshot: String? = nil,
        evaluatedAt: Date = Date()
    ) async {
        await ensureLoaded()

        guard var goal = goalsByProjectID[projectID] else { return }

        goal.status = status
        goal.updatedAt = evaluatedAt
        goal.lastEvaluatedAt = evaluatedAt
        if let evidenceSnapshot {
            goal.lastEvidenceSnapshot = evidenceSnapshot
        }

        switch status {
        case .completed:
            goal.completedAt = goal.completedAt ?? evaluatedAt
        case .active, .paused:
            goal.completedAt = nil
        }

        goalsByProjectID[projectID] = goal
        await persist(goal)
    }

    func clearGoal(for projectID: String) async {
        await ensureLoaded()
        goalsByProjectID.removeValue(forKey: projectID)
        guard loadPersistedGoals else { return }
        try? await memoryStore.deleteProjectGoal(for: projectID)
    }

    func goal(for projectID: String) async -> ForemanProjectGoal? {
        await ensureLoaded()
        return goalsByProjectID[projectID]
    }

    func activeGoal(for projectID: String) async -> ForemanProjectGoal? {
        await ensureLoaded()
        guard let goal = goalsByProjectID[projectID], goal.status.isActive else {
            return nil
        }

        return goal
    }

    func goal(forTerminalID terminalID: String, in terminals: [TerminalSnapshot]) async -> ForemanProjectGoal? {
        await ensureLoaded()

        guard let projectID = projectID(forTerminalID: terminalID, in: terminals) else {
            return nil
        }

        return goalsByProjectID[projectID]
    }

    func projectID(forTerminalID terminalID: String, in terminals: [TerminalSnapshot]) -> String? {
        guard let snapshot = terminals.first(where: { $0.terminalID == terminalID }) else {
            return nil
        }

        return ForemanProjectPathResolver.projectPath(from: snapshot.cwd)
    }

    private func ensureLoaded() async {
        guard !hasLoadedStoredGoals else { return }

        guard loadPersistedGoals else {
            hasLoadedStoredGoals = true
            return
        }

        if let storedGoals = try? await memoryStore.projectGoals() {
            goalsByProjectID = Dictionary(
                uniqueKeysWithValues: storedGoals.map { ($0.projectID, $0) }
            )
        }

        hasLoadedStoredGoals = true
    }

    private func persist(_ goal: ForemanProjectGoal) async {
        guard loadPersistedGoals else { return }
        try? await memoryStore.store(projectGoal: goal)
    }
}
