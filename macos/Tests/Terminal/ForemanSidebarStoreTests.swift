import Testing
@testable import Ghostty

struct ForemanSidebarStoreTests {
    @MainActor
    @Test
    func storeBuildsVisibleRowsAndSelectsNextPendingDraft() {
        let store = ForemanSidebarStore.preview
        store.dispatchQueue = [
            .init(terminalID: "term-1", message: "first", state: .pending),
            .init(terminalID: "term-2", message: "second", state: .pending)
        ]

        let next = store.sendAndAdvance(currentTerminalID: "term-1")

        #expect(store.dispatchQueue[0].state == .sent)
        #expect(next == "term-2")
        #expect(store.selectedTerminalID == "term-2")
    }
}
