import SwiftUI

struct ProposalCardView: View {
    @ObservedObject var store: ProposalStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let proposal = store.current {
                card(for: proposal)
            } else {
                idleState
            }
        }
        .frame(minWidth: 300, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Foreman")
                .font(.system(size: 18, weight: .bold))
            Text("Watching your terminals. I'll let you know when one needs you.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private func card(for proposal: TerminalProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Needs you · \(proposal.terminalID)", systemImage: "exclamationmark.bubble.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)

            Text(proposal.summary)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)

            if store.isEditing {
                TextField("Your reply", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                HStack(spacing: 8) {
                    Button("Send") { store.approveEdited() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { store.cancelEdit() }
                        .buttonStyle(.bordered)
                }
            } else {
                Text("Suggested: \(proposal.actionTitle)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if proposal.canSend {
                        Button("✓ Yes") { store.approve() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("✗ No") { store.reject() }
                        .buttonStyle(.bordered)
                    Button("✎ Edit") { store.beginEdit() }
                        .buttonStyle(.bordered)
                }
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }
}

#Preview("Waiting") {
    let store = ProposalStore()
    store.present(
        TerminalProposal(
            terminalID: "term-2",
            fingerprint: "fp1",
            summary: "Kimi wants to push to main. Tests passed, so I'd let it.",
            actionTitle: "Approve the push",
            payload: "y",
            kind: .waitingApproval
        )
    )
    return ProposalCardView(store: store)
}

#Preview("Idle") {
    ProposalCardView(store: ProposalStore())
}
