import Foundation

enum TerminalUnderstandingState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case succeeded
    case failed
    case waiting
    case noisyHealthy = "noisy_healthy"
}

enum AgentIdentity: String, Codable, Equatable, Sendable {
    case none
    case claudeCode = "claude_code"
    case codex
    case kimi
    case unknown

    var displayName: String? {
        switch self {
        case .none:
            return nil
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .kimi:
            return "Kimi"
        case .unknown:
            return "Unknown Agent"
        }
    }
}

enum AgentInteractionState: String, Codable, Equatable, Sendable {
    case unknown
    case running
    case waitingApproval = "waiting_approval"
    case waitingChoice = "waiting_choice"
    case waitingText = "waiting_text"
    case completed
    case error
}

enum AgentSupportLevel: String, Codable, Equatable, Sendable {
    case genericFallback = "generic_fallback"
    case firstClass = "first_class"
}

enum UnderstandingEvidenceSource: String, Codable, Equatable, Sendable {
    case runtime
    case outcome
    case screenHeuristic = "screen_heuristic"
    case phraseHeuristic = "phrase_heuristic"
    case managedLaunch = "managed_launch"
    case wireSignal = "wire_signal"
}

struct UnderstandingEvidence: Codable, Equatable, Sendable {
    let source: UnderstandingEvidenceSource
    let detail: String
    let confidence: Double
}

struct TerminalSuggestedAction: Codable, Equatable, Sendable {
    let title: String
    let command: String?
    let reason: String
    let isRecommended: Bool
    let authoritativeFingerprint: String?
    let authoritativePayload: String?
    let guidancePrompt: String?

    init(
        title: String,
        command: String?,
        reason: String,
        isRecommended: Bool,
        authoritativeFingerprint: String? = nil,
        authoritativePayload: String? = nil,
        guidancePrompt: String? = nil
    ) {
        self.title = title
        self.command = command
        self.reason = reason
        self.isRecommended = isRecommended
        self.authoritativeFingerprint = authoritativeFingerprint
        self.authoritativePayload = authoritativePayload
        self.guidancePrompt = guidancePrompt
    }
}

struct TerminalUnderstanding: Codable, Equatable, Sendable, Identifiable {
    let terminalID: String
    let title: String
    let cwd: String?
    let state: TerminalUnderstandingState
    let agentIdentity: AgentIdentity
    let agentInteractionState: AgentInteractionState
    let supportLevel: AgentSupportLevel
    let lastMeaningfulEvent: String
    let shortExplanation: String
    let importantDetails: [String]
    let evidence: [UnderstandingEvidence]
    let suggestedNextActions: [TerminalSuggestedAction]
    let agentInteractionContext: AgentInteractionContext
    let workerSnapshot: TerminalWorkerSnapshot?

    var id: String { terminalID }

    init(
        terminalID: String,
        title: String,
        cwd: String? = nil,
        state: TerminalUnderstandingState,
        agentIdentity: AgentIdentity = .none,
        agentInteractionState: AgentInteractionState = .unknown,
        supportLevel: AgentSupportLevel = .genericFallback,
        lastMeaningfulEvent: String,
        shortExplanation: String,
        importantDetails: [String] = [],
        evidence: [UnderstandingEvidence] = [],
        suggestedNextActions: [TerminalSuggestedAction] = [],
        agentInteractionContext: AgentInteractionContext = .none,
        workerSnapshot: TerminalWorkerSnapshot? = nil
    ) {
        self.terminalID = terminalID
        self.title = title
        self.cwd = cwd
        self.state = state
        self.agentIdentity = agentIdentity
        self.agentInteractionState = agentInteractionState
        self.supportLevel = supportLevel
        self.lastMeaningfulEvent = lastMeaningfulEvent
        self.shortExplanation = shortExplanation
        self.importantDetails = importantDetails
        self.evidence = evidence
        self.suggestedNextActions = suggestedNextActions
        self.agentInteractionContext = agentInteractionContext
        self.workerSnapshot = workerSnapshot
    }

    var recommendedAction: TerminalSuggestedAction? {
        suggestedNextActions.first(where: \.isRecommended)
    }

    static func preview(
        terminalID: String,
        state: TerminalUnderstandingState,
        shortExplanation: String,
        lastMeaningfulEvent: String,
        importantDetails: [String],
        suggestedNextActions: [TerminalSuggestedAction],
        agentIdentity: AgentIdentity = .none,
        agentInteractionState: AgentInteractionState = .unknown,
        supportLevel: AgentSupportLevel = .genericFallback,
        evidence: [UnderstandingEvidence] = [],
        agentInteractionContext: AgentInteractionContext = .none,
        workerSnapshot: TerminalWorkerSnapshot? = nil
    ) -> Self {
        .init(
            terminalID: terminalID,
            title: terminalID,
            cwd: nil,
            state: state,
            agentIdentity: agentIdentity,
            agentInteractionState: agentInteractionState,
            supportLevel: supportLevel,
            lastMeaningfulEvent: lastMeaningfulEvent,
            shortExplanation: shortExplanation,
            importantDetails: importantDetails,
            evidence: evidence,
            suggestedNextActions: suggestedNextActions,
            agentInteractionContext: agentInteractionContext,
            workerSnapshot: workerSnapshot
        )
    }
}

struct TerminalOverview: Codable, Equatable, Sendable {
    let summary: String
    let changedTerminalIDs: [String]
    let primaryTerminalID: String?
}
