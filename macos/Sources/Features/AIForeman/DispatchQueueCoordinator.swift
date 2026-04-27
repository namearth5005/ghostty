import Foundation

final class DispatchQueueCoordinator {
    private let riskyPatterns = [
        "reset --hard",
        "force-push",
        "rm -rf",
        "deploy",
        "kubectl delete"
    ]

    func requiresConfirmation(_ item: DispatchQueueItem) -> Bool {
        riskyPatterns.contains { item.message.localizedCaseInsensitiveContains($0) }
    }

    static func sendPayload(for message: String) -> String {
        var payload = message
        while payload.last?.isNewline == true {
            payload.removeLast()
        }
        return payload
    }

    @MainActor
    @discardableResult
    func send(_ item: DispatchQueueItem, through controller: TerminalController) -> Bool {
        controller.sendForemanText(Self.sendPayload(for: item.message), to: item.terminalID)
    }
}
