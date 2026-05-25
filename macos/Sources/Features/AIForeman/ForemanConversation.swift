import Foundation

enum ConversationMessageRole: String, Codable, Sendable, Equatable {
    case user
    case agent
}

struct ConversationMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: ConversationMessageRole
    let content: String
    let action: AgentAction?
    let terminalID: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: ConversationMessageRole,
        content: String,
        action: AgentAction? = nil,
        terminalID: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.action = action
        self.terminalID = terminalID
        self.timestamp = timestamp
    }
}

@MainActor
final class ForemanConversation: ObservableObject {
    private static let maxHiddenContextEntries = 8

    let runtimeState: ForemanRuntimeState

    @Published var messages: [ConversationMessage] = []
    @Published var goal: String?
    @Published var mode: AgentMode = .interactive
    @Published var isRunning: Bool = false
    @Published var status: AgentStatus = .idle
    @Published var iterationCount: Int = 0
    @Published var errorMessage: String?
    @Published private(set) var hiddenContext: [String] = []

    let maxIterations = 20

    init(runtimeState: ForemanRuntimeState = ForemanRuntimeState()) {
        self.runtimeState = runtimeState
    }

    func start(goal: String, mode: AgentMode = .interactive) {
        self.goal = goal
        self.mode = mode
        self.isRunning = true
        self.status = .observing
        self.iterationCount = 0
        self.errorMessage = nil
        runtimeState.resetForNewConversation()
        self.hiddenContext = []
        addMessage(role: .user, content: goal)
    }

    func stop() {
        isRunning = false
        status = .idle
        runtimeState.resetObservedTerminalContext()
        hiddenContext = []
    }

    func addMessage(
        role: ConversationMessageRole,
        content: String,
        action: AgentAction? = nil,
        terminalID: String? = nil
    ) {
        messages.append(ConversationMessage(
            role: role,
            content: content,
            action: action,
            terminalID: terminalID
        ))
    }

    func visibleMessages(selectedTerminalID: String?) -> [ConversationMessage] {
        messages.filter { message in
            guard let messageTerminalID = message.terminalID else {
                return true
            }
            return messageTerminalID == selectedTerminalID
        }
    }

    func addHiddenContext(_ content: String) {
        hiddenContext.append(content)
        if hiddenContext.count > Self.maxHiddenContextEntries {
            hiddenContext.removeFirst(hiddenContext.count - Self.maxHiddenContextEntries)
        }
    }

    func setStatus(_ status: AgentStatus) {
        self.status = status
    }

    func incrementIteration() {
        iterationCount += 1
    }

    func updateTerminalContext(
        overview: TerminalOverview,
        understandings: [TerminalUnderstanding],
        workerSnapshots: [String: TerminalWorkerSnapshot] = [:]
    ) {
        runtimeState.updateTerminalContext(
            overview: overview,
            understandings: understandings,
            workerSnapshots: workerSnapshots
        )
    }

    func setActiveProjectGoal(_ goal: ForemanProjectGoal?) {
        runtimeState.setActiveProjectGoal(goal)
    }

    var hasReachedMaxIterations: Bool {
        iterationCount >= maxIterations
    }

    var lastOverview: TerminalOverview? {
        runtimeState.lastOverview
    }

    var lastUnderstandings: [TerminalUnderstanding] {
        runtimeState.lastUnderstandings
    }

    var lastWorkerSnapshots: [String: TerminalWorkerSnapshot] {
        runtimeState.lastWorkerSnapshots
    }

    var activeProjectGoal: ForemanProjectGoal? {
        runtimeState.activeProjectGoal
    }

    var effectiveGoal: String? {
        runtimeState.effectiveGoal(fallbackGoal: goal)
    }

    var formattedHistory: String {
        messages.map { msg in
            let prefix = msg.role == .user ? "User" : "Agent"
            return "[\(prefix)]: \(msg.content)"
        }.joined(separator: "\n")
    }
}
