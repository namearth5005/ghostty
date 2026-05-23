import Foundation

enum AgentRuntimeState: String, Codable, Equatable, Sendable {
    case unknown
    case idle
    case working
    case blocked

    init(context: AgentInteractionContext) {
        switch context {
        case .none:
            self = .unknown
        case .running:
            self = .working
        case .waitingApproval, .waitingChoice, .waitingText, .error:
            self = .blocked
        case .completed:
            self = .idle
        }
    }
}

struct AgentRawRuntimeDetector {
    private let screenDetector = AgentScreenInteractionDetector()

    struct Detection: Equatable, Sendable {
        let state: AgentRuntimeState
        let evidence: [UnderstandingEvidence]
    }

    func detect(
        identity: AgentIdentity,
        current: TerminalSnapshot,
        previous: TerminalSnapshot? = nil
    ) -> Detection {
        let lastEvent = TerminalScreenText.lastMeaningfulEvent(
            currentVisibleText: current.visibleText,
            previousVisibleText: previous?.visibleText ?? ""
        )
        let promptReady = current.runtime.cursorIsAtPrompt || current.signals.likelyWaitingForInput

        if let screenDetection = screenDetector.detect(
            identity: identity,
            visibleText: current.visibleText,
            lastEvent: lastEvent
        ) {
            return detection(for: screenDetection)
        }

        if promptReady && promptRequiresReply(lastEvent: lastEvent) {
            return detection(
                state: .blocked,
                detail: "Agent has returned control while still asking for input.",
                source: .runtime,
                confidence: 0.92
            )
        }

        if current.signals.likelyErrorState && !TerminalScreenText.looksLikeQuestion(lastEvent) {
            return detection(
                state: .blocked,
                detail: "Error markers detected in terminal output.",
                source: .phraseHeuristic,
                confidence: 0.74
            )
        }

        if looksActivelyWorking(identity: identity, snapshot: current) {
            return detection(
                state: .working,
                detail: "Agent appears to still be actively working.",
                source: .runtime,
                confidence: 0.8
            )
        }

        if promptReady {
            return detection(
                state: .idle,
                detail: "Agent returned to a quiet prompt without an active request.",
                source: .runtime,
                confidence: 0.82
            )
        }

        if current.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return detection(
                state: .idle,
                detail: "Terminal is empty.",
                source: .runtime,
                confidence: 0.8
            )
        }

        if current.runtime.usingAlternateScreen || current.signals.likelyLongRunning {
            return detection(
                state: .working,
                detail: "Agent owns an active TUI or long-running command.",
                source: .runtime,
                confidence: 0.72
            )
        }

        return detection(
            state: .idle,
            detail: "No active blocking or running markers were detected.",
            source: .runtime,
            confidence: 0.65
        )
    }

    private func looksActivelyWorking(identity: AgentIdentity, snapshot: TerminalSnapshot) -> Bool {
        let lowered = snapshot.visibleText.lowercased()
        let promptReady = snapshot.runtime.cursorIsAtPrompt || snapshot.signals.likelyWaitingForInput

        if snapshot.signals.likelyLongRunning && !promptReady {
            return true
        }

        switch identity {
        case .codex:
            if lowered.contains("working (") || lowered.contains("esc to interrupt") || lowered.contains("loading the session") {
                return true
            }
        case .kimi:
            if lowered.contains("thinking") || lowered.contains("step ") || lowered.contains("working...") {
                return true
            }
        case .claudeCode:
            if lowered.contains("thinking") || lowered.contains("working") || lowered.contains("generating") {
                return true
            }
        case .none, .unknown:
            break
        }

        return !promptReady && snapshot.runtime.usingAlternateScreen
    }

    private func promptRequiresReply(lastEvent: String) -> Bool {
        if TerminalScreenText.looksLikeQuestion(lastEvent) || containsReplyCue(in: lastEvent.lowercased()) {
            return true
        }

        return false
    }

    private func containsReplyCue(in text: String) -> Bool {
        containsAny(text, markers: [
            "what do you need",
            "what do you want",
            "what would you like",
            "how can i help",
            "before i can continue",
            "need your input",
            "need a decision",
            "choose one",
            "select an option",
        ])
    }

    private func detection(
        state: AgentRuntimeState,
        detail: String,
        source: UnderstandingEvidenceSource,
        confidence: Double
    ) -> Detection {
        Detection(
            state: state,
            evidence: [.init(source: source, detail: detail, confidence: confidence)]
        )
    }

    private func detection(for screenDetection: AgentScreenInteractionDetector.Detection) -> Detection {
        switch screenDetection.reason {
        case .kimiWelcome:
            return detection(
                state: .blocked,
                detail: "Kimi welcome screen is awaiting first input.",
                source: .screenHeuristic,
                confidence: 0.9
            )
        case .kimiInputRegion:
            return detection(
                state: .blocked,
                detail: "Kimi input region is awaiting the next message.",
                source: .screenHeuristic,
                confidence: 0.82
            )
        case .approvalPrompt:
            return detection(
                state: .blocked,
                detail: "Approval prompt detected.",
                source: .phraseHeuristic,
                confidence: 0.86
            )
        case .choiceMenu:
            return detection(
                state: .blocked,
                detail: "Interactive choice menu detected.",
                source: .screenHeuristic,
                confidence: 0.86
            )
        }
    }

    private func containsAny(_ text: String, markers: [String]) -> Bool {
        markers.contains(where: text.contains)
    }
}
