import XCTest

final class ForemanManagedLaunchUITests: GhosttyCustomConfigCase {
    private struct ManagedLaunchCase {
        let identity: String
        let accessibilityIdentifier: String
        let fallbackLabel: String
    }

    override static var runsForEachTargetApplicationUIConfiguration: Bool { false }

    @MainActor
    func testLaunchButtonsCaptureManagedLaunchRequestsFromForemanSidebar() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GHOSTTY_RUN_FOREMAN_MANAGED_LAUNCH_UI_TESTS"] == "1",
            "Managed-launch UI harness is opt-in because native macOS UI automation is flaky in CI-like runs."
        )
        // For live host-side checks outside XCTest, prefer the sibling
        // `foreman-managed-launch-manual.sh` launcher so the current build path
        // is used instead of whichever stale debug bundle Launch Services finds.
        // `foreman-managed-launch-manual.sh --verify-launches` also exercises the
        // three visible launch rows against the managed-launch capture suite.

        try updateConfig(
            """
            window-position-x = 50
            window-position-y = 50
            window-width = 70
            window-height = 24
            title = "ForemanManagedLaunchUITests"
            """
        )

        let defaultsSuite = "GHOSTTY_UI_TESTS_FOREMAN_MANAGED_LAUNCH"
        UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)

        let externalWindowMonitor = addUIInterruptionMonitor(withDescription: "Dismiss external windows") { element in
            let closeButton = element.buttons["_XCUI:CloseWindow"].firstMatch
            guard closeButton.exists else {
                return false
            }

            closeButton.click()
            return true
        }
        defer { removeUIInterruptionMonitor(externalWindowMonitor) }

        let app = try ghosttyApplication(defaultsSuite: defaultsSuite)
        app.launchEnvironment["GHOSTTY_CLEAR_USER_DEFAULTS"] = "YES"
        app.launchEnvironment["GHOSTTY_FOREMAN_TEST_FORCE_AGENT_READINESS"] = "installed"
        app.launchEnvironment["GHOSTTY_FOREMAN_TEST_CAPTURE_MANAGED_LAUNCH"] = "1"
        app.launchEnvironment["GHOSTTY_FOREMAN_TEST_START_VISIBLE"] = "1"
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Main terminal window should exist")

        XCTAssertTrue(
            app.staticTexts["Foreman Agent"].waitForExistence(timeout: 5),
            "Foreman sidebar should be visible for the managed-launch harness"
        )

        let launchCases = [
            ManagedLaunchCase(
                identity: "claude_code",
                accessibilityIdentifier: "foreman.launch.claude_code",
                fallbackLabel: "Launch Claude Code"
            ),
            ManagedLaunchCase(
                identity: "codex",
                accessibilityIdentifier: "foreman.launch.codex",
                fallbackLabel: "Launch Codex"
            ),
            ManagedLaunchCase(
                identity: "kimi",
                accessibilityIdentifier: "foreman.launch.kimi",
                fallbackLabel: "Launch Kimi"
            ),
        ]

        let capturedDefaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))

        for launchCase in launchCases {
            capturedDefaults.removePersistentDomain(forName: defaultsSuite)

            let launchButton = app.buttons[launchCase.accessibilityIdentifier].firstMatch
            let launchButtonExists =
                launchButton.waitForExistence(timeout: 5) ||
                app.buttons[launchCase.fallbackLabel].firstMatch.waitForExistence(timeout: 5)
            let resolvedButton = launchButton.exists ? launchButton : app.buttons[launchCase.fallbackLabel].firstMatch

            XCTAssertTrue(
                launchButtonExists,
                "\(launchCase.identity) launch button should exist when Foreman is visible"
            )

            if resolvedButton.isHittable {
                resolvedButton.click()
            } else {
                resolvedButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }

            let capturedLaunch = try XCTUnwrap(
                waitForManagedLaunchCapture(in: defaultsSuite, identity: launchCase.identity)
            )
            XCTAssertEqual(capturedLaunch.string(forKey: "ForemanManagedLaunch.identity"), launchCase.identity)
            XCTAssertEqual(capturedLaunch.string(forKey: "ForemanManagedLaunch.location"), "tab")
            XCTAssertNotNil(capturedLaunch.string(forKey: "ForemanManagedLaunch.workingDirectory"))
            XCTAssertNotNil(capturedLaunch.object(forKey: "ForemanManagedLaunch.sourceWindowNumber") as? Int)
            XCTAssertTrue(window.exists, "Managed-launch click should leave the app responsive")
        }

        app.terminate()
    }

    private func waitForManagedLaunchCapture(
        in defaultsSuite: String,
        identity: String,
        timeout: TimeInterval = 5
    ) -> UserDefaults? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let defaults = UserDefaults(suiteName: defaultsSuite),
               defaults.string(forKey: "ForemanManagedLaunch.identity") == identity,
               defaults.string(forKey: "ForemanManagedLaunch.location") == "tab",
               defaults.string(forKey: "ForemanManagedLaunch.workingDirectory")?.isEmpty == false,
               defaults.object(forKey: "ForemanManagedLaunch.sourceWindowNumber") as? Int != nil {
                return defaults
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return nil
    }
}
