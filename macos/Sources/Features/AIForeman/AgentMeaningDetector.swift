import Foundation

struct AgentMeaningDetector {
    struct Detection: Equatable, Sendable {
        let identity: AgentIdentity
        let interactionState: AgentInteractionState
        let runtimeState: AgentRuntimeState
        let supportLevel: AgentSupportLevel
        let evidence: [UnderstandingEvidence]
        let context: AgentInteractionContext
    }

    private let runtimeDetector = AgentRuntimeDetector()

    func detect(
        current: TerminalSnapshot,
        previous: TerminalSnapshot?,
        lastOutcome: TerminalOutcomeReport?,
        lastEvent: String,
        wireRecords: [KimiWireRecord] = [],
        codexWireRecords: [CodexWireRecord] = [],
        claudeWireRecords: [ClaudeSessionState] = [],
        runtimeDetection: AgentRuntimeDetector.Detection? = nil
    ) -> Detection? {
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

        if identity == .kimi,
           let approvalDetection = detectKimiScreenApproval(current: current, lastEvent: lastEvent) {
            return approvalDetection
        }

        if identity == .kimi, !wireRecords.isEmpty,
           let wireDetection = detectFromKimiWireRecords(
               identity: identity,
               wireRecords: wireRecords
           ) {
            return wireDetection
        }

        if identity == .codex, !codexWireRecords.isEmpty,
           let wireDetection = detectFromCodexWireRecords(
               identity: identity,
               wireRecords: codexWireRecords
           ) {
            return wireDetection
        }

        if identity == .claudeCode, !claudeWireRecords.isEmpty,
           let wireDetection = detectFromClaudeWireRecords(
               identity: identity,
               wireRecords: claudeWireRecords
           ) {
            return wireDetection
        }

        switch identity {
        case .kimi:
            let lowered = current.visibleText.lowercased()
            if lowered.contains("welcome to kimi code cli"),
               lowered.contains("directory:"),
               lowered.contains("model:") {
                return detection(
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
                return detection(
                    identity,
                    .waitingText,
                    runtimeState: .blocked,
                    .screenHeuristic,
                    "Kimi input region detected - awaiting next message.",
                    0.82,
                    .waitingText(question: nil)
                )
            }

            return detectFromRuntime(
                identity: identity,
                runtimeDetection: runtimeDetection,
                current: current,
                lastOutcome: lastOutcome,
                lastEvent: lastEvent,
                choiceMarkers: ["choose one", "select an option"],
                approvalMarkers: ["approve once", "approve for this session", "reject"]
            )

        case .codex:
            return detectFromRuntime(
                identity: identity,
                runtimeDetection: runtimeDetection,
                current: current,
                lastOutcome: lastOutcome,
                lastEvent: lastEvent,
                choiceMarkers: ["enter to confirm", "esc to cancel"],
                approvalMarkers: []
            )

        case .claudeCode:
            return detectFromRuntime(
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

    private func detectKimiScreenApproval(current: TerminalSnapshot, lastEvent: String) -> Detection? {
        let lowered = current.visibleText.lowercased()
        let hasApprovalHeader = lowered.contains("shell is requesting approval to run command")
        let hasApproveOption = lowered.contains("approve once") || lowered.contains("approve for this session")
        let hasRejectOption = lowered.contains("reject, tell the model what to do instead")

        guard hasApprovalHeader && (hasApproveOption || hasRejectOption) else {
            return nil
        }

        return Detection(
            identity: .kimi,
            interactionState: .waitingApproval,
            runtimeState: .blocked,
            supportLevel: .firstClass,
            evidence: [.init(source: .screenHeuristic, detail: "Kimi shell approval UI detected on screen", confidence: 0.95)],
            context: .waitingApproval(description: lastEvent, tool: nil)
        )
    }

    private func detectFromKimiWireRecords(
        identity: AgentIdentity,
        wireRecords: [KimiWireRecord]
    ) -> Detection? {
        guard let record = wireRecords.lazy.reversed().compactMap({ record -> KimiWireRecord? in
            record.asAgentInteractionContext != nil ? record : nil
        }).first,
        let context = record.asAgentInteractionContext else {
            return nil
        }

        let enrichedContext = enrichKimiWireContext(context, from: wireRecords)
        return detectionFromContext(
            identity: identity,
            context: enrichedContext,
            detail: "Wire record: \(record.message.type)"
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

    private func detectFromCodexWireRecords(
        identity: AgentIdentity,
        wireRecords: [CodexWireRecord]
    ) -> Detection? {
        guard let record = wireRecords.lazy.reversed().compactMap({ record -> CodexWireRecord? in
            record.asAgentInteractionContext != nil ? record : nil
        }).first,
        let context = record.asAgentInteractionContext else {
            return nil
        }

        return detectionFromContext(
            identity: identity,
            context: context,
            detail: "Codex wire: \(record.payload.type ?? record.type)"
        )
    }

    private func detectFromClaudeWireRecords(
        identity: AgentIdentity,
        wireRecords: [ClaudeSessionState]
    ) -> Detection? {
        guard let pair = wireRecords.lazy.reversed().compactMap({ state -> (ClaudeSessionState, AgentInteractionContext)? in
            guard let context = state.asAgentInteractionContext else { return nil }
            return (state, context)
        }).first else {
            return nil
        }

        return detectionFromContext(
            identity: identity,
            context: pair.1,
            detail: "Claude status: \(pair.0.status ?? "unknown")"
        )
    }

    private func detectionFromContext(
        identity: AgentIdentity,
        context: AgentInteractionContext,
        detail: String
    ) -> Detection? {
        guard let interactionState = interactionState(for: context) else {
            return nil
        }

        return Detection(
            identity: identity,
            interactionState: interactionState,
            runtimeState: AgentRuntimeState(context: context),
            supportLevel: .firstClass,
            evidence: [.init(source: .wireSignal, detail: detail, confidence: 0.98)],
            context: context
        )
    }

    private func interactionState(for context: AgentInteractionContext) -> AgentInteractionState? {
        switch context {
        case .running:
            return .running
        case .waitingApproval:
            return .waitingApproval
        case .waitingChoice:
            return .waitingChoice
        case .waitingText:
            return .waitingText
        case .completed:
            return .completed
        case .error:
            return .error
        case .none:
            return nil
        }
    }

    private func detectFromRuntime(
        identity: AgentIdentity,
        runtimeDetection: AgentRuntimeDetector.Detection,
        current: TerminalSnapshot,
        lastOutcome: TerminalOutcomeReport?,
        lastEvent: String,
        choiceMarkers: [String],
        approvalMarkers: [String]
    ) -> Detection {
        let lowered = current.visibleText.lowercased()
        let promptReady = current.signals.likelyWaitingForInput

        if let lastOutcome {
            switch lastOutcome.outcome {
            case .failure, .hung:
                return detection(identity, .error, runtimeState: .blocked, .outcome, "Terminal outcome reported failure.", 1.0, .error(description: lastOutcome.summary ?? "Unknown failure"))
            case .success:
                return detection(identity, .completed, runtimeState: .idle, .outcome, "Terminal outcome reported success.", 1.0, .completed(summary: lastOutcome.summary))
            case .needsInput:
                return detection(identity, .waitingText, runtimeState: .blocked, .outcome, "Terminal outcome requested additional input.", 1.0, .waitingText(question: lastOutcome.summary))
            case .stillRunning, .unknown:
                break
            }
        }

        if containsAny(lowered, markers: choiceMarkers) || looksLikeNumberedChoiceMenu(current.visibleText) {
            let options = extractNumberedOptions(current.visibleText)
            guard !options.isEmpty else {
                return detection(identity, .waitingText, runtimeState: .blocked, .screenHeuristic, "Detected an interactive prompt without parsed choice options.", 0.78, .waitingText(question: lastEvent))
            }

            return detection(identity, .waitingChoice, runtimeState: .blocked, .screenHeuristic, "Detected an interactive choice menu.", 0.86, .waitingChoice(question: lastEvent, options: options))
        }

        if looksLikeApprovalPrompt(identity: identity, loweredVisibleText: lowered, approvalMarkers: approvalMarkers) {
            return detection(identity, .waitingApproval, runtimeState: .blocked, .phraseHeuristic, "Detected approval-oriented prompt text.", 0.82, .waitingApproval(description: lastEvent, tool: nil))
        }

        switch runtimeDetection.state {
        case .blocked:
            if current.signals.likelyErrorState && !looksLikeQuestion(lastEvent) {
                return detection(identity, .error, runtimeState: .blocked, .phraseHeuristic, "Detected active failure markers in agent output.", 0.73, .error(description: lastEvent))
            }

            let question = lastEvent.isEmpty ? nil : lastEvent
            return detection(identity, .waitingText, runtimeState: .blocked, .runtime, "Terminal returned control while the agent still needs attention.", 0.92, .waitingText(question: question))

        case .working:
            let stepDescription = lastEvent.isEmpty ? nil : lastEvent
            return detection(identity, .running, runtimeState: .working, .runtime, "Agent process is active without a prompt handoff.", 0.75, .running(stepDescription: stepDescription))

        case .idle:
            return Detection(
                identity: identity,
                interactionState: .unknown,
                runtimeState: .idle,
                supportLevel: .firstClass,
                evidence: runtimeDetection.evidence,
                context: .none
            )

        case .unknown:
            if promptReady {
                return detection(identity, .waitingText, runtimeState: .blocked, .runtime, "Terminal returned control to the input region.", 0.92, .waitingText(question: lastEvent))
            }

            return detection(identity, .unknown, runtimeState: .unknown, .runtime, "Unable to determine raw runtime state.", 0.4)
        }
    }

    private func detection(
        _ identity: AgentIdentity,
        _ interactionState: AgentInteractionState,
        runtimeState: AgentRuntimeState,
        _ source: UnderstandingEvidenceSource,
        _ detail: String,
        _ confidence: Double,
        _ context: AgentInteractionContext = .none
    ) -> Detection {
        Detection(
            identity: identity,
            interactionState: interactionState,
            runtimeState: runtimeState,
            supportLevel: .firstClass,
            evidence: [.init(source: source, detail: detail, confidence: confidence)],
            context: context
        )
    }
}

private func meaningContainsAny(_ text: String, markers: [String]) -> Bool {
    markers.contains(where: text.contains)
}

private func meaningLooksLikeApprovalPrompt(
    identity: AgentIdentity,
    loweredVisibleText: String,
    approvalMarkers: [String]
) -> Bool {
    switch identity {
    case .codex:
        return meaningLooksLikeCodexApprovalPrompt(loweredVisibleText)
    case .none, .unknown:
        return false
    case .kimi, .claudeCode:
        return meaningContainsAny(loweredVisibleText, markers: approvalMarkers)
    }
}

private func meaningLooksLikeCodexApprovalPrompt(_ text: String) -> Bool {
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

private func meaningLooksLikeNumberedChoiceMenu(_ text: String) -> Bool {
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

private func meaningExtractNumberedOptions(_ text: String) -> [String] {
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

private func meaningLooksLikeQuestion(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).contains("?")
}

private extension AgentMeaningDetector {
    func containsAny(_ text: String, markers: [String]) -> Bool {
        meaningContainsAny(text, markers: markers)
    }

    func looksLikeApprovalPrompt(
        identity: AgentIdentity,
        loweredVisibleText: String,
        approvalMarkers: [String]
    ) -> Bool {
        meaningLooksLikeApprovalPrompt(
            identity: identity,
            loweredVisibleText: loweredVisibleText,
            approvalMarkers: approvalMarkers
        )
    }

    func looksLikeNumberedChoiceMenu(_ text: String) -> Bool {
        meaningLooksLikeNumberedChoiceMenu(text)
    }

    func extractNumberedOptions(_ text: String) -> [String] {
        meaningExtractNumberedOptions(text)
    }

    func looksLikeQuestion(_ text: String) -> Bool {
        meaningLooksLikeQuestion(text)
    }
}
