import Foundation

struct AgentRuntimeDetector {
    typealias State = AgentRuntimeState

    private let identityDetector = AgentIdentityDetector()
    private let rawRuntimeDetector = AgentRawRuntimeDetector()

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
        guard let identity = identityDetector.identity(for: current) else {
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
            return detection(identity: identity, state: State(context: context), detail: "Kimi wire state", source: .wireSignal, confidence: 0.98)

        case .codex:
            guard let context = codexWireRecords
                .lazy
                .reversed()
                .compactMap(\.asAgentInteractionContext)
                .first else {
                return nil
            }
            return detection(identity: identity, state: State(context: context), detail: "Codex wire state", source: .wireSignal, confidence: 0.98)

        case .claudeCode:
            guard let context = claudeWireRecords
                .lazy
                .reversed()
                .compactMap(\.asAgentInteractionContext)
                .first else {
                return nil
            }
            return detection(identity: identity, state: State(context: context), detail: "Claude session state", source: .wireSignal, confidence: 0.98)

        case .none, .unknown:
            return nil
        }
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
