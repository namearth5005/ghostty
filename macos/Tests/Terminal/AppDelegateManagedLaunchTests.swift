import AppKit
import Testing
@testable import Ghostty

struct AppDelegateManagedLaunchTests {
    @MainActor
    @Test
    func managedLaunchCaptureWritesRequestDetailsToConfiguredGhosttySuite() {
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
        let request = ManagedAgentLaunchRequest(
            identity: .codex,
            workingDirectory: "/tmp/project",
            sourceWindowNumber: 42
        )

        let result = appDelegate.launchManagedAgent(request)
        let capturedDefaults = try! #require(UserDefaults(suiteName: suite))

        #expect(result == "captured-managed-launch-codex")
        #expect(capturedDefaults.string(forKey: "ForemanManagedLaunch.identity") == "codex")
        #expect(capturedDefaults.string(forKey: "ForemanManagedLaunch.location") == "tab")
        #expect(capturedDefaults.string(forKey: "ForemanManagedLaunch.workingDirectory") == "/tmp/project")
        #expect(capturedDefaults.object(forKey: "ForemanManagedLaunch.sourceWindowNumber") as? Int == 42)
    }
}
