import Testing
@testable import Ghostty

struct ManagedAgentRegistryTests {
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
