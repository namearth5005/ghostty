import Foundation

struct TerminalUnderstandingEngine {
    private let runtimeDetector = AgentRuntimeDetector()

    func understand(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?,
        wireRecords: [KimiWireRecord] = [],
        codexWireRecords: [CodexWireRecord] = [],
        claudeWireRecords: [ClaudeSessionState] = [],
        runtimeDetection: AgentRuntimeDetector.Detection? = nil
    ) -> TerminalUnderstanding {
        let applicableOutcome = applicableOutcome(for: current, previous: previous, lastOutcome: lastOutcome)
        let lastEvent = extractLastMeaningfulEvent(from: current, previous: previous, lastOutcome: applicableOutcome)
        let classification = classifyAgent(
            current: current,
            previous: previous,
            lastOutcome: applicableOutcome,
            lastEvent: lastEvent,
            wireRecords: wireRecords,
            codexWireRecords: codexWireRecords,
            claudeWireRecords: claudeWireRecords,
            runtimeDetection: runtimeDetection
        )
        let state = classifyState(current: current, lastOutcome: applicableOutcome, classification: classification)
        let suggestedActions = makeSuggestions(
            for: current,
            state: state,
            classification: classification,
            lastEvent: lastEvent
        )

        return TerminalUnderstanding(
            terminalID: current.terminalID,
            title: current.title,
            cwd: current.cwd,
            state: state,
            agentIdentity: classification?.identity ?? .none,
            agentInteractionState: classification?.interactionState ?? .unknown,
            supportLevel: classification?.supportLevel ?? .genericFallback,
            lastMeaningfulEvent: lastEvent,
            shortExplanation: explain(
                state: state,
                snapshot: current,
                classification: classification,
                lastEvent: lastEvent
            ),
            importantDetails: importantDetails(from: current.visibleText, state: state),
            evidence: classification?.evidence ?? [],
            suggestedNextActions: suggestedActions,
            agentInteractionContext: classification?.context ?? .none
        )
    }

    func makeOverview(
        current: [TerminalUnderstanding],
        previous: [TerminalUnderstanding]
    ) -> TerminalOverview {
        let currentIDs = Set(current.map(\.terminalID))
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.terminalID, $0) })
        let changedCurrent = current.filter { previousByID[$0.terminalID] != $0 }.map(\.terminalID)
        let removed = previous.map(\.terminalID).filter { !currentIDs.contains($0) }
        let changed = changedCurrent + removed

        if let changedTerminal = current.first(where: { changedCurrent.contains($0.terminalID) }) {
            return TerminalOverview(
                summary: "\(changedTerminal.terminalID): \(changedTerminal.shortExplanation)",
                changedTerminalIDs: changed,
                primaryTerminalID: changedTerminal.terminalID
            )
        }

        if let removedTerminalID = removed.first {
            return TerminalOverview(
                summary: "\(removedTerminalID) is no longer available.",
                changedTerminalIDs: changed,
                primaryTerminalID: removedTerminalID
            )
        }

        let summary = current.isEmpty
            ? "No terminals are currently available."
            : current.map { "\($0.terminalID): \($0.shortExplanation)" }.joined(separator: " ")

        return TerminalOverview(
            summary: summary,
            changedTerminalIDs: [],
            primaryTerminalID: current.first?.terminalID
        )
    }

    private func classifyAgent(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?,
        lastEvent: String,
        wireRecords: [KimiWireRecord],
        codexWireRecords: [CodexWireRecord],
        claudeWireRecords: [ClaudeSessionState],
        runtimeDetection: AgentRuntimeDetector.Detection?
    ) -> AgentClassification? {
        let resolvedRuntimeDetection = runtimeDetection ?? runtimeDetector.detect(
            current: current,
            previous: previous,
            kimiWireRecords: wireRecords,
            codexWireRecords: codexWireRecords,
            claudeWireRecords: claudeWireRecords
        )

        guard let runtimeDetection = resolvedRuntimeDetection else {
            return nil
        }

        let identity = runtimeDetection.identity

        // CRITICAL: Check for explicit approval UI on screen BEFORE trusting wire records.
        // Kimi's wire protocol does not emit ApprovalRequest for shell command approvals,
        // so the wire records may say .running while the screen shows a blocking approval prompt.
        if identity == .kimi,
           let approvalClassification = detectKimiScreenApproval(current: current, lastEvent: lastEvent) {
            return approvalClassification
        }

        if identity == .kimi, !wireRecords.isEmpty,
           let wireClassification = classifyFromWireRecords(
               identity: identity,
               wireRecords: wireRecords,
               lastEvent: lastEvent
           ) {
            return wireClassification
        }
        if identity == .codex, !codexWireRecords.isEmpty,
           let wireClassification = classifyFromCodexWireRecords(
               identity: identity,
               wireRecords: codexWireRecords,
               lastEvent: lastEvent
           ) {
            return wireClassification
        }
        if identity == .claudeCode, !claudeWireRecords.isEmpty,
           let wireClassification = classifyFromClaudeWireRecords(
               identity: identity,
               wireRecords: claudeWireRecords,
               lastEvent: lastEvent
           ) {
            return wireClassification
        }

        switch identity {
        case .kimi:
            let lowered = current.visibleText.lowercased()
            if lowered.contains("welcome to kimi code cli"),
               lowered.contains("directory:"),
               lowered.contains("model:") {
                return classification(
                    identity,
                    .waitingText,
                    runtimeState: .blocked,
                    .screenHeuristic,
                    "Kimi welcome screen detected — awaiting first input.",
                    0.88,
                    .waitingText(question: nil)
                )
            }

            if lowered.contains("agent (kimi"),
               lowered.contains("input") {
                return classification(
                    identity,
                    .waitingText,
                    runtimeState: .blocked,
                    .screenHeuristic,
                    "Kimi input region detected - awaiting next message.",
                    0.82,
                    .waitingText(question: nil)
                )
            }

            return classifyFromRuntimeDetection(
                identity: identity,
                runtimeDetection: runtimeDetection,
                current: current,
                lastOutcome: lastOutcome,
                lastEvent: lastEvent,
                choiceMarkers: ["choose one", "select an option"],
                approvalMarkers: ["approve once", "approve for this session", "reject"]
            )

        case .codex:
            return classifyFromRuntimeDetection(
                identity: identity,
                runtimeDetection: runtimeDetection,
                current: current,
                lastOutcome: lastOutcome,
                lastEvent: lastEvent,
                choiceMarkers: ["enter to confirm", "esc to cancel"],
                approvalMarkers: []
            )

        case .claudeCode:
            return classifyFromRuntimeDetection(
                identity: identity,
                runtimeDetection: runtimeDetection,
                current: current,
                lastOutcome: lastOutcome,
                lastEvent: lastEvent,
                choiceMarkers: ["what do you want to do?", "enter to confirm", "esc to cancel"],
                approvalMarkers: ["approve", "allow once", "allow always", "[y/n]", "yes / no", "allow this", "allow edit"]
            )

        case .none, .unknown:
            return nil
        }
    }

    /// Detects Kimi's shell-command approval UI when the wire protocol fails to emit ApprovalRequest.
    /// Looks for very specific on-screen markers to avoid false positives.
    private func detectKimiScreenApproval(current: TerminalSnapshot, lastEvent: String) -> AgentClassification? {
        let lowered = current.visibleText.lowercased()

        // Primary marker: the exact approval prompt header Kimi displays
        let hasApprovalHeader = lowered.contains("shell is requesting approval to run command")

        // Secondary markers: the exact option text Kimi shows
        let hasApproveOption = lowered.contains("approve once") || lowered.contains("approve for this session")
        let hasRejectOption = lowered.contains("reject, tell the model what to do instead")

        // Must have the header AND at least one option to avoid false positives
        guard hasApprovalHeader && (hasApproveOption || hasRejectOption) else {
            return nil
        }

        return AgentClassification(
            identity: .kimi,
            interactionState: .waitingApproval,
            runtimeState: .blocked,
            supportLevel: .firstClass,
            evidence: [.init(source: .screenHeuristic, detail: "Kimi shell approval UI detected on screen", confidence: 0.95)],
            context: .waitingApproval(description: lastEvent, tool: nil)
        )
    }

    private func classifyFromWireRecords(
        identity: AgentIdentity,
        wireRecords: [KimiWireRecord],
        lastEvent: String
    ) -> AgentClassification? {
        // Find the most recent record that carries actionable state
        guard let record = wireRecords.lazy.reversed().compactMap({ rec -> KimiWireRecord? in
            rec.asAgentInteractionContext != nil ? rec : nil
        }).first else {
            return nil
        }

        guard let context = record.asAgentInteractionContext else {
            return nil
        }
        let enrichedContext = enrichKimiWireContext(context, from: wireRecords)

        let interactionState: AgentInteractionState
        switch enrichedContext {
        case .running:
            interactionState = .running
        case .waitingApproval:
            interactionState = .waitingApproval
        case .waitingChoice:
            interactionState = .waitingChoice
        case .waitingText:
            interactionState = .waitingText
        case .completed:
            interactionState = .completed
        case .error:
            interactionState = .error
        case .none:
            return nil
        }

        return AgentClassification(
            identity: identity,
            interactionState: interactionState,
            runtimeState: runtimeState(for: enrichedContext),
            supportLevel: .firstClass,
            evidence: [.init(source: .wireSignal, detail: "Wire record: \(record.message.type)", confidence: 0.98)],
            context: enrichedContext
        )
    }

    private func enrichKimiWireContext(
        _ context: AgentInteractionContext,
        from wireRecords: [KimiWireRecord]
    ) -> AgentInteractionContext {
        guard case .waitingText(let question) = context,
              question?.isEmpty ?? true,
              let wireQuestion = latestKimiTextQuestion(from: wireRecords) else {
            return context
        }

        return .waitingText(question: wireQuestion)
    }

    private func latestKimiTextQuestion(from wireRecords: [KimiWireRecord]) -> String? {
        for record in wireRecords.reversed() where record.message.type == "ContentPart" {
            guard let text = record.message.payload.text ?? record.message.payload.content else {
                continue
            }

            if let question = text
                .split(separator: "\n")
                .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
                .last(where: { !$0.isEmpty && $0.contains("?") }) {
                return question
            }
        }

        return nil
    }

    private func classifyFromCodexWireRecords(
        identity: AgentIdentity,
        wireRecords: [CodexWireRecord],
        lastEvent: String
    ) -> AgentClassification? {
        guard let record = wireRecords.lazy.reversed().compactMap({ rec -> CodexWireRecord? in
            rec.asAgentInteractionContext != nil ? rec : nil
        }).first else {
            return nil
        }

        guard let context = record.asAgentInteractionContext else {
            return nil
        }

        let interactionState: AgentInteractionState
        switch context {
        case .running:
            interactionState = .running
        case .waitingApproval:
            interactionState = .waitingApproval
        case .waitingChoice:
            interactionState = .waitingChoice
        case .waitingText:
            interactionState = .waitingText
        case .completed:
            interactionState = .completed
        case .error:
            interactionState = .error
        case .none:
            return nil
        }

        return AgentClassification(
            identity: identity,
            interactionState: interactionState,
            runtimeState: runtimeState(for: context),
            supportLevel: .firstClass,
            evidence: [.init(source: .wireSignal, detail: "Codex wire: \(record.payload.type ?? record.type)", confidence: 0.98)],
            context: context
        )
    }

    private func classifyFromClaudeWireRecords(
        identity: AgentIdentity,
        wireRecords: [ClaudeSessionState],
        lastEvent: String
    ) -> AgentClassification? {
        guard let state = wireRecords.last,
              let context = state.asAgentInteractionContext else {
            return nil
        }

        let interactionState: AgentInteractionState
        switch context {
        case .running:
            interactionState = .running
        case .waitingApproval:
            interactionState = .waitingApproval
        case .waitingChoice:
            interactionState = .waitingChoice
        case .waitingText:
            interactionState = .waitingText
        case .completed:
            interactionState = .completed
        case .error:
            interactionState = .error
        case .none:
            return nil
        }

        return AgentClassification(
            identity: identity,
            interactionState: interactionState,
            runtimeState: runtimeState(for: context),
            supportLevel: .firstClass,
            evidence: [.init(source: .wireSignal, detail: "Claude status: \(state.status ?? "unknown")", confidence: 0.98)],
            context: context
        )
    }

    private func runtimeState(for context: AgentInteractionContext) -> AgentRuntimeDetector.State {
        switch context {
        case .none:
            return .unknown
        case .running:
            return .working
        case .waitingApproval, .waitingChoice, .waitingText:
            return .blocked
        case .completed:
            return .idle
        case .error:
            return .blocked
        }
    }

    private func classifyState(
        current: TerminalSnapshot,
        lastOutcome: TerminalOutcomeReport?,
        classification: AgentClassification?
    ) -> TerminalUnderstandingState {
        if let classification {
            switch classification.interactionState {
            case .waitingApproval, .waitingChoice, .waitingText:
                return .waiting
            case .running:
                return .running
            case .completed:
                return .succeeded
            case .error:
                return .failed
            case .unknown:
                switch classification.runtimeState {
                case .blocked:
                    return .waiting
                case .working:
                    return .running
                case .idle:
                    return .idle
                case .unknown:
                    break
                }
            }
        }

        if let lastOutcome, lastOutcome.terminalID == current.terminalID {
            switch lastOutcome.outcome {
            case .success:
                return .succeeded
            case .failure:
                return .failed
            case .needsInput:
                return .waiting
            case .hung:
                return .failed
            case .stillRunning, .unknown:
                break
            }
        }
        if current.visibleText.lowercased().contains("command not found") || current.signals.likelyErrorState {
            return .failed
        }
        if current.signals.likelyWaitingForInput {
            return .waiting
        }
        if current.signals.likelyLongRunning {
            return .running
        }
        if current.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .idle
        }
        return .noisyHealthy
    }

    private func extractLastMeaningfulEvent(
        from current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?
    ) -> String {
        if let lastOutcome, lastOutcome.terminalID == current.terminalID, let summary = lastOutcome.summary {
            return summary
        }
        let previousText = previous?.visibleText ?? ""
        let currentLines = meaningfulTerminalLines(from: current.visibleText)
        let previousLines = Set(previousText.split(separator: "\n").map(String.init))
        return currentLines.last(where: { !previousLines.contains($0) && !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? currentLines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? "No meaningful terminal event detected."
    }

    private func explain(
        state: TerminalUnderstandingState,
        snapshot: TerminalSnapshot,
        classification: AgentClassification?,
        lastEvent: String
    ) -> String {
        if let classification {
            let name = classification.identity.displayName ?? snapshot.title
            switch classification.interactionState {
            case .waitingApproval:
                return "\(name) is waiting for approval to continue."
            case .waitingChoice:
                return "\(name) is waiting for your selection."
            case .waitingText:
                if looksLikeQuestion(lastEvent) {
                    return "\(name) is waiting for your response: \(lastEvent)"
                }
                return "\(name) is waiting for your response."
            case .running:
                return "\(name) is actively working in this terminal."
            case .completed:
                return "\(name) completed its turn: \(lastEvent)"
            case .error:
                return "\(name) hit an error: \(lastEvent)"
            case .unknown:
                break
            }
        }

        switch state {
        case .failed:
            return "The terminal failed: \(lastEvent)"
        case .succeeded:
            return "The terminal completed successfully: \(lastEvent)"
        case .running:
            return "The \(snapshot.title) terminal is still running a long-lived command."
        case .waiting:
            return "The terminal is waiting for input."
        case .idle:
            return "The terminal is idle."
        case .noisyHealthy:
            return "The terminal is producing output without signs of failure."
        }
    }

    private func importantDetails(from visibleText: String, state: TerminalUnderstandingState) -> [String] {
        let lines: [String]
        switch state {
        case .waiting:
            lines = meaningfulTerminalLines(from: visibleText)
        default:
            lines = visibleText.split(separator: "\n").map(String.init)
        }

        switch state {
        case .failed:
            return Array(lines.suffix(3))
        default:
            return Array(lines.suffix(2))
        }
    }

    private func makeSuggestions(
        for snapshot: TerminalSnapshot,
        state: TerminalUnderstandingState,
        classification: AgentClassification?,
        lastEvent: String
    ) -> [TerminalSuggestedAction] {
        let input = snapshot.lastInputPreview ?? ""

        if let classification {
            switch classification.interactionState {
            case .waitingApproval:
                return [
                    .init(title: "Review the approval request", command: nil, reason: lastEvent, isRecommended: true),
                    .init(title: "Let Foreman explain the requested action", command: nil, reason: "Use this when the approval UI is dense.", isRecommended: false),
                ]
            case .waitingChoice:
                return [
                    .init(title: "Inspect the available choices", command: nil, reason: lastEvent, isRecommended: true),
                    .init(title: "Ask Foreman to summarize the options", command: nil, reason: "Useful when the menu is noisy.", isRecommended: false),
                ]
            case .waitingText:
                return [
                    .init(title: "Reply to the agent", command: nil, reason: lastEvent, isRecommended: true),
                ]
            case .error:
                return [
                    .init(title: "Inspect the failure details", command: nil, reason: lastEvent, isRecommended: true),
                ]
            case .running, .completed, .unknown:
                break
            }
        }

        if state == .failed && lastEvent.lowercased().contains("command not found") && input.contains("hfind") {
            return [
                .init(
                    title: "Run the likely intended find command",
                    command: "find . -print",
                    reason: "This looks like a typo of a standard shell command.",
                    isRecommended: true
                ),
                .init(
                    title: "Try fd if a faster file search was intended",
                    command: "fd .",
                    reason: "The intended tool may have been `fd` rather than `find`.",
                    isRecommended: false
                ),
                .init(
                    title: "Confirm whether hfind was intentional",
                    command: nil,
                    reason: "Use this when the missing command may be project-specific.",
                    isRecommended: false
                ),
            ]
        }

        if state == .failed {
            return [
                .init(title: "Inspect the failure details", command: nil, reason: lastEvent, isRecommended: true),
                .init(
                    title: "Rerun the command after fixing the obvious issue",
                    command: input.isEmpty ? nil : input,
                    reason: "Useful when the failure was transient or typo-driven.",
                    isRecommended: false
                ),
                .init(
                    title: "Ask Foreman for a focused explanation",
                    command: nil,
                    reason: "Useful if the output is noisy and needs compression.",
                    isRecommended: false
                ),
            ]
        }

        return []
    }

    private func looksLikePrompt(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let promptMarkers = ["$", "%", "#", ">", "λ", "❯", "➜", "→", "⇒", "›"]
        return promptMarkers.contains(where: {
            trimmed == $0 || trimmed.hasPrefix($0 + " ") || trimmed.hasSuffix(" " + $0) || trimmed.hasSuffix($0)
        })
    }

    private func looksLikeQuestion(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).contains("?")
    }

    private func meaningfulTerminalLines(from text: String) -> [String] {
        text.split(separator: "\n")
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty &&
                    !looksLikePrompt(trimmed) &&
                    !looksLikeTerminalInputChrome(trimmed)
            }
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

    private func applicableOutcome(
        for current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?
    ) -> TerminalOutcomeReport? {
        guard let lastOutcome, lastOutcome.terminalID == current.terminalID else {
            return nil
        }

        let activeCommand = normalizedCommand(current.lastInputPreview)
            ?? normalizedCommand(previous?.lastInputPreview)
        guard let activeCommand, activeCommand == normalizedCommand(lastOutcome.sentCommand) else {
            return nil
        }

        if isFreshExecutionTransition(current: current, previous: previous) {
            return nil
        }

        return lastOutcome
    }

    private func normalizedCommand(_ command: String?) -> String? {
        guard let command else {
            return nil
        }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func isFreshExecutionTransition(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?
    ) -> Bool {
        guard let previous else { return false }
        guard previous.signals.likelyWaitingForInput else { return false }
        guard !current.signals.likelyWaitingForInput else { return false }
        return current.visibleText != previous.visibleText
    }
}

private struct AgentClassification {
    let identity: AgentIdentity
    let interactionState: AgentInteractionState
    let runtimeState: AgentRuntimeDetector.State
    let supportLevel: AgentSupportLevel
    let evidence: [UnderstandingEvidence]
    let context: AgentInteractionContext
}

private func classifyFromRuntimeDetection(
    identity: AgentIdentity,
    runtimeDetection: AgentRuntimeDetector.Detection,
    current: TerminalSnapshot,
    lastOutcome: TerminalOutcomeReport?,
    lastEvent: String,
    choiceMarkers: [String],
    approvalMarkers: [String]
) -> AgentClassification {
    let lowered = current.visibleText.lowercased()
    let promptReady = current.signals.likelyWaitingForInput

    if let lastOutcome {
        switch lastOutcome.outcome {
        case .failure, .hung:
            return classification(identity, .error, runtimeState: .blocked, .outcome, "Terminal outcome reported failure.", 1.0, .error(description: lastOutcome.summary ?? "Unknown failure"))
        case .success:
            return classification(identity, .completed, runtimeState: .idle, .outcome, "Terminal outcome reported success.", 1.0, .completed(summary: lastOutcome.summary))
        case .needsInput:
            return classification(identity, .waitingText, runtimeState: .blocked, .outcome, "Terminal outcome requested additional input.", 1.0, .waitingText(question: lastOutcome.summary))
        case .stillRunning, .unknown:
            break
        }
    }

    if containsAny(lowered, markers: choiceMarkers) || looksLikeNumberedChoiceMenu(current.visibleText) {
        let options = extractNumberedOptions(current.visibleText)
        guard !options.isEmpty else {
            return classification(identity, .waitingText, runtimeState: .blocked, .screenHeuristic, "Detected an interactive prompt without parsed choice options.", 0.78, .waitingText(question: lastEvent))
        }

        return classification(identity, .waitingChoice, runtimeState: .blocked, .screenHeuristic, "Detected an interactive choice menu.", 0.86, .waitingChoice(question: lastEvent, options: options))
    }

    if looksLikeApprovalPrompt(identity: identity, loweredVisibleText: lowered, approvalMarkers: approvalMarkers) {
        return classification(identity, .waitingApproval, runtimeState: .blocked, .phraseHeuristic, "Detected approval-oriented prompt text.", 0.82, .waitingApproval(description: lastEvent, tool: nil))
    }

    switch runtimeDetection.state {
    case .blocked:
        if current.signals.likelyErrorState && !looksLikeQuestion(lastEvent) {
            return classification(identity, .error, runtimeState: .blocked, .phraseHeuristic, "Detected active failure markers in agent output.", 0.73, .error(description: lastEvent))
        }

        let question = lastEvent.isEmpty ? nil : lastEvent
        return classification(identity, .waitingText, runtimeState: .blocked, .runtime, "Terminal returned control while the agent still needs attention.", 0.92, .waitingText(question: question))

    case .working:
        let stepDescription = lastEvent.isEmpty ? nil : lastEvent
        return classification(identity, .running, runtimeState: .working, .runtime, "Agent process is active without a prompt handoff.", 0.75, .running(stepDescription: stepDescription))

    case .idle:
        return classification(
            identity,
            .unknown,
            runtimeState: .idle,
            runtimeDetection.evidence.first?.source ?? .runtime,
            runtimeDetection.evidence.first?.detail ?? "Agent is idle.",
            runtimeDetection.evidence.first?.confidence ?? 0.75
        )

    case .unknown:
        if promptReady {
            return classification(identity, .waitingText, runtimeState: .blocked, .runtime, "Terminal returned control to the input region.", 0.92, .waitingText(question: lastEvent))
        }

        return classification(identity, .unknown, runtimeState: .unknown, .runtime, "Unable to determine raw runtime state.", 0.4)
    }
}

private func extractNumberedOptions(_ text: String) -> [String] {
    let lines = text.split(separator: "\n").map(String.init)
    var options: [String] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstScalar = trimmed.unicodeScalars.first else { continue }
        if CharacterSet.decimalDigits.contains(firstScalar) || trimmed.hasPrefix("❯ ") {
            if let dotRange = trimmed.range(of: ". ") {
                let option = String(trimmed[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !option.isEmpty {
                    options.append(option)
                }
            }
        }
    }
    return options
}

private func classification(
    _ identity: AgentIdentity,
    _ interactionState: AgentInteractionState,
    runtimeState: AgentRuntimeDetector.State,
    _ source: UnderstandingEvidenceSource,
    _ detail: String,
    _ confidence: Double,
    _ context: AgentInteractionContext = .none
) -> AgentClassification {
    AgentClassification(
        identity: identity,
        interactionState: interactionState,
        runtimeState: runtimeState,
        supportLevel: .firstClass,
        evidence: [.init(source: source, detail: detail, confidence: confidence)],
        context: context
    )
}

private func containsAny(_ text: String, markers: [String]) -> Bool {
    markers.contains(where: text.contains)
}

private func looksLikeApprovalPrompt(
    identity: AgentIdentity,
    loweredVisibleText: String,
    approvalMarkers: [String]
) -> Bool {
    switch identity {
    case .codex:
        return looksLikeCodexApprovalPrompt(loweredVisibleText)
    case .none, .unknown:
        return false
    case .kimi, .claudeCode:
        return containsAny(loweredVisibleText, markers: approvalMarkers)
    }
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

private func looksLikeNumberedChoiceMenu(_ text: String) -> Bool {
    let lines = text
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    let numberedCount = lines.filter { line in
        let scalars = Array(line.unicodeScalars)
        guard let first = scalars.first, CharacterSet.decimalDigits.contains(first) || line.hasPrefix("❯ 1.") else {
            return false
        }
        return line.contains(". ")
    }.count

    return numberedCount >= 2
}

private func looksLikeQuestion(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).contains("?")
}
