import Foundation

enum AgentTerminalMatcher {
    static func matches(_ snapshot: TerminalSnapshot, identity: AgentIdentity) -> Bool {
        AgentIdentityDetector().matches(snapshot, identity: identity)
    }
}
