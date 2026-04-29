import Foundation
import SwiftUI
import Combine

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

struct DispatchActivityLogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let terminalID: String
    let message: String
    let state: DispatchQueueItemState
    let timestamp: Date
    var outcome: TerminalOutcome?

    init(
        id: UUID = UUID(),
        terminalID: String,
        message: String,
        state: DispatchQueueItemState,
        timestamp: Date = Date(),
        outcome: TerminalOutcome? = nil
    ) {
        self.id = id
        self.terminalID = terminalID
        self.message = message
        self.state = state
        self.timestamp = timestamp
        self.outcome = outcome
    }
}

@MainActor
final class ForemanSidebarStore: ObservableObject {
    @Published var terminalRows: [TerminalSummaryRowModel]
    @Published var dispatchQueue: [DispatchQueueItem]
    @Published var userInstruction: String
    @Published var selectedTerminalID: String?
    @Published var isSidebarVisible: Bool
    @Published var planSummary: String?
    @Published var errorMessage: String?
    @Published var isGeneratingDrafts: Bool
    @Published var activityLog: [DispatchActivityLogEntry]
    @Published var lastActionMessage: String?

    // Agentic conversation state
    @Published var conversation: ForemanConversation
    @Published var chatInput: String = ""
    @Published var isAgentRunning: Bool = false
    var onStartAgent: ((String, AgentMode) -> Void)?
    var onSendChatMessage: ((String) -> Void)?
    var onStopAgent: (() -> Void)?
    var onApproveAction: (() -> Void)?
    var onSkipAction: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(
        terminalRows: [TerminalSummaryRowModel] = [],
        dispatchQueue: [DispatchQueueItem] = [],
        userInstruction: String = "",
        selectedTerminalID: String? = nil,
        isSidebarVisible: Bool = true,
        planSummary: String? = nil,
        errorMessage: String? = nil,
        isGeneratingDrafts: Bool = false,
        activityLog: [DispatchActivityLogEntry] = [],
        lastActionMessage: String? = nil,
        conversation: ForemanConversation? = nil
    ) {
        self.terminalRows = terminalRows
        self.dispatchQueue = dispatchQueue
        self.userInstruction = userInstruction
        self.selectedTerminalID = selectedTerminalID
        self.isSidebarVisible = isSidebarVisible
        self.planSummary = planSummary
        self.errorMessage = errorMessage
        self.isGeneratingDrafts = isGeneratingDrafts
        self.activityLog = activityLog
        self.lastActionMessage = lastActionMessage
        self.conversation = conversation ?? ForemanConversation()

        // Forward conversation changes so SwiftUI re-renders the sidebar
        self.conversation.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
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
            selectedTerminalID: "term-1",
            isSidebarVisible: true,
            planSummary: "Two terminals need input."
        )
    }

    func showSidebar() {
        isSidebarVisible = true
    }

    func hideSidebar() {
        isSidebarVisible = false
    }

    func startAgent(goal: String, mode: AgentMode) {
        chatInput = ""
        isAgentRunning = true
        guard onStartAgent != nil else {
            conversation.errorMessage = "Agent not initialized. Close and reopen the window."
            return
        }
        onStartAgent?(goal, mode)
    }

    func sendChatMessage(_ text: String) {
        chatInput = ""
        onSendChatMessage?(text)
    }

    func stopAgent() {
        isAgentRunning = false
        onStopAgent?()
    }

    func approveAction() {
        onApproveAction?()
    }

    func skipAction() {
        onSkipAction?()
    }

    func applySnapshots(
        _ snapshots: [TerminalSnapshot],
        summariesByTerminalID: [String: TerminalSummary] = [:]
    ) {
        terminalRows = snapshots.map { snapshot in
            if let summary = summariesByTerminalID[snapshot.terminalID] {
                return TerminalSummaryRowModel(
                    terminalID: snapshot.terminalID,
                    title: snapshot.title,
                    cwd: snapshot.cwd,
                    state: summary.state,
                    summary: summary.summary,
                    isFocused: snapshot.isFocused
                )
            }

            return TerminalSummaryRowModel(
                terminalID: snapshot.terminalID,
                title: snapshot.title,
                cwd: snapshot.cwd,
                state: Self.snapshotState(for: snapshot),
                summary: Self.snapshotSummary(for: snapshot),
                isFocused: snapshot.isFocused
            )
        }

        let nextPendingTerminalID = dispatchQueue.first(where: { $0.state == .pending })?.terminalID
        let focusedTerminalID = snapshots.first(where: { $0.isFocused })?.terminalID
        let firstTerminalID = snapshots.first?.terminalID

        if let selectedTerminalID,
           terminalRows.contains(where: { $0.terminalID == selectedTerminalID }) {
            return
        }

        selectedTerminalID = nextPendingTerminalID ?? focusedTerminalID ?? firstTerminalID
    }

    func applyDispatchPlan(
        _ plan: DispatchPlan,
        validTerminalIDs: Set<String>? = nil
    ) {
        let allowedTerminalIDs = validTerminalIDs ?? Set(terminalRows.map(\.terminalID))
        let filteredDrafts = plan.drafts.filter { allowedTerminalIDs.contains($0.terminalID) }
        let skippedDraftCount = plan.drafts.count - filteredDrafts.count

        planSummary = plan.planSummary
        dispatchQueue = filteredDrafts.map {
            DispatchQueueItem(terminalID: $0.terminalID, message: $0.message)
        }

        if let firstPendingTerminalID = dispatchQueue.first(where: { $0.state == .pending })?.terminalID {
            selectedTerminalID = firstPendingTerminalID
        } else if !terminalRows.contains(where: { $0.terminalID == selectedTerminalID }) {
            selectedTerminalID = terminalRows.first?.terminalID
        }

        if skippedDraftCount == 0 {
            errorMessage = nil
        } else if skippedDraftCount == 1 {
            errorMessage = "Skipped 1 draft for a terminal that is no longer available."
        } else {
            errorMessage = "Skipped \(skippedDraftCount) drafts for terminals that are no longer available."
        }
    }

    func sendAndAdvance(currentTerminalID: String) -> String? {
        if let currentIndex = dispatchQueue.firstIndex(where: { $0.terminalID == currentTerminalID && $0.state == .pending }) {
            dispatchQueue[currentIndex].state = .sent
            appendActivityLog(
                terminalID: dispatchQueue[currentIndex].terminalID,
                message: dispatchQueue[currentIndex].message,
                state: .sent
            )
            lastActionMessage = "Sent to \(dispatchQueue[currentIndex].terminalID)."
        }

        let nextTerminalID = dispatchQueue.first(where: { $0.state == .pending })?.terminalID
        selectedTerminalID = nextTerminalID
        return nextTerminalID
    }

    func skipAndAdvance(currentTerminalID: String) -> String? {
        if let currentIndex = dispatchQueue.firstIndex(where: { $0.terminalID == currentTerminalID && $0.state == .pending }) {
            dispatchQueue[currentIndex].state = .skipped
            appendActivityLog(
                terminalID: dispatchQueue[currentIndex].terminalID,
                message: dispatchQueue[currentIndex].message,
                state: .skipped
            )
            lastActionMessage = "Skipped \(dispatchQueue[currentIndex].terminalID)."
        }

        let nextTerminalID = dispatchQueue.first(where: { $0.state == .pending })?.terminalID
        selectedTerminalID = nextTerminalID
        return nextTerminalID
    }

    func clearActivityLog() {
        activityLog.removeAll()
    }

    func clearLastActionMessage() {
        lastActionMessage = nil
    }

    func appendActivityLog(terminalID: String, message: String, state: DispatchQueueItemState) {
        let entry = DispatchActivityLogEntry(
            terminalID: terminalID,
            message: message,
            state: state
        )
        activityLog.append(entry)
        if activityLog.count > 50 {
            activityLog.removeFirst(activityLog.count - 50)
        }
    }

    func updateDraftMessage(itemID: UUID, message: String) {
        guard let index = dispatchQueue.firstIndex(where: { $0.id == itemID }),
              dispatchQueue[index].state == .pending else {
            return
        }

        dispatchQueue[index].message = message
    }

    private static func snapshotState(for snapshot: TerminalSnapshot) -> String {
        if snapshot.signals.likelyErrorState { return "blocked" }
        if snapshot.signals.likelyLongRunning { return "running" }
        if snapshot.signals.likelyWaitingForInput { return "waiting" }
        if snapshot.signals.likelyTUI { return "unsupported" }
        return "idle"
    }

    private static func snapshotSummary(for snapshot: TerminalSnapshot) -> String {
        TerminalContentAnalyzer.analyze(snapshot).summary
    }
}
