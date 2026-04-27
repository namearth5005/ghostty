import Testing
@testable import Ghostty

struct BaseTerminalControllerTests {
    @MainActor
    @Test
    func foremanSidebarStoreChangesCanBeRelayedToParentObservers() {
        let store = ForemanSidebarStore()
        var changeCount = 0
        let relay = BaseTerminalController.makeForemanSidebarStoreChangeRelay(for: store) {
            changeCount += 1
        }

        store.showSidebar()
        store.hideSidebar()

        withExtendedLifetime(relay) {
            #expect(changeCount == 2)
        }
    }
}
