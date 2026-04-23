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

    @MainActor
    @discardableResult
    func send(_ item: DispatchQueueItem, through controller: TerminalController) -> Bool {
        controller.sendForemanText(item.message, to: item.terminalID)
    }
}
