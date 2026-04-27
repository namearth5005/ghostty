import Testing
@testable import Ghostty

struct DispatchQueueCoordinatorTests {
    @MainActor
    @Test
    func riskyDraftRequiresExtraConfirmationBeforeSend() {
        let coordinator = DispatchQueueCoordinator()
        let item = DispatchQueueItem(
            terminalID: "term-9",
            message: "git reset --hard HEAD~1",
            state: .pending
        )

        #expect(coordinator.requiresConfirmation(item) == true)
    }

    @Test
    func sendPayloadStripsTrailingNewlinesBeforeReturnKeySubmission() {
        let payload = DispatchQueueCoordinator.sendPayload(for: "pnpm test\n\n")

        #expect(payload == "pnpm test")
    }
}
