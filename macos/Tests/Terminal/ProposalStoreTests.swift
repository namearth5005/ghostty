import Testing
@testable import Ghostty

@MainActor
struct ProposalStoreTests {
    private func proposal(_ fingerprint: String, payload: String? = "y") -> TerminalProposal {
        TerminalProposal(
            terminalID: "t1",
            fingerprint: fingerprint,
            summary: "Kimi wants to push to main.",
            actionTitle: "Approve",
            payload: payload,
            kind: .waitingApproval
        )
    }

    @Test
    func approveSendsPayloadAndClears() {
        let store = ProposalStore()
        var sent: [(terminalID: String, payload: String)] = []
        store.onApprove = { proposal, payload in sent.append((proposal.terminalID, payload)) }

        store.present(proposal("fp1"))
        store.approve()

        #expect(sent.count == 1)
        #expect(sent[0].payload == "y")
        #expect(store.current == nil)
    }

    @Test
    func rejectClearsWithoutSending() {
        let store = ProposalStore()
        var approved = false
        var rejectedTerminalID: String?
        store.onApprove = { _, _ in approved = true }
        store.onReject = { proposal in rejectedTerminalID = proposal.terminalID }

        store.present(proposal("fp1"))
        store.reject()

        #expect(!approved)
        #expect(rejectedTerminalID == "t1")
        #expect(store.current == nil)
    }

    @Test
    func editedApprovalSendsDraftText() {
        let store = ProposalStore()
        var sent: String?
        store.onApprove = { _, payload in sent = payload }

        store.present(proposal("fp1"))
        store.beginEdit()
        store.draft = "no, stop"
        store.approveEdited()

        #expect(sent == "no, stop")
        #expect(store.current == nil)
    }

    @Test
    func newFingerprintReplacesStaleProposal() {
        let store = ProposalStore()
        store.present(proposal("fp1", payload: "old"))
        store.present(proposal("fp2", payload: "new"))

        #expect(store.current?.fingerprint == "fp2")
        #expect(store.draft == "new")
    }

    @Test
    func sameProposalDoesNotResetInProgressEdit() {
        let store = ProposalStore()
        store.present(proposal("fp1", payload: "y"))
        store.beginEdit()
        store.draft = "half-typed reply"
        store.present(proposal("fp1", payload: "y"))

        #expect(store.isEditing)
        #expect(store.draft == "half-typed reply")
    }

    @Test
    func clearForMatchingTerminalRemovesCard() {
        let store = ProposalStore()
        store.present(proposal("fp1"))
        store.clear(terminalID: "t1")

        #expect(store.current == nil)
    }

    @Test
    func clearForOtherTerminalLeavesCard() {
        let store = ProposalStore()
        store.present(proposal("fp1"))
        store.clear(terminalID: "other")

        #expect(store.current?.fingerprint == "fp1")
    }
}
