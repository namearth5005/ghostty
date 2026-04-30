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
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: ConversationMessageRole,
        content: String,
        action: AgentAction? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.action = action
        self.timestamp = timestamp
    }
}

@MainActor
final class ForemanConversation: ObservableObject {
    @Published var messages: [ConversationMessage] = []
    @Published var goal: String?
    @Published var mode: AgentMode = .interactive
    @Published var isRunning: Bool = false
    @Published var status: AgentStatus = .idle
    @Published var iterationCount: Int = 0
    @Published var errorMessage: String?
    @Published var lastOverview: TerminalOverview?
    @Published var lastUnderstandings: [TerminalUnderstanding] = []

    let maxIterations = 20

    func start(goal: String, mode: AgentMode = .interactive) {
        self.goal = goal
        self.mode = mode
        self.isRunning = true
        self.status = .observing
        self.iterationCount = 0
        self.errorMessage = nil
        addMessage(role: .user, content: goal)
    }

    func stop() {
        isRunning = false
        status = .idle
    }

    func addMessage(role: ConversationMessageRole, content: String, action: AgentAction? = nil) {
        messages.append(ConversationMessage(role: role, content: content, action: action))
    }

    func setStatus(_ status: AgentStatus) {
        self.status = status
    }

    func incrementIteration() {
        iterationCount += 1
    }

    func updateTerminalContext(
        overview: TerminalOverview,
        understandings: [TerminalUnderstanding]
    ) {
        self.lastOverview = overview
        self.lastUnderstandings = understandings
    }

    var hasReachedMaxIterations: Bool {
        iterationCount >= maxIterations
    }

    var formattedHistory: String {
        messages.map { msg in
            let prefix = msg.role == .user ? "User" : "Agent"
            return "[\(prefix)]: \(msg.content)"
        }.joined(separator: "\n")
    }
}
