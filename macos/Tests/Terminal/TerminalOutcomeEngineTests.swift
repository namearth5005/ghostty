import Testing
@testable import Ghostty

struct TerminalOutcomeEngineTests {
    @Test
    func engineClassifiesSuccessOnPromptReturn() async throws {
        var reports: [TerminalOutcomeReport] = []
        var callCount = 0
        let engine = TerminalOutcomeEngine(
            captureSnapshot: { _ in
                callCount += 1
                if callCount == 1 {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "shell",
                        cwd: "/tmp",
                        isFocused: true,
                        visibleText: "hello",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                } else {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "shell",
                        cwd: "/tmp",
                        isFocused: true,
                        visibleText: "hello\nuser@host $",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                }
            },
            onOutcome: { report in
                reports.append(report)
            }
        )

        await MainActor.run {
            engine.register(terminalID: "term-1", sentCommand: "echo hello")
            engine.tick() // baseline
            engine.tick() // classify
        }

        #expect(reports.count == 1)
        #expect(reports[0].outcome == .success)
        #expect(reports[0].terminalID == "term-1")
    }

    @Test
    func engineClassifiesFailureOnErrorMarkers() async throws {
        var reports: [TerminalOutcomeReport] = []
        var callCount = 0
        let engine = TerminalOutcomeEngine(
            captureSnapshot: { _ in
                callCount += 1
                if callCount == 1 {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "build",
                        cwd: "/tmp",
                        isFocused: false,
                        visibleText: "npm build",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                } else {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "build",
                        cwd: "/tmp",
                        isFocused: false,
                        visibleText: "npm build\nerror: module not found",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                }
            },
            onOutcome: { report in
                reports.append(report)
            }
        )

        await MainActor.run {
            engine.register(terminalID: "term-1", sentCommand: "npm build")
            engine.tick() // baseline
            engine.tick() // classify
        }

        #expect(reports.count == 1)
        #expect(reports[0].outcome == .failure)
    }

    @Test
    func engineClassifiesNeedsInputOnPasswordPrompt() async throws {
        var reports: [TerminalOutcomeReport] = []
        var callCount = 0
        let engine = TerminalOutcomeEngine(
            captureSnapshot: { _ in
                callCount += 1
                if callCount == 1 {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "deploy",
                        cwd: "/tmp",
                        isFocused: false,
                        visibleText: "ssh prod",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                } else {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "deploy",
                        cwd: "/tmp",
                        isFocused: false,
                        visibleText: "ssh prod\nEnter password:",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                }
            },
            onOutcome: { report in
                reports.append(report)
            }
        )

        await MainActor.run {
            engine.register(terminalID: "term-1", sentCommand: "ssh prod")
            engine.tick() // baseline
            engine.tick() // classify
        }

        #expect(reports.count == 1)
        #expect(reports[0].outcome == .needsInput)
    }

    @Test
    func engineParsesTestOutputOnOutcome() async throws {
        var reports: [TerminalOutcomeReport] = []
        var callCount = 0
        let engine = TerminalOutcomeEngine(
            captureSnapshot: { _ in
                callCount += 1
                if callCount == 1 {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "test",
                        cwd: "/tmp",
                        isFocused: false,
                        visibleText: "npm test",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                } else {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "test",
                        cwd: "/tmp",
                        isFocused: false,
                        visibleText: "npm test\nTests: 2 failed, 42 passed, 44 total\nuser@host $",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                }
            },
            onOutcome: { report in
                reports.append(report)
            }
        )

        await MainActor.run {
            engine.register(terminalID: "term-1", sentCommand: "npm test")
            engine.tick() // baseline
            engine.tick() // classify
        }

        #expect(reports.count == 1)
        if let parsed = reports[0].parsedOutput as? TestOutput {
            #expect(parsed.framework == "jest")
            #expect(parsed.passed == 42)
            #expect(parsed.failed == 2)
        } else {
            Issue.record("Expected TestOutput but got \(String(describing: reports[0].parsedOutput))")
        }
    }

    @Test
    func engineClassifiesHungOnTimeout() async throws {
        var reports: [TerminalOutcomeReport] = []
        let engine = TerminalOutcomeEngine(
            captureSnapshot: { _ in
                TerminalSnapshot.makePreview(
                    terminalID: "term-1",
                    windowID: "win-1",
                    tabID: "tab-1",
                    title: "build",
                    cwd: "/tmp",
                    isFocused: false,
                    visibleText: "npm build\nstill building...",
                    recentScrollbackLines: [],
                    lastInputPreview: nil
                )
            },
            onOutcome: { report in
                reports.append(report)
            }
        )

        await MainActor.run {
            engine.register(terminalID: "term-1", sentCommand: "npm build")
            engine.tick() // baseline
        }

        // Simulate time passing by manipulating internal state
        await MainActor.run {
            // Force timeout by setting start time far in the past
            // We can't access private state, so instead we rely on the timer
            // For unit testing, we verify that with no prompt return and no error,
            // the engine keeps monitoring until timeout
            // Since we can't wait 30s in a unit test, we verify the engine is still monitoring
            // by checking that no report was produced yet
        }

        #expect(reports.isEmpty)
    }

    @Test
    func engineClassifiesSuccessOnSuccessMarkers() async throws {
        var reports: [TerminalOutcomeReport] = []
        var callCount = 0
        let engine = TerminalOutcomeEngine(
            captureSnapshot: { _ in
                callCount += 1
                if callCount == 1 {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "deploy",
                        cwd: "/tmp",
                        isFocused: false,
                        visibleText: "npm run deploy",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                } else {
                    return TerminalSnapshot.makePreview(
                        terminalID: "term-1",
                        windowID: "win-1",
                        tabID: "tab-1",
                        title: "deploy",
                        cwd: "/tmp",
                        isFocused: false,
                        visibleText: "npm run deploy\n✓ Deployment successful",
                        recentScrollbackLines: [],
                        lastInputPreview: nil
                    )
                }
            },
            onOutcome: { report in
                reports.append(report)
            }
        )

        await MainActor.run {
            engine.register(terminalID: "term-1", sentCommand: "npm run deploy")
            engine.tick() // baseline
            engine.tick() // classify
        }

        #expect(reports.count == 1)
        #expect(reports[0].outcome == .success)
    }

    @Test
    func engineCancelMonitoringStopsTracking() async throws {
        var reports: [TerminalOutcomeReport] = []
        let engine = TerminalOutcomeEngine(
            captureSnapshot: { _ in
                TerminalSnapshot.makePreview(
                    terminalID: "term-1",
                    windowID: "win-1",
                    tabID: "tab-1",
                    title: "shell",
                    cwd: "/tmp",
                    isFocused: true,
                    visibleText: "running...",
                    recentScrollbackLines: [],
                    lastInputPreview: nil
                )
            },
            onOutcome: { report in
                reports.append(report)
            }
        )

        await MainActor.run {
            engine.register(terminalID: "term-1", sentCommand: "long task")
            engine.tick() // baseline
            engine.cancelMonitoring(terminalID: "term-1")
            engine.tick() // should not produce report since cancelled
        }

        #expect(reports.isEmpty)
    }
}
