import Foundation

struct ForemanNarrationContext: Equatable, Sendable {
    let goal: String?
    let mode: AgentMode
    let iterationCount: Int
    let messages: [ConversationMessage]
    let hiddenContext: [String]
}
