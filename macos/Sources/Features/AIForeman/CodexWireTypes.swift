import Foundation

/// Codable models for OpenAI Codex CLI JSONL session events.
/// Codex writes newline-delimited JSON to:
///   ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<UUID>.jsonl
struct CodexWireRecord: Codable {
    let timestamp: String?
    let type: String
    let payload: CodexWirePayload
}

struct CodexWirePayload: Codable {
    // session_meta fields
    let id: String?
    let cwd: String?
    let originator: String?
    let cliVersion: String?

    // event_msg sub-type
    let type: String?

    // task_started / task_complete / turn_aborted fields
    let turnId: String?
    let startedAt: Int?
    let completedAt: Int?
    let durationMs: Int?
    let reason: String?
    let lastAgentMessage: String?

    // exec_command_end fields
    let callId: String?
    let processId: Int?
    let command: [String]?
    let status: String?

    // agent_message fields
    let message: String?
    let phase: String?

    enum CodingKeys: String, CodingKey {
        case id
        case cwd
        case originator
        case cliVersion = "cli_version"
        case type
        case turnId = "turn_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMs = "duration_ms"
        case reason
        case lastAgentMessage = "last_agent_message"
        case callId = "call_id"
        case processId = "process_id"
        case command
        case status
        case message
        case phase
    }
}

extension CodexWireRecord {
    /// Maps this Codex record to a rich agent interaction context.
    /// Returns nil for records that don't carry actionable state.
    var asAgentInteractionContext: AgentInteractionContext? {
        switch type {
        case "event_msg":
            guard let subType = payload.type else { return nil }
            switch subType {
            case "task_started":
                return .running(stepDescription: nil)
            case "task_complete":
                return .waitingText(question: nil)
            case "turn_aborted":
                return .error(description: payload.reason ?? "Turn aborted")
            case "exec_command_end":
                // Tool execution finished — if the overall task is still running,
                // this doesn't change the running state. We only map it if it
                // signals completion of the entire turn, which is handled by
                // task_complete above.
                return nil
            case "agent_message":
                // Streaming message — still running
                return nil
            case "user_message":
                // User input logged — waiting state
                return nil
            default:
                return nil
            }
        case "session_meta", "turn_context", "response_item":
            return nil
        default:
            return nil
        }
    }
}
