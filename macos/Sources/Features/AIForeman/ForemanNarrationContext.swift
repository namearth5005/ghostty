import Foundation

enum ForemanStepPolicy: String, Equatable, Sendable {
    case standard
    case guidanceOnly
}

struct ForemanNarrationContext: Equatable, Sendable {
    let goal: String?
    let mode: AgentMode
    let iterationCount: Int
    let messages: [ConversationMessage]
    let hiddenContext: [String]
    let stepPolicy: ForemanStepPolicy

    init(
        goal: String?,
        mode: AgentMode,
        iterationCount: Int,
        messages: [ConversationMessage],
        hiddenContext: [String],
        stepPolicy: ForemanStepPolicy = .standard
    ) {
        self.goal = goal
        self.mode = mode
        self.iterationCount = iterationCount
        self.messages = messages
        self.hiddenContext = hiddenContext
        self.stepPolicy = stepPolicy
    }

    func withStepPolicy(_ stepPolicy: ForemanStepPolicy) -> Self {
        Self(
            goal: goal,
            mode: mode,
            iterationCount: iterationCount,
            messages: messages,
            hiddenContext: hiddenContext,
            stepPolicy: stepPolicy
        )
    }
}
