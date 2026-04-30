import Foundation

enum TerminalUnderstandingState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case succeeded
    case failed
    case waiting
    case noisyHealthy = "noisy_healthy"
}

struct TerminalSuggestedAction: Codable, Equatable, Sendable {
    let title: String
    let command: String?
    let reason: String
    let isRecommended: Bool
}

struct TerminalUnderstanding: Codable, Equatable, Sendable, Identifiable {
    let terminalID: String
    let title: String
    let cwd: String?
    let state: TerminalUnderstandingState
    let lastMeaningfulEvent: String
    let shortExplanation: String
    let importantDetails: [String]
    let suggestedNextActions: [TerminalSuggestedAction]

    var id: String { terminalID }

    var recommendedAction: TerminalSuggestedAction? {
        suggestedNextActions.first(where: \.isRecommended)
    }

    static func preview(
        terminalID: String,
        state: TerminalUnderstandingState,
        shortExplanation: String,
        lastMeaningfulEvent: String,
        importantDetails: [String],
        suggestedNextActions: [TerminalSuggestedAction]
    ) -> Self {
        .init(
            terminalID: terminalID,
            title: terminalID,
            cwd: nil,
            state: state,
            lastMeaningfulEvent: lastMeaningfulEvent,
            shortExplanation: shortExplanation,
            importantDetails: importantDetails,
            suggestedNextActions: suggestedNextActions
        )
    }
}

struct TerminalOverview: Codable, Equatable, Sendable {
    let summary: String
    let changedTerminalIDs: [String]
    let primaryTerminalID: String?
}
