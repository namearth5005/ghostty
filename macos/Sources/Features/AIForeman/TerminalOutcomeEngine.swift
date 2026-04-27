import Foundation

final class TerminalOutcomeEngine {
    struct MonitoredTerminal {
        let terminalID: String
        let sentCommand: String
        let startTime: Date
        var lastSnapshot: TerminalSnapshot?
        var lastCheckTime: Date
    }

    private var monitored: [String: MonitoredTerminal] = [:]
    private var timer: Timer?
    private let captureSnapshot: @MainActor (String) -> TerminalSnapshot?
    private let onOutcome: @MainActor (TerminalOutcomeReport) -> Void
    private let parsers: [TerminalOutputParser]

    init(
        captureSnapshot: @escaping @MainActor (String) -> TerminalSnapshot?,
        onOutcome: @escaping @MainActor (TerminalOutcomeReport) -> Void,
        parsers: [TerminalOutputParser] = [TestOutputParser(), GitStatusParser()]
    ) {
        self.captureSnapshot = captureSnapshot
        self.onOutcome = onOutcome
        self.parsers = parsers
    }

    func register(terminalID: String, sentCommand: String) {
        monitored[terminalID] = MonitoredTerminal(
            terminalID: terminalID,
            sentCommand: sentCommand,
            startTime: Date(),
            lastSnapshot: nil,
            lastCheckTime: Date()
        )
        ensureTimerRunning()
    }

    func cancelMonitoring(terminalID: String) {
        monitored.removeValue(forKey: terminalID)
        if monitored.isEmpty {
            stopTimer()
        }
    }

    private func ensureTimerRunning() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    func tick() {
        let now = Date()
        var completed: [String] = []

        for terminalID in monitored.keys {
            guard var monitor = monitored[terminalID] else { continue }
            defer { monitored[terminalID] = monitor }

            guard let snapshot = captureSnapshot(terminalID) else {
                completed.append(terminalID)
                continue
            }

            let timeout = snapshot.signals.likelyLongRunning ? 60.0 : 30.0

            if now.timeIntervalSince(monitor.startTime) > timeout {
                let report = makeReport(
                    terminalID: terminalID,
                    command: monitor.sentCommand,
                    outcome: .hung,
                    snapshot: snapshot,
                    summary: "No outcome detected within \(Int(timeout))s."
                )
                onOutcome(report)
                completed.append(terminalID)
                continue
            }

            if monitor.lastSnapshot == nil {
                monitor.lastSnapshot = snapshot
                monitor.lastCheckTime = now
                continue
            }

            if let outcome = classifyOutcome(
                previous: monitor.lastSnapshot!,
                current: snapshot,
                command: monitor.sentCommand
            ) {
                let report = makeReport(
                    terminalID: terminalID,
                    command: monitor.sentCommand,
                    outcome: outcome,
                    snapshot: snapshot,
                    summary: outcomeSummary(outcome: outcome, snapshot: snapshot)
                )
                onOutcome(report)
                completed.append(terminalID)
                continue
            }

            monitor.lastSnapshot = snapshot
            monitor.lastCheckTime = now
        }

        for terminalID in completed {
            monitored.removeValue(forKey: terminalID)
        }

        if monitored.isEmpty {
            stopTimer()
        }
    }

    private func makeReport(
        terminalID: String,
        command: String,
        outcome: TerminalOutcome,
        snapshot: TerminalSnapshot,
        summary: String?
    ) -> TerminalOutcomeReport {
        var parsed: ParsedTerminalOutput?
        for parser in parsers {
            if let result = parser.parse(visibleText: snapshot.visibleText, scrollback: snapshot.recentScrollback) {
                parsed = result
                break
            }
        }
        return TerminalOutcomeReport(
            id: UUID(),
            terminalID: terminalID,
            sentCommand: command,
            outcome: outcome,
            detectedAt: Date(),
            summary: summary,
            parsedOutput: parsed
        )
    }

    private func classifyOutcome(
        previous: TerminalSnapshot,
        current: TerminalSnapshot,
        command: String
    ) -> TerminalOutcome? {
        let prevText = previous.visibleText
        let currText = current.visibleText

        if prevText == currText {
            return nil
        }

        let newLines = extractNewLines(previous: prevText, current: currText)
        let newText = newLines.joined(separator: "\n")

        if isInputPrompt(newText) {
            return .needsInput
        }

        if TerminalSnapshot.isLikelyErrorState(newText) {
            return .failure
        }

        if hasSuccessMarkers(newText) {
            return .success
        }

        if !previous.signals.likelyWaitingForInput && current.signals.likelyWaitingForInput {
            return .success
        }

        return nil
    }

    private func extractNewLines(previous: String, current: String) -> [String] {
        let prevLines = Set(previous.split(separator: "\n").map { String($0) })
        let currLines = current.split(separator: "\n").map { String($0) }
        return currLines.filter { !prevLines.contains($0) }
    }

    private func isInputPrompt(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("password:")
            || lowered.contains("passphrase:")
            || lowered.contains("[y/n]")
            || lowered.contains("(yes/no)")
            || lowered.contains("[y/n/i]")
            || lowered.contains("enter token")
    }

    private func hasSuccessMarkers(_ text: String) -> Bool {
        let markers = ["✓", "✔", "pass", "done", "success", "finished", "completed", "ok", "built", "compiled"]
        let lowered = text.lowercased()
        return markers.contains { lowered.contains($0) }
    }

    private func outcomeSummary(outcome: TerminalOutcome, snapshot: TerminalSnapshot) -> String {
        switch outcome {
        case .success:
            if let parsed = snapshot.visibleText.split(separator: "\n").last {
                return "Completed: \(String(parsed).prefix(80))"
            }
            return "Command completed successfully."
        case .failure:
            if let errorLine = snapshot.visibleText.split(separator: "\n").last(where: {
                TerminalSnapshot.isLikelyErrorState(String($0))
            }) {
                return "Failed: \(String(errorLine).prefix(80))"
            }
            return "Command failed."
        case .hung:
            return "Command timed out without returning to prompt."
        case .needsInput:
            return "Waiting for user input."
        case .stillRunning:
            return "Command is still running."
        case .unknown:
            return "Outcome unknown."
        }
    }
}
