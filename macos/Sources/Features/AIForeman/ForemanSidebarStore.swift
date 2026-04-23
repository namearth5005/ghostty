import Foundation
import SwiftUI

struct TerminalSummaryRowModel: Identifiable, Equatable, Sendable {
    let terminalID: String
    var title: String
    var cwd: String?
    var state: String
    var summary: String
    var isFocused: Bool

    var id: String { terminalID }
}

enum DispatchQueueItemState: String, Equatable, Sendable {
    case pending
    case sent
    case skipped
}

struct DispatchQueueItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let terminalID: String
    var message: String
    var state: DispatchQueueItemState

    init(
        id: UUID = UUID(),
        terminalID: String,
        message: String,
        state: DispatchQueueItemState = .pending
    ) {
        self.id = id
        self.terminalID = terminalID
        self.message = message
        self.state = state
    }
}

@MainActor
final class ForemanSidebarStore: ObservableObject {
    @Published var terminalRows: [TerminalSummaryRowModel]
    @Published var dispatchQueue: [DispatchQueueItem]
    @Published var userInstruction: String
    @Published var selectedTerminalID: String?

    init(
        terminalRows: [TerminalSummaryRowModel] = [],
        dispatchQueue: [DispatchQueueItem] = [],
        userInstruction: String = "",
        selectedTerminalID: String? = nil
    ) {
        self.terminalRows = terminalRows
        self.dispatchQueue = dispatchQueue
        self.userInstruction = userInstruction
        self.selectedTerminalID = selectedTerminalID
    }

    static var preview: ForemanSidebarStore {
        ForemanSidebarStore(
            terminalRows: [
                .init(
                    terminalID: "term-1",
                    title: "api tests",
                    cwd: "/tmp/project",
                    state: "blocked",
                    summary: "Blocked on an auth assertion failure.",
                    isFocused: true
                ),
                .init(
                    terminalID: "term-2",
                    title: "worker",
                    cwd: "/tmp/project",
                    state: "running",
                    summary: "Still processing a long-running build.",
                    isFocused: false
                )
            ],
            dispatchQueue: [
                .init(terminalID: "term-1", message: "Rerun the failing auth test and explain the failure briefly."),
                .init(terminalID: "term-2", message: "Post a short progress update and keep running.")
            ],
            userInstruction: "Ask the blocked one to retry and the running one to report status.",
            selectedTerminalID: "term-1"
        )
    }

    func sendAndAdvance(currentTerminalID: String) -> String? {
        if let currentIndex = dispatchQueue.firstIndex(where: { $0.terminalID == currentTerminalID && $0.state == .pending }) {
            dispatchQueue[currentIndex].state = .sent
        }

        let nextTerminalID = dispatchQueue.first(where: { $0.state == .pending })?.terminalID
        selectedTerminalID = nextTerminalID
        return nextTerminalID
    }
}
