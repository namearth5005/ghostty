import Foundation

struct AgentRuntimeDetector {
    typealias State = AgentRuntimeState

    private let identityDetector = AgentIdentityDetector()
    private let rawRuntimeDetector = AgentRawRuntimeDetector()
    private let contextResolver = AgentInteractionContextResolver()

    struct Detection: Equatable, Sendable {
        let identity: AgentIdentity
        let state: State
        let evidence: [UnderstandingEvidence]
    }

    func identity(for snapshot: TerminalSnapshot) -> AgentIdentity? {
        identityDetector.identity(for: snapshot)
    }

    func matches(_ snapshot: TerminalSnapshot, identity expectedIdentity: AgentIdentity) -> Bool {
        identityDetector.matches(snapshot, identity: expectedIdentity)
    }

    func detect(
        current: TerminalSnapshot,
        previous: TerminalSnapshot? = nil,
        kimiWireRecords: [KimiWireRecord] = [],
        codexWireRecords: [CodexWireRecord] = [],
        claudeWireRecords: [ClaudeSessionState] = []
    ) -> Detection? {
        guard let identity = identityDetector.identity(for: current) ??
            inferredIdentityFromAttachedContext(
                kimiWireRecords: kimiWireRecords,
                codexWireRecords: codexWireRecords,
                claudeWireRecords: claudeWireRecords
            ) else {
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

        let rawDetection = rawRuntimeDetector.detect(
            identity: identity,
            current: current,
            previous: previous
        )

        return Detection(
            identity: identity,
            state: rawDetection.state,
            evidence: rawDetection.evidence
        )
    }

    private func inferredIdentityFromAttachedContext(
        kimiWireRecords: [KimiWireRecord],
        codexWireRecords: [CodexWireRecord],
        claudeWireRecords: [ClaudeSessionState]
    ) -> AgentIdentity? {
        var candidates: [AgentIdentity] = []

        if contextResolver.resolveKimi(from: kimiWireRecords) != nil {
            candidates.append(.kimi)
        }
        if contextResolver.resolveCodex(from: codexWireRecords) != nil {
            candidates.append(.codex)
        }
        if contextResolver.resolveClaude(from: claudeWireRecords) != nil {
            candidates.append(.claudeCode)
        }

        guard candidates.count == 1 else {
            return nil
        }

        return candidates[0]
    }

    private func detectFromWire(
        identity: AgentIdentity,
        kimiWireRecords: [KimiWireRecord],
        codexWireRecords: [CodexWireRecord],
        claudeWireRecords: [ClaudeSessionState]
    ) -> Detection? {
        guard let resolved = contextResolver.resolve(
            identity: identity,
            kimiWireRecords: kimiWireRecords,
            codexWireRecords: codexWireRecords,
            claudeWireRecords: claudeWireRecords
        ) else {
            return nil
        }

        return detection(
            identity: identity,
            state: State(context: resolved.context),
            detail: resolved.detail,
            source: .wireSignal,
            confidence: 0.98
        )
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
}
