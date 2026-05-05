import Foundation

/// Models for Anthropic Claude Code session state file.
///
/// Claude Code writes session metadata to:
///   ~/.claude/sessions/{pid}.json
///
/// The file contains a `status` field that tracks the session's coarse state.
struct ClaudeSessionState: Codable {
    let pid: Int
    let sessionId: String?
    let cwd: String?
    let status: String?
    let updatedAt: Int?
    let startedAt: Int?
    let version: String?
    let kind: String?

    enum CodingKeys: String, CodingKey {
        case pid
        case sessionId = "sessionId"
        case cwd
        case status
        case updatedAt = "updatedAt"
        case startedAt = "startedAt"
        case version
        case kind
    }
}

extension ClaudeSessionState {
    /// Maps the session status to a rich agent interaction context.
    var asAgentInteractionContext: AgentInteractionContext? {
        guard let status else { return nil }
        switch status.lowercased() {
        case "idle":
            return .waitingText(question: nil)
        case "working", "generating", "busy":
            return .running(stepDescription: nil)
        case "waiting_for_approval", "approval", "needs_approval":
            return .waitingApproval(description: "", tool: nil)
        case "error", "failed", "crashed":
            return .error(description: "Claude session error")
        default:
            return nil
        }
    }
}
