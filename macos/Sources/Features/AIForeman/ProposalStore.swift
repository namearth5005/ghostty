import Foundation
import SwiftUI

/// Holds the single current proposal for a terminal sidebar and exposes the
/// approve / reject / edit interactions. All decisions leave via the callbacks.
@MainActor
final class ProposalStore: ObservableObject {
    @Published private(set) var current: TerminalProposal?
    @Published var draft: String = ""
    @Published private(set) var isEditing: Bool = false
    @Published var errorMessage: String?

    /// Called when the user approves: send `payload` to `proposal.terminalID`.
    var onApprove: ((_ proposal: TerminalProposal, _ payload: String) -> Void)?
    /// Called when the user rejects: dismiss without sending.
    var onReject: ((_ proposal: TerminalProposal) -> Void)?

    /// Replace the current proposal. A proposal with the same `id` is treated as a
    /// no-op so a repeated capture tick does not disrupt an in-progress edit.
    func present(_ proposal: TerminalProposal) {
        if current?.id == proposal.id {
            return
        }
        current = proposal
        draft = proposal.payload ?? ""
        isEditing = false
        errorMessage = nil
    }

    /// Drop the proposal if it belongs to `terminalID` (the terminal moved on).
    func clear(terminalID: String) {
        guard current?.terminalID == terminalID else { return }
        reset()
    }

    func beginEdit() {
        guard let current else { return }
        draft = current.payload ?? ""
        isEditing = true
    }

    func cancelEdit() {
        isEditing = false
        draft = current?.payload ?? ""
    }

    func approve() {
        guard let proposal = current, let payload = proposal.payload, !payload.isEmpty else { return }
        onApprove?(proposal, payload)
        reset()
    }

    func approveEdited() {
        guard let proposal = current else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onApprove?(proposal, text)
        reset()
    }

    func reject() {
        guard let proposal = current else { return }
        onReject?(proposal)
        reset()
    }

    private func reset() {
        current = nil
        draft = ""
        isEditing = false
        errorMessage = nil
    }
}
