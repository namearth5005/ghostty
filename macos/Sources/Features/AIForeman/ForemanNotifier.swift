import Foundation
import AppKit
import UserNotifications

@MainActor
class ForemanNotifier {
    static let shared = ForemanNotifier()

    struct NotificationMessage: Equatable {
        let title: String
        let body: String
    }

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

    func observe(report: TerminalOutcomeReport, summaryOverride: String? = nil) {
        guard authorized else { return }

        let previous = lastOutcomes[report.terminalID]
        lastOutcomes[report.terminalID] = report.outcome

        guard let message = Self.notificationMessage(
            previous: previous,
            report: report,
            summaryOverride: summaryOverride
        ) else { return }
        guard !isAppFocusedAndSidebarVisible() else { return }

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "foreman-outcome-\(report.id.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Notify the user about a pending proposal when the app is not in the foreground.
    func notifyProposal(terminalID: String, summary: String) {
        guard authorized else { return }
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "Foreman needs you"
        content.body = summary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "foreman-proposal-\(terminalID)",
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

    nonisolated static func notificationMessage(
        previous: TerminalOutcome?,
        report: TerminalOutcomeReport,
        summaryOverride: String?
    ) -> NotificationMessage? {
        guard let previous else { return nil }
        guard previous != report.outcome else { return nil }

        let fallbackBody: String?
        switch report.outcome {
        case .failure:
            fallbackBody = report.summary ?? "\(report.terminalID): \(report.sentCommand) failed."
        case .success:
            fallbackBody = report.summary ?? "\(report.terminalID): \(report.sentCommand) completed successfully."
        case .needsInput:
            fallbackBody = report.summary ?? "\(report.terminalID): waiting for input."
        case .hung:
            fallbackBody = report.summary ?? "\(report.terminalID): \(report.sentCommand) appears to be hung."
        case .unknown, .stillRunning:
            fallbackBody = nil
        }

        guard let body = summaryOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? fallbackBody else {
            return nil
        }

        return NotificationMessage(
            title: "Foreman Update",
            body: body
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
