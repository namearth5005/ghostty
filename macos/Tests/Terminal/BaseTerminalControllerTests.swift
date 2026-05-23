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

    @Test
    func managedAgentLaunchRequestUsesFocusedWorkingDirectoryAndTabLocation() {
        let request = BaseTerminalController.makeManagedAgentLaunchRequest(
            identity: .codex,
            workingDirectory: "/tmp/project",
            sourceWindowNumber: 42
        )

        #expect(request.identity == .codex)
        #expect(request.workingDirectory == "/tmp/project")
        #expect(request.sourceWindowNumber == 42)
        #expect(request.initialPrompt == nil)
        #expect(request.location == .tab)
    }

    @Test
    func managedAgentLaunchRequestPreservesExplicitOverrides() {
        let request = BaseTerminalController.makeManagedAgentLaunchRequest(
            identity: .claudeCode,
            workingDirectory: nil,
            sourceWindowNumber: nil,
            initialPrompt: "review this branch",
            location: .window
        )

        #expect(request.identity == .claudeCode)
        #expect(request.workingDirectory == nil)
        #expect(request.sourceWindowNumber == nil)
        #expect(request.initialPrompt == "review this branch")
        #expect(request.location == .window)
    }
}
