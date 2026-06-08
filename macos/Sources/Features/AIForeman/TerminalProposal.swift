import Foundation

/// One terminal's pending decision, pre-chewed into a summary + one suggested action.
/// The unit the user approves. `payload` is what gets sent to the terminal on "Yes".
struct TerminalProposal: Identifiable, Equatable, Sendable {
    let terminalID: String
    let fingerprint: String
    let summary: String
    let actionTitle: String
    let payload: String?
    let kind: AgentInteractionState

    var id: String { "\(terminalID)|\(fingerprint)" }

    /// True when there is a one-tap action to send. When false, the card offers only Edit/No.
    var canSend: Bool { (payload?.isEmpty == false) }
}
