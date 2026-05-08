import Foundation

/// Fired when an AI agent (Kimi, Claude Code, Codex) transitions from
/// actively working to a state where it needs user input or approval.
struct AgentNeedsAttentionEvent: Codable, Sendable {
    let terminalID: String
    let agentIdentity: AgentIdentity
    let interactionState: AgentInteractionState
    let deltaText: String
    let timestamp: Date
    let fingerprint: String

    init(
        terminalID: String,
        agentIdentity: AgentIdentity,
        interactionState: AgentInteractionState,
        deltaText: String,
        timestamp: Date,
        fingerprint: String? = nil
    ) {
        self.terminalID = terminalID
        self.agentIdentity = agentIdentity
        self.interactionState = interactionState
        self.deltaText = deltaText
        self.timestamp = timestamp
        self.fingerprint = fingerprint ?? Self.makeFingerprint(
            terminalID: terminalID,
            agentIdentity: agentIdentity,
            interactionState: interactionState,
            text: deltaText
        )
    }

    static func makeFingerprint(
        terminalID: String,
        agentIdentity: AgentIdentity,
        interactionState: AgentInteractionState,
        text: String
    ) -> String {
        [
            terminalID,
            agentIdentity.rawValue,
            interactionState.rawValue,
            normalizedFingerprintText(text),
        ].joined(separator: "|")
    }

    private static func normalizedFingerprintText(_ text: String) -> String {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let maxCharacters = 512
        guard normalized.count > maxCharacters else {
            return normalized
        }

        let prefix = String(normalized.prefix(maxCharacters))
        return "\(prefix)#\(stableHexHash(normalized))"
    }

    private static func stableHexHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return String(hash, radix: 16)
    }
}
