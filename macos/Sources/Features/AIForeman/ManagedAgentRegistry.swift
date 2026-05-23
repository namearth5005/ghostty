import Foundation

enum ManagedAgentSetupRequirement: String, Codable, Equatable, Sendable {
    case none
    case claudeHooks = "claude_hooks"
}

enum ManagedAgentSetupStatus: Equatable, Sendable {
    case ready
    case requiresOneTimeSetup(ManagedAgentSetupRequirement)
    case unsupportedManualOnly
}

enum AgentReadinessState: Equatable, Sendable {
    case unknown
    case notInstalled
    case installed(loginStatus: LoginStatus)
    
    enum LoginStatus: Equatable, Sendable {
        case unknown
        case notLoggedIn
        case loggedIn
    }
}

enum ManagedAgentLaunchLocation: String, Codable, Equatable, Sendable {
    case tab
    case window
}

struct ManagedAgentLaunchRequest: Equatable, Sendable {
    let identity: AgentIdentity
    let workingDirectory: String?
    let sourceWindowNumber: Int?
    let initialPrompt: String?
    let location: ManagedAgentLaunchLocation

    init(
        identity: AgentIdentity,
        workingDirectory: String? = nil,
        sourceWindowNumber: Int? = nil,
        initialPrompt: String? = nil,
        location: ManagedAgentLaunchLocation = .tab
    ) {
        self.identity = identity
        self.workingDirectory = workingDirectory
        self.sourceWindowNumber = sourceWindowNumber
        self.initialPrompt = initialPrompt
        self.location = location
    }

    func resolvedWindowNumber(
        availableWindowNumbers: [Int],
        fallbackWindowNumber: Int?
    ) -> Int? {
        if let sourceWindowNumber, availableWindowNumbers.contains(sourceWindowNumber) {
            return sourceWindowNumber
        }

        return fallbackWindowNumber
    }
}

struct ManagedAgentDefinition: Equatable, Sendable {
    let identity: AgentIdentity
    let displayName: String
    let executable: String
    let supportLevel: AgentSupportLevel
    let setupRequirement: ManagedAgentSetupRequirement
    let environment: [String: String]

    var setupStatus: ManagedAgentSetupStatus {
        switch setupRequirement {
        case .none:
            return .ready
        case .claudeHooks:
            return .requiresOneTimeSetup(.claudeHooks)
        }
    }

    func makeSurfaceConfiguration(
        workingDirectory: String?,
        initialPrompt: String?
    ) -> Ghostty.SurfaceConfiguration {
        var config = Ghostty.SurfaceConfiguration()
        config.command = executable
        config.workingDirectory = workingDirectory
        config.environmentVariables = environment

        if let initialPrompt, !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.initialInput = initialPrompt + "\n"
        }

        return config
    }
}

enum ManagedAgentRegistry {
    static let supportedAgents: [ManagedAgentDefinition] = [
        .init(
            identity: .claudeCode,
            displayName: "Claude Code",
            executable: "claude",
            supportLevel: .firstClass,
            setupRequirement: .claudeHooks,
            environment: ["CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS": "1"]
        ),
        .init(
            identity: .codex,
            displayName: "Codex",
            executable: "codex",
            supportLevel: .firstClass,
            setupRequirement: .none,
            environment: [:]
        ),
        .init(
            identity: .kimi,
            displayName: "Kimi",
            executable: "kimi",
            supportLevel: .firstClass,
            setupRequirement: .none,
            environment: [:]
        ),
    ]

    static func definition(for identity: AgentIdentity) -> ManagedAgentDefinition? {
        supportedAgents.first(where: { $0.identity == identity })
    }

    static func readiness(for identity: AgentIdentity) -> AgentReadinessState {
        guard let definition = definition(for: identity) else {
            return .unknown
        }
        
        // Check common installation paths directly, since GUI apps don't inherit shell PATH
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "/usr/local/bin/\(definition.executable)",
            "/opt/homebrew/bin/\(definition.executable)",
            "\(home)/.local/bin/\(definition.executable)",
            "\(home)/.cargo/bin/\(definition.executable)",
            "\(home)/.nix-profile/bin/\(definition.executable)",
        ]
        
        let executablePath = commonPaths.first {
            FileManager.default.fileExists(atPath: $0) &&
            FileManager.default.isExecutableFile(atPath: $0)
        }
        
        if executablePath == nil {
            // Fallback: try through login shell which has full PATH
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-lc", "which \(definition.executable)"]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
                guard task.terminationStatus == 0 else {
                    return .notInstalled
                }
            } catch {
                return .notInstalled
            }
        }
        
        // For Kimi, try `kimi info --json` to verify it's functional
        if identity == .kimi {
            let infoTask = Process()
            infoTask.executableURL = URL(fileURLWithPath: "/bin/bash")
            infoTask.arguments = ["-lc", "kimi info --json"]
            infoTask.standardOutput = Pipe()
            infoTask.standardError = Pipe()
            do {
                try infoTask.run()
                infoTask.waitUntilExit()
                if infoTask.terminationStatus == 0 {
                    return .installed(loginStatus: .unknown)
                }
            } catch {
                return .notInstalled
            }
        }
        
        // For other agents, executable existence is enough for now
        return .installed(loginStatus: .unknown)
    }
}
