import Testing
@testable import Ghostty

struct TerminalProposalTests {
    @Test
    func idCombinesTerminalAndFingerprint() {
        let proposal = TerminalProposal(
            terminalID: "t1",
            fingerprint: "fp1",
            summary: "Kimi wants to push to main.",
            actionTitle: "Approve the push",
            payload: "y",
            kind: .waitingApproval
        )

        #expect(proposal.id == "t1|fp1")
        #expect(proposal.canSend)
    }

    @Test
    func proposalWithoutPayloadCannotSend() {
        let proposal = TerminalProposal(
            terminalID: "t1",
            fingerprint: "fp1",
            summary: "Codex hit an error.",
            actionTitle: "Review the error",
            payload: nil,
            kind: .error
        )

        #expect(!proposal.canSend)
    }
}
