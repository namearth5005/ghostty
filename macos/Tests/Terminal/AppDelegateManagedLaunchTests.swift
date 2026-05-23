import AppKit
import Testing
@testable import Ghostty

struct AppDelegateManagedLaunchTests {
    @MainActor
    @Test
    func managedLaunchCaptureWritesRequestDetailsForSupportedAgents() {
        let suite = "GHOSTTY_TEST_MANAGED_LAUNCH_\(UUID().uuidString)"
        let defaults = try! #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let suiteKey = "GHOSTTY_USER_DEFAULTS_SUITE"
        let captureKey = "GHOSTTY_FOREMAN_TEST_CAPTURE_MANAGED_LAUNCH"
        let previousSuite = getenv(suiteKey).map { String(cString: $0) }
        let previousCapture = getenv(captureKey).map { String(cString: $0) }

        setenv(suiteKey, suite, 1)
        setenv(captureKey, "1", 1)
        defer {
            if let previousSuite {
                setenv(suiteKey, previousSuite, 1)
            } else {
                unsetenv(suiteKey)
            }

            if let previousCapture {
                setenv(captureKey, previousCapture, 1)
            } else {
                unsetenv(captureKey)
            }

            defaults.removePersistentDomain(forName: suite)
        }

        let appDelegate = try! #require(NSApp.delegate as? AppDelegate)
        let capturedDefaults = try! #require(UserDefaults(suiteName: suite))
        let cases: [(request: ManagedAgentLaunchRequest, expectedResult: String)] = [
            (
                ManagedAgentLaunchRequest(
                    identity: .codex,
                    workingDirectory: "/tmp/codex-project",
                    sourceWindowNumber: 42,
                    location: .tab
                ),
                "captured-managed-launch-codex"
            ),
            (
                ManagedAgentLaunchRequest(
                    identity: .kimi,
                    workingDirectory: "/tmp/kimi-project",
                    sourceWindowNumber: 43,
                    location: .tab
                ),
                "captured-managed-launch-kimi"
            ),
            (
                ManagedAgentLaunchRequest(
                    identity: .claudeCode,
                    workingDirectory: "/tmp/claude-project",
                    sourceWindowNumber: 44,
                    location: .window
                ),
                "captured-managed-launch-claude_code"
            ),
        ]

        for entry in cases {
            defaults.removePersistentDomain(forName: suite)

            let result = appDelegate.launchManagedAgent(entry.request)

            #expect(result == entry.expectedResult)
            #expect(capturedDefaults.string(forKey: "ForemanManagedLaunch.identity") == entry.request.identity.rawValue)
            #expect(capturedDefaults.string(forKey: "ForemanManagedLaunch.location") == entry.request.location.rawValue)
            #expect(capturedDefaults.string(forKey: "ForemanManagedLaunch.workingDirectory") == entry.request.workingDirectory)
            #expect(capturedDefaults.object(forKey: "ForemanManagedLaunch.sourceWindowNumber") as? Int == entry.request.sourceWindowNumber)
        }
    }
}
