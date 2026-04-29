import Foundation
import AppKit
import UserNotifications

@MainActor
class ForemanNotifier {
    static let shared = ForemanNotifier()

    private var lastOutcomes: [String: TerminalOutcome] = [:]
    private var authorized = false

    private init() {}

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.authorized = granted
            }
        }
    }

    func observe(report: TerminalOutcomeReport) {
        guard authorized else { return }

        let previous = lastOutcomes[report.terminalID]
        lastOutcomes[report.terminalID] = report.outcome

        guard let previous = previous else { return }
        guard previous != report.outcome else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default

        var shouldNotify = true

        switch (previous, report.outcome) {
        case (_, .failure):
            content.title = "Command Failed"
            content.body = "\(report.sentCommand) failed in terminal."

        case (_, .success):
            content.title = "Command Succeeded"
            content.body = "\(report.sentCommand) completed successfully."

        case (_, .needsInput):
            content.title = "Input Required"
            content.body = "Terminal is waiting for input."

        case (_, .hung):
            content.title = "Command Stuck"
            content.body = "\(report.sentCommand) appears to be hung."

        default:
            shouldNotify = false
        }

        guard shouldNotify else { return }
        guard !isAppFocusedAndSidebarVisible() else { return }

        let request = UNNotificationRequest(
            identifier: "foreman-outcome-\(report.id.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func isAppFocusedAndSidebarVisible() -> Bool {
        guard NSApp.isActive else { return false }
        guard let keyWindow = NSApp.keyWindow else { return false }
        guard keyWindow.windowController is TerminalController else { return false }

        // If we can find a visible Foreman sidebar in the key window, suppress notification
        // This is a heuristic — we check if the window's first responder chain contains
        // a Foreman-related view or if the sidebar is known to be open.
        // For simplicity, we suppress if Foreman is the focused app and any terminal window is key.
        return true
    }
}
