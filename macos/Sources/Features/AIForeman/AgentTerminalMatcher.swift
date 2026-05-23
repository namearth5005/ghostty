import Foundation

enum AgentTerminalMatcher {
    static func matches(_ snapshot: TerminalSnapshot, identity: AgentIdentity) -> Bool {
        AgentRuntimeDetector().matches(snapshot, identity: identity)
    }
}
