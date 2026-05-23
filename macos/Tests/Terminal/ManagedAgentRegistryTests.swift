import Testing
@testable import Ghostty

struct ManagedAgentRegistryTests {
    @Test
    func readinessCanBeForcedInstalledForUIHarness() {
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

        #expect(ManagedAgentRegistry.readiness(for: .codex) == .installed(loginStatus: .loggedIn))
        #expect(ManagedAgentRegistry.readiness(for: .kimi) == .installed(loginStatus: .loggedIn))
        #expect(ManagedAgentRegistry.readiness(for: .claudeCode) == .installed(loginStatus: .loggedIn))
    }

    @Test
    func claudeLaunchProfileRequiresOneTimeSetupAndEnablesStateEvents() {
        let definition = try! #require(ManagedAgentRegistry.definition(for: .claudeCode))
        let configuration = definition.makeSurfaceConfiguration(
            workingDirectory: "/tmp/project",
            initialPrompt: "hello"
        )

        #expect(definition.setupStatus == .requiresOneTimeSetup(.claudeHooks))
        #expect(configuration.command == "claude")
        #expect(configuration.workingDirectory == "/tmp/project")
        #expect(configuration.initialInput == "hello\n")
        #expect(configuration.environmentVariables["CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS"] == "1")
    }

    @Test
    func codexAndKimiLaunchProfilesAreFirstClassWithoutExtraSetup() {
        let codex = try! #require(ManagedAgentRegistry.definition(for: .codex))
        let kimi = try! #require(ManagedAgentRegistry.definition(for: .kimi))

        #expect(codex.setupStatus == .ready)
        #expect(codex.supportLevel == .firstClass)
        #expect(codex.makeSurfaceConfiguration(workingDirectory: nil, initialPrompt: nil).command == "codex")

        #expect(kimi.setupStatus == .ready)
        #expect(kimi.supportLevel == .firstClass)
        #expect(kimi.makeSurfaceConfiguration(workingDirectory: nil, initialPrompt: nil).command == "kimi")
    }

    @Test
    func launchRequestPrefersSourceWindowWhenAvailable() {
        let request = ManagedAgentLaunchRequest(
            identity: .codex,
            sourceWindowNumber: 12
        )

        #expect(
            request.resolvedWindowNumber(
                availableWindowNumbers: [4, 12, 18],
                fallbackWindowNumber: 4
            ) == 12
        )
    }

    @Test
    func launchRequestFallsBackWhenSourceWindowIsUnavailable() {
        let request = ManagedAgentLaunchRequest(
            identity: .kimi,
            sourceWindowNumber: 99
        )

        #expect(
            request.resolvedWindowNumber(
                availableWindowNumbers: [4, 12, 18],
                fallbackWindowNumber: 4
            ) == 4
        )
    }
}
