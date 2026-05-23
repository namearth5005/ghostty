import Foundation

struct AgentRuntimeDetector {
    enum State: String, Codable, Equatable, Sendable {
        case unknown
        case idle
        case working
        case blocked
    }

    struct Detection: Equatable, Sendable {
        let identity: AgentIdentity
        let state: State
        let evidence: [UnderstandingEvidence]
    }

    func identity(for snapshot: TerminalSnapshot) -> AgentIdentity? {
        detectIdentity(snapshot)
    }

    func matches(_ snapshot: TerminalSnapshot, identity expectedIdentity: AgentIdentity) -> Bool {
        identity(for: snapshot) == expectedIdentity
    }

    func detect(
        current: TerminalSnapshot,
        previous: TerminalSnapshot? = nil,
        kimiWireRecords: [KimiWireRecord] = [],
        codexWireRecords: [CodexWireRecord] = [],
        claudeWireRecords: [ClaudeSessionState] = []
    ) -> Detection? {
        guard let identity = detectIdentity(current) else {
            return nil
        }

        if let wireDetection = detectFromWire(
            identity: identity,
            kimiWireRecords: kimiWireRecords,
            codexWireRecords: codexWireRecords,
            claudeWireRecords: claudeWireRecords
        ) {
            return wireDetection
        }

        return detectFromScreen(identity: identity, current: current, previous: previous)
    }

    private func detectIdentity(_ snapshot: TerminalSnapshot) -> AgentIdentity? {
        if let foregroundProcessName = snapshot.runtime.foregroundProcessName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !foregroundProcessName.isEmpty {
            if let processMatch = detectIdentity(in: foregroundProcessName) {
                return processMatch
            }

            return detectIdentity(inVisibleText: snapshot.visibleText)
        }

        if let visibleMatch = detectIdentity(inVisibleText: snapshot.visibleText) {
            return visibleMatch
        }

        return detectIdentity(in: snapshot.title)
    }

    private func detectIdentity(inVisibleText visibleText: String) -> AgentIdentity? {
        let visible = visibleText.lowercased()
        if visible.contains("welcome to kimi code cli") || visible.contains("agent (kimi") {
            return .kimi
        }
        if visible.contains("welcome to claude code") || visible.contains("claude code") {
            return .claudeCode
        }
        if visible.contains("openai codex") {
            return .codex
        }

        return nil
    }

    private func detectIdentity(in candidate: String?) -> AgentIdentity? {
        guard let candidate else { return nil }
        let lowered = candidate.lowercased()

        if lowered.contains("kimi code") || lowered == "kimi" || lowered.contains("kimi") {
            return .kimi
        }
        if lowered.contains("claude code") || lowered == "claude" || lowered.contains("claude") {
            return .claudeCode
        }
        if lowered.contains("openai codex") || lowered == "codex" || lowered.contains("codex") {
            return .codex
        }

        return nil
    }

    private func detectFromWire(
        identity: AgentIdentity,
        kimiWireRecords: [KimiWireRecord],
        codexWireRecords: [CodexWireRecord],
        claudeWireRecords: [ClaudeSessionState]
    ) -> Detection? {
        switch identity {
        case .kimi:
            guard let context = kimiWireRecords
                .lazy
                .reversed()
                .compactMap(\.asAgentInteractionContext)
                .first else {
                return nil
            }
            return detection(identity: identity, state: state(for: context), detail: "Kimi wire state", source: .wireSignal, confidence: 0.98)

        case .codex:
            guard let context = codexWireRecords
                .lazy
                .reversed()
                .compactMap(\.asAgentInteractionContext)
                .first else {
                return nil
            }
            return detection(identity: identity, state: state(for: context), detail: "Codex wire state", source: .wireSignal, confidence: 0.98)

        case .claudeCode:
            guard let context = claudeWireRecords
                .lazy
                .reversed()
                .compactMap(\.asAgentInteractionContext)
                .first else {
                return nil
            }
            return detection(identity: identity, state: state(for: context), detail: "Claude session state", source: .wireSignal, confidence: 0.98)

        case .none, .unknown:
            return nil
        }
    }

    private func state(for context: AgentInteractionContext) -> State {
        switch context {
        case .none:
            return .unknown
        case .running:
            return .working
        case .waitingApproval, .waitingChoice, .waitingText, .error:
            return .blocked
        case .completed:
            return .idle
        }
    }

    private func detectFromScreen(
        identity: AgentIdentity,
        current: TerminalSnapshot,
        previous: TerminalSnapshot?
    ) -> Detection {
        let lowered = current.visibleText.lowercased()
        let lastEvent = lastMeaningfulEvent(from: current, previous: previous)
        let promptReady = current.runtime.cursorIsAtPrompt || current.signals.likelyWaitingForInput

        if identity == .kimi && isKimiWelcomeScreen(lowered) {
            return detection(identity: identity, state: .blocked, detail: "Kimi welcome screen is awaiting first input.", source: .screenHeuristic, confidence: 0.9)
        }

        if hasChoiceMenu(in: current.visibleText, identity: identity) {
            return detection(identity: identity, state: .blocked, detail: "Interactive choice menu detected.", source: .screenHeuristic, confidence: 0.86)
        }

        if hasApprovalPrompt(in: lowered, identity: identity) {
            return detection(identity: identity, state: .blocked, detail: "Approval prompt detected.", source: .phraseHeuristic, confidence: 0.86)
        }

        if promptReady && promptRequiresReply(identity: identity, lastEvent: lastEvent, visibleText: lowered) {
            return detection(identity: identity, state: .blocked, detail: "Agent has returned control while still asking for input.", source: .runtime, confidence: 0.92)
        }

        if current.signals.likelyErrorState && !looksLikeQuestion(lastEvent) {
            return detection(identity: identity, state: .blocked, detail: "Error markers detected in terminal output.", source: .phraseHeuristic, confidence: 0.74)
        }

        if looksActivelyWorking(identity: identity, snapshot: current) {
            return detection(identity: identity, state: .working, detail: "Agent appears to still be actively working.", source: .runtime, confidence: 0.8)
        }

        if promptReady {
            return detection(identity: identity, state: .idle, detail: "Agent returned to a quiet prompt without an active request.", source: .runtime, confidence: 0.82)
        }

        if current.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return detection(identity: identity, state: .idle, detail: "Terminal is empty.", source: .runtime, confidence: 0.8)
        }

        if current.runtime.usingAlternateScreen || current.signals.likelyLongRunning {
            return detection(identity: identity, state: .working, detail: "Agent owns an active TUI or long-running command.", source: .runtime, confidence: 0.72)
        }

        return detection(identity: identity, state: .idle, detail: "No active blocking or running markers were detected.", source: .runtime, confidence: 0.65)
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

    private func hasApprovalPrompt(in loweredVisibleText: String, identity: AgentIdentity) -> Bool {
        switch identity {
        case .kimi:
            return loweredVisibleText.contains("shell is requesting approval to run command")
                || loweredVisibleText.contains("approve once")
                || loweredVisibleText.contains("approve for this session")
                || loweredVisibleText.contains("reject, tell the model what to do instead")
        case .codex:
            return looksLikeCodexApprovalPrompt(loweredVisibleText)
        case .claudeCode:
            return containsAny(loweredVisibleText, markers: ["approve", "allow once", "allow always", "[y/n]", "yes / no", "allow this", "allow edit"])
        case .none, .unknown:
            return false
        }
    }

    private func hasChoiceMenu(in visibleText: String, identity: AgentIdentity) -> Bool {
        let lowered = visibleText.lowercased()
        let choiceMarkers: [String]
        switch identity {
        case .kimi:
            choiceMarkers = ["choose one", "select an option"]
        case .codex:
            choiceMarkers = ["enter to confirm", "esc to cancel"]
        case .claudeCode:
            choiceMarkers = ["what do you want to do?", "enter to confirm", "esc to cancel"]
        case .none, .unknown:
            choiceMarkers = []
        }

        return containsAny(lowered, markers: choiceMarkers) && looksLikeNumberedChoiceMenu(visibleText)
    }

    private func promptRequiresReply(identity: AgentIdentity, lastEvent: String, visibleText: String) -> Bool {
        if looksLikeQuestion(lastEvent) || containsReplyCue(in: lastEvent.lowercased()) {
            return true
        }

        if identity == .kimi && isKimiWelcomeScreen(visibleText) {
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

    private func isKimiWelcomeScreen(_ loweredVisibleText: String) -> Bool {
        loweredVisibleText.contains("welcome to kimi code cli")
            && loweredVisibleText.contains("directory:")
            && loweredVisibleText.contains("model:")
    }

    private func detection(
        identity: AgentIdentity,
        state: State,
        detail: String,
        source: UnderstandingEvidenceSource,
        confidence: Double
    ) -> Detection {
        Detection(
            identity: identity,
            state: state,
            evidence: [.init(source: source, detail: detail, confidence: confidence)]
        )
    }

    private func lastMeaningfulEvent(from current: TerminalSnapshot, previous: TerminalSnapshot?) -> String {
        let previousLines = Set((previous?.visibleText ?? "").split(separator: "\n").map(String.init))
        let currentLines = meaningfulTerminalLines(from: current.visibleText)

        return currentLines.last(where: { !previousLines.contains($0) && !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? currentLines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? ""
    }

    private func meaningfulTerminalLines(from text: String) -> [String] {
        text.split(separator: "\n")
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty
                    && !looksLikePrompt(trimmed)
                    && !looksLikeTerminalInputChrome(trimmed)
            }
    }

    private func looksLikePrompt(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let promptMarkers = ["$", "%", "#", ">", "λ", "❯", "➜", "→", "⇒", "›"]
        return promptMarkers.contains(where: {
            trimmed == $0 || trimmed.hasPrefix($0 + " ") || trimmed.hasSuffix(" " + $0) || trimmed.hasSuffix($0)
        })
    }

    private func looksLikeTerminalInputChrome(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()

        if lowered == "input" {
            return true
        }

        let withoutInput = lowered
            .replacingOccurrences(of: "input", with: "")
            .trimmingCharacters(in: .whitespaces)
        let inputChromeRun = withoutInput.filter { !$0.isWhitespace }
        if lowered.contains("input"),
           !inputChromeRun.isEmpty,
           inputChromeRun.allSatisfy({ $0 == "-" || $0 == "─" || $0 == "━" }) {
            return true
        }

        if lowered.hasPrefix("agent ("),
           lowered.contains("context:") ||
            lowered.contains("ctrl-") ||
            lowered.contains("shift-tab") ||
            lowered.contains("@:") {
            return true
        }

        if lowered.hasPrefix("context:") {
            return true
        }

        return false
    }

    private func looksLikeNumberedChoiceMenu(_ text: String) -> Bool {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let numberedCount = lines.filter { line in
            let scalars = Array(line.unicodeScalars)
            guard let first = scalars.first,
                  CharacterSet.decimalDigits.contains(first) || line.hasPrefix("❯ 1.") else {
                return false
            }
            return line.contains(". ")
        }.count

        return numberedCount >= 2
    }

    private func looksLikeQuestion(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).contains("?")
    }

    private func containsAny(_ text: String, markers: [String]) -> Bool {
        markers.contains(where: text.contains)
    }

    private func looksLikeCodexApprovalPrompt(_ text: String) -> Bool {
        if text.contains("permission required") ||
            text.contains("requesting permission") ||
            text.contains("needs your approval") {
            return true
        }

        if text.contains("[y/n]") &&
            (text.contains("approve") || text.contains("permission") || text.contains("allow")) {
            return true
        }

        return false
    }
}
