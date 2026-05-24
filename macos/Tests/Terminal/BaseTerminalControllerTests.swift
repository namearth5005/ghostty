import Testing
@testable import Ghostty

struct BaseTerminalControllerTests {
    @MainActor
    @Test
    func foremanSidebarStoreChangesCanBeRelayedToParentObservers() {
        let key = "GHOSTTY_FOREMAN_TEST_FORCE_AGENT_READINESS"
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, "installed", 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }

        let store = ForemanSidebarStore()
        var changeCount = 0
        let relay = BaseTerminalController.makeForemanSidebarStoreChangeRelay(for: store) {
            changeCount += 1
        }

        store.showSidebar()
        store.hideSidebar()

        withExtendedLifetime(relay) {
            #expect(changeCount >= 2)
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

    @Test
    func managedAgentLaunchHandlerUsesCurrentContextWhenInvoked() {
        var currentWorkingDirectory: String? = "/tmp/project-one"
        var currentWindowNumber: Int? = 42
        var capturedRequests: [ManagedAgentLaunchRequest] = []

        let handler = BaseTerminalController.makeManagedAgentLaunchHandler(
            currentWorkingDirectory: { currentWorkingDirectory },
            currentSourceWindowNumber: { currentWindowNumber },
            launchManagedAgent: { request in
                capturedRequests.append(request)
                return "captured-\(request.identity.rawValue)"
            }
        )

        handler(.codex)

        currentWorkingDirectory = "/tmp/project-two"
        currentWindowNumber = 43

        handler(.kimi)

        #expect(capturedRequests == [
            ManagedAgentLaunchRequest(
                identity: .codex,
                workingDirectory: "/tmp/project-one",
                sourceWindowNumber: 42
            ),
            ManagedAgentLaunchRequest(
                identity: .kimi,
                workingDirectory: "/tmp/project-two",
                sourceWindowNumber: 43
            ),
        ])
    }
}
