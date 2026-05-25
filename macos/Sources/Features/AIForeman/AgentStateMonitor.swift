import Foundation

/// Watches AI agent terminals and fires a single event when an agent
/// transitions from working (running) to a state that needs attention.
final class AgentStateMonitor {
    var onEvent: ((AgentNeedsAttentionEvent) -> Void)?

    private var previousAgentStateByTerminalID: [String: AgentInteractionState] = [:]
    private var previousWaitingTextWasMeaningfulByTerminalID: [String: Bool] = [:]
    private var pendingFingerprintsByTerminalID: [String: Set<String>] = [:]
    private var terminalsWithEvents: Set<String> = []

    /// Kept for existing call sites; fingerprint-level resolution is handled by resolve.
    func notifyForemanReacted(terminalID: String, state: AgentInteractionState) {
        DebugLogger.log("[AgentStateMonitor] Foreman reacted to terminal \(terminalID.prefix(8)) in state \(state)")
    }

    func resolve(terminalID: String, fingerprint: String) {
        pendingFingerprintsByTerminalID[terminalID]?.remove(fingerprint)

        if pendingFingerprintsByTerminalID[terminalID]?.isEmpty == true {
            pendingFingerprintsByTerminalID.removeValue(forKey: terminalID)
        }

        DebugLogger.log("[AgentStateMonitor] Resolved fingerprint for terminal \(terminalID.prefix(8))")
    }

    /// Call this with the latest understandings (e.g., from sidebar refresh).
    func observe(understandings: [TerminalUnderstanding]) {
        let now = Date()

        for understanding in understandings {
            let id = understanding.terminalID

            // Only watch AI agents — ignore shell terminals entirely
            guard understanding.agentIdentity != .none else {
                // Clean up tracking for terminals that are no longer AI agents
                previousAgentStateByTerminalID.removeValue(forKey: id)
                previousWaitingTextWasMeaningfulByTerminalID.removeValue(forKey: id)
                pendingFingerprintsByTerminalID.removeValue(forKey: id)
                terminalsWithEvents.remove(id)
                continue
            }

            let previous = previousAgentStateByTerminalID[id] ?? .unknown
            let current = understanding.agentInteractionState
            let currentWaitingTextIsMeaningful = current == .waitingText &&
                Self.isMeaningfulWaitingText(understanding)
            let previousWaitingTextWasMeaningful =
                previousWaitingTextWasMeaningfulByTerminalID[id] ?? false

            guard Self.isAttentionState(current) else {
                pendingFingerprintsByTerminalID.removeValue(forKey: id)
                terminalsWithEvents.remove(id)
                previousWaitingTextWasMeaningfulByTerminalID.removeValue(forKey: id)
                DebugLogger.log("[AgentStateMonitor] Cleared pending fingerprints: terminal=\(id.prefix(8)) curr=\(current)")
                previousAgentStateByTerminalID[id] = current
                continue
            }

            // Fire on: running → {waitingApproval, waitingChoice, waitingText, error}
            // Also fire on FIRST detection for urgent states only (approval, choice, error).
            // First-detected waitingText is allowed only when it contains a real prompt,
            // so an already-waiting worker can get suggestions without spamming startup screens.
            let isTransitionFromRunning = previous == .running
            let isFirstDetection = previous == .unknown
            let isUrgentState = current == .waitingApproval || current == .waitingChoice || current == .error
            let isFirstMeaningfulWaitingText = isFirstDetection &&
                current == .waitingText &&
                currentWaitingTextIsMeaningful
            let waitingTextBecameMeaningful = previous == .waitingText &&
                current == .waitingText &&
                !previousWaitingTextWasMeaningful &&
                currentWaitingTextIsMeaningful
            let canFireChangedAttentionEvent = current != .waitingText &&
                terminalsWithEvents.contains(id)
            let shouldFire = (isTransitionFromRunning && Self.isAttentionState(current)) ||
                (isFirstDetection && isUrgentState) ||
                isFirstMeaningfulWaitingText ||
                waitingTextBecameMeaningful ||
                canFireChangedAttentionEvent

            if shouldFire {
                let deltaText = Self.eventText(from: understanding)
                let fingerprintText = Self.fingerprintText(from: understanding, fallback: deltaText)
                let fingerprint = AgentNeedsAttentionEvent.makeFingerprint(
                    terminalID: id,
                    agentIdentity: understanding.agentIdentity,
                    interactionState: current,
                    text: fingerprintText
                )

                if pendingFingerprintsByTerminalID[id]?.contains(fingerprint) == true {
                    DebugLogger.log("[AgentStateMonitor] Duplicate fingerprint pending: terminal=\(id.prefix(8)) agent=\(understanding.agentIdentity) state=\(current)")
                } else {
                    let event = AgentNeedsAttentionEvent(
                        terminalID: id,
                        agentIdentity: understanding.agentIdentity,
                        interactionState: current,
                        deltaText: deltaText,
                        timestamp: now,
                        fingerprint: fingerprint
                    )
                    DebugLogger.log("[AgentStateMonitor] Firing event: terminal=\(id.prefix(8)) agent=\(understanding.agentIdentity) state=\(current) transition=\(isTransitionFromRunning) meaningful=\(currentWaitingTextIsMeaningful) becameMeaningful=\(waitingTextBecameMeaningful)")
                    onEvent?(event)
                    pendingFingerprintsByTerminalID[id, default: []].insert(fingerprint)
                    terminalsWithEvents.insert(id)
                }
            } else if understanding.agentIdentity != .none {
                DebugLogger.log("[AgentStateMonitor] No trigger: terminal=\(id.prefix(8)) prev=\(previous) curr=\(current) meaningful=\(currentWaitingTextIsMeaningful) previousMeaningful=\(previousWaitingTextWasMeaningful)")
            }

            // Update tracked state
            previousAgentStateByTerminalID[id] = current
            if current == .waitingText {
                previousWaitingTextWasMeaningfulByTerminalID[id] = currentWaitingTextIsMeaningful
            } else {
                previousWaitingTextWasMeaningfulByTerminalID.removeValue(forKey: id)
            }
        }

        // Clean up tracking for closed terminals
        let activeIDs = Set(understandings.map(\.terminalID))
        for id in previousAgentStateByTerminalID.keys where !activeIDs.contains(id) {
            previousAgentStateByTerminalID.removeValue(forKey: id)
            previousWaitingTextWasMeaningfulByTerminalID.removeValue(forKey: id)
            pendingFingerprintsByTerminalID.removeValue(forKey: id)
            terminalsWithEvents.remove(id)
        }
    }

    private static func isAttentionState(_ state: AgentInteractionState) -> Bool {
        switch state {
        case .waitingApproval, .waitingChoice, .waitingText, .error:
            return true
        case .unknown, .running, .completed:
            return false
        }
    }

    private static func isMeaningfulWaitingText(_ understanding: TerminalUnderstanding) -> Bool {
        let text = ([
            understanding.shortExplanation,
            understanding.lastMeaningfulEvent,
            understanding.agentInteractionContext.descriptionString ?? "",
        ] + understanding.importantDetails)
            .joined(separator: "\n")
            .lowercased()

        if text.contains("welcome to kimi code cli") ||
            text.contains("send /help for help") {
            return false
        }

        return text.contains("?") ||
            text.contains("what would you like") ||
            text.contains("what should") ||
            text.contains("which ") ||
            text.contains("choose ")
    }

    private static func eventText(from understanding: TerminalUnderstanding) -> String {
        if let request = understanding.workerSnapshot?.request {
            let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty {
                return prompt
            }
        }

        if understanding.agentInteractionState == .waitingText,
           let question = understanding.agentInteractionContext.descriptionString,
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return question
        }

        return understanding.importantDetails.joined(separator: "\n")
    }

    private static func fingerprintText(
        from understanding: TerminalUnderstanding,
        fallback: String
    ) -> String {
        if let snapshot = understanding.workerSnapshot,
           snapshot.request != nil {
            return snapshot.attentionFingerprint
        }

        return fallback
    }
}
