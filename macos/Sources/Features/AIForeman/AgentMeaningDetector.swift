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
    private let contextResolver = AgentInteractionContextResolver()
    private let screenDetector = AgentScreenInteractionDetector()

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
        let screenDetection = screenDetector.detect(
            identity: identity,
            visibleText: current.visibleText,
            lastEvent: lastEvent
        )

        // Preserve the existing Kimi behavior where the on-screen approval UI
        // outranks any stale running wire state.
        if identity == .kimi,
           let screenDetection,
           screenDetection.reason == .approvalPrompt,
           let approvalDetection = detectionFromScreen(
               identity: identity,
               screenDetection: screenDetection
           ) {
            return approvalDetection
        }

        if let resolvedContext = contextResolver.resolve(
            identity: identity,
            kimiWireRecords: wireRecords,
            codexWireRecords: codexWireRecords,
            claudeWireRecords: claudeWireRecords
        ), let wireDetection = detectionFromContext(
            identity: identity,
            context: resolvedContext.context,
            detail: resolvedContext.detail
        ) {
            return wireDetection
        }

        if let screenDetection,
           let detection = detectionFromScreen(
               identity: identity,
               screenDetection: screenDetection
           ) {
            return detection
        }

        switch identity {
        case .kimi, .codex, .claudeCode:
            return detectFromRuntime(
                identity: identity,
                runtimeDetection: runtimeDetection,
                current: current,
                lastOutcome: lastOutcome,
                lastEvent: lastEvent
            )

        case .none, .unknown:
            return nil
        }
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
        lastEvent: String
    ) -> Detection {
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

        switch runtimeDetection.state {
        case .blocked:
            if current.signals.likelyErrorState && !TerminalScreenText.looksLikeQuestion(lastEvent) {
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

    private func detectionFromScreen(
        identity: AgentIdentity,
        screenDetection: AgentScreenInteractionDetector.Detection
    ) -> Detection? {
        let interactionState: AgentInteractionState? = switch screenDetection.context {
        case .waitingApproval:
            AgentInteractionState.waitingApproval
        case .waitingChoice:
            AgentInteractionState.waitingChoice
        case .waitingText:
            AgentInteractionState.waitingText
        case .running, .completed, .error, .none:
            nil
        }

        guard let interactionState else {
            return nil
        }

        let evidence: UnderstandingEvidence
        switch screenDetection.reason {
        case .kimiWelcome:
            evidence = .init(
                source: .screenHeuristic,
                detail: "Kimi welcome screen detected — awaiting first input.",
                confidence: 0.88
            )
        case .kimiInputRegion:
            evidence = .init(
                source: .screenHeuristic,
                detail: "Kimi input region detected - awaiting next message.",
                confidence: 0.82
            )
        case .approvalPrompt:
            if identity == .kimi {
                evidence = .init(
                    source: .screenHeuristic,
                    detail: "Kimi shell approval UI detected on screen",
                    confidence: 0.95
                )
            } else {
                evidence = .init(
                    source: .phraseHeuristic,
                    detail: "Detected approval-oriented prompt text.",
                    confidence: 0.82
                )
            }
        case .choiceMenu:
            switch screenDetection.context {
            case .waitingChoice:
                evidence = .init(
                    source: .screenHeuristic,
                    detail: "Detected an interactive choice menu.",
                    confidence: 0.86
                )
            case .waitingText:
                evidence = .init(
                    source: .screenHeuristic,
                    detail: "Detected an interactive prompt without parsed choice options.",
                    confidence: 0.78
                )
            case .waitingApproval, .running, .completed, .error, .none:
                return nil
            }
        }

        return Detection(
            identity: identity,
            interactionState: interactionState,
            runtimeState: .blocked,
            supportLevel: .firstClass,
            evidence: [evidence],
            context: screenDetection.context
        )
    }
}
