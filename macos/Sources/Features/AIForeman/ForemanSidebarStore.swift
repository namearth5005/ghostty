import Foundation
import SwiftUI
import Combine

struct TerminalSummaryRowModel: Identifiable, Equatable, Sendable {
    let terminalID: String
    var title: String
    var cwd: String?
    var state: String
    var summary: String
    var agentIdentity: String?
    var agentInteractionState: String?
    var supportLevel: String?
    var evidenceSummary: String?
    var isFocused: Bool
    var suggestedActions: [TerminalSuggestedAction]
    var pendingAttention: PendingAgentAttention?
    
    // NEW: Rich agent context for UX
    var agentContextType: String?
    var agentContextTitle: String?
    var agentContextDescription: String?
    var agentContextDetail: String?
    var agentContextOptions: [String]?

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

enum PendingAgentAttentionStatus: String, Equatable, Sendable {
    case awaitingUser
    case sending
    case failed
    case resolved
}

struct PendingAgentAction: Identifiable, Equatable, Sendable {
    enum Style: String, Equatable, Sendable {
        case primary
        case secondary
        case destructive
    }

    let id: String
    let title: String
    let payload: String
    let style: Style

    init(
        id: String,
        title: String,
        payload: String,
        style: Style = .secondary
    ) {
        self.id = id
        self.title = title
        self.payload = payload
        self.style = style
    }
}

struct PendingAgentAttention: Identifiable, Equatable, Sendable {
    var id: String { "\(terminalID)|\(fingerprint)" }

    let terminalID: String
    let agentIdentity: AgentIdentity
    let interactionState: AgentInteractionState
    let fingerprint: String
    var title: String
    var description: String
    var detail: String?
    var actions: [PendingAgentAction]
    var status: PendingAgentAttentionStatus
    var errorMessage: String?

    init(
        terminalID: String,
        agentIdentity: AgentIdentity,
        interactionState: AgentInteractionState,
        fingerprint: String,
        title: String,
        description: String,
        detail: String? = nil,
        actions: [PendingAgentAction],
        status: PendingAgentAttentionStatus = .awaitingUser,
        errorMessage: String? = nil
    ) {
        self.terminalID = terminalID
        self.agentIdentity = agentIdentity
        self.interactionState = interactionState
        self.fingerprint = fingerprint
        self.title = title
        self.description = description
        self.detail = detail
        self.actions = actions
        self.status = status
        self.errorMessage = errorMessage
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
    @Published private(set) var pendingAttentionByTerminalID: [String: PendingAgentAttention] = [:]

    // Agentic conversation state
    @Published var conversation: ForemanConversation
    @Published var chatInput: String = ""
    @Published var isAgentRunning: Bool = false
    @Published var agentReadiness: [(AgentIdentity, AgentReadinessState)] = []
    var onStartAgent: ((String, AgentMode) -> Void)?
    var onSendChatMessage: ((String) -> Void)?
    var onStopAgent: (() -> Void)?
    var onApproveAction: (() -> Void)?
    var onSkipAction: (() -> Void)?
    var onLaunchAgent: ((AgentIdentity) -> Void)?
    var onExecuteSuggestion: ((String, String) -> Void)?
    var onExecutePendingAttentionAction: ((PendingAgentAttention, PendingAgentAction) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(
        terminalRows: [TerminalSummaryRowModel] = [],
        dispatchQueue: [DispatchQueueItem] = [],
        userInstruction: String = "",
        selectedTerminalID: String? = nil,
        isSidebarVisible: Bool = false,
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
                    agentIdentity: nil,
                    agentInteractionState: nil,
                    supportLevel: nil,
                    evidenceSummary: nil,
                    isFocused: true,
                    suggestedActions: [],
                    pendingAttention: nil,
                    agentContextType: nil,
                    agentContextTitle: nil,
                    agentContextDescription: nil,
                    agentContextDetail: nil
                ),
                .init(
                    terminalID: "term-2",
                    title: "kimi",
                    cwd: "/tmp/project",
                    state: "waiting",
                    summary: "Kimi is waiting for your approval.",
                    agentIdentity: "kimi",
                    agentInteractionState: "waiting_approval",
                    supportLevel: "first_class",
                    evidenceSummary: "screen_heuristic",
                    isFocused: false,
                    suggestedActions: [
                        .init(title: "Review the approval request", command: nil, reason: "Run shell command: git push origin main", isRecommended: true)
                    ],
                    pendingAttention: .init(
                        terminalID: "term-2",
                        agentIdentity: .kimi,
                        interactionState: .waitingApproval,
                        fingerprint: "preview-approval",
                        title: "Kimi needs approval",
                        description: "Run shell command: git push origin main",
                        detail: "Shell",
                        actions: [
                            .init(
                                id: "approve",
                                title: "Approve",
                                payload: "y",
                                style: .primary
                            ),
                            .init(
                                id: "deny",
                                title: "Deny",
                                payload: "n",
                                style: .secondary
                            )
                        ]
                    ),
                    agentContextType: "waitingApproval",
                    agentContextTitle: "Needs your approval",
                    agentContextDescription: "Run shell command: git push origin main",
                    agentContextDetail: "Shell"
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
        refreshAgentReadiness()
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

    var visibleConversationMessages: [ConversationMessage] {
        conversation.visibleMessages(selectedTerminalID: selectedTerminalID)
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

    func executeSuggestion(terminalID: String, command: String) {
        onExecuteSuggestion?(terminalID, command)
    }

    func upsertPendingAttention(_ attention: PendingAgentAttention) {
        DebugLogger.log("[ForemanSidebarStore] upsertPendingAttention terminal=\(attention.terminalID.prefix(8)) fingerprint='\(attention.fingerprint)' title='\(attention.title)' actions=\(attention.actions.count)")
        pendingAttentionByTerminalID[attention.terminalID] = attention
        updateTerminalRowPendingAttention(terminalID: attention.terminalID)
        selectedTerminalID = attention.terminalID
        showSidebar()
        DebugLogger.log("[ForemanSidebarStore] upsertPendingAttention complete terminal=\(attention.terminalID.prefix(8)) selected=\(selectedTerminalID ?? "nil") visible=\(isSidebarVisible) rowHasAttention=\(terminalRows.first(where: { $0.terminalID == attention.terminalID })?.pendingAttention != nil)")
    }

    func markPendingAttentionSending(terminalID: String, fingerprint: String) {
        updatePendingAttention(terminalID: terminalID, fingerprint: fingerprint) { attention in
            attention.status = .sending
            attention.errorMessage = nil
        }
    }

    func markPendingAttentionFailed(terminalID: String, fingerprint: String, errorMessage: String) {
        updatePendingAttention(terminalID: terminalID, fingerprint: fingerprint) { attention in
            attention.status = .failed
            attention.errorMessage = errorMessage
        }
    }

    func resolvePendingAttention(terminalID: String, fingerprint: String) {
        guard pendingAttentionByTerminalID[terminalID]?.fingerprint == fingerprint else {
            return
        }

        pendingAttentionByTerminalID.removeValue(forKey: terminalID)
        updateTerminalRowPendingAttention(terminalID: terminalID)
    }

    func executePendingAttentionAction(terminalID: String, actionID: String) {
        guard let attention = pendingAttentionByTerminalID[terminalID],
              let action = attention.actions.first(where: { $0.id == actionID }) else {
            return
        }

        executePendingAttentionAction(attention, action: action)
    }

    func executePendingAttentionAction(_ attention: PendingAgentAttention, action: PendingAgentAction) {
        guard pendingAttentionByTerminalID[attention.terminalID] == attention else {
            return
        }

        onExecutePendingAttentionAction?(attention, action)
    }

    func applySnapshots(
        _ snapshots: [TerminalSnapshot],
        summariesByTerminalID: [String: TerminalSummary] = [:],
        understandingsByTerminalID: [String: TerminalUnderstanding] = [:]
    ) {
        reconcilePendingAttention(
            snapshots: snapshots,
            understandingsByTerminalID: understandingsByTerminalID
        )

        terminalRows = snapshots.map { snapshot in
            if let understanding = understandingsByTerminalID[snapshot.terminalID] {
                let context = understanding.agentInteractionContext
                return TerminalSummaryRowModel(
                    terminalID: snapshot.terminalID,
                    title: snapshot.title,
                    cwd: snapshot.cwd,
                    state: understanding.state.rawValue,
                    summary: understanding.shortExplanation,
                    agentIdentity: understanding.agentIdentity == .none ? nil : understanding.agentIdentity.rawValue,
                    agentInteractionState: understanding.agentInteractionState == .unknown ? nil : understanding.agentInteractionState.rawValue,
                    supportLevel: understanding.supportLevel.rawValue,
                    evidenceSummary: understanding.evidence.first?.source.rawValue,
                    isFocused: snapshot.isFocused,
                    suggestedActions: understanding.suggestedNextActions,
                    pendingAttention: pendingAttentionByTerminalID[snapshot.terminalID],
                    agentContextType: context.typeString,
                    agentContextTitle: context.titleString,
                    agentContextDescription: context.descriptionString,
                    agentContextDetail: context.detailString,
                    agentContextOptions: context.optionsArray
                )
            }

            if let summary = summariesByTerminalID[snapshot.terminalID] {
                return TerminalSummaryRowModel(
                    terminalID: snapshot.terminalID,
                    title: snapshot.title,
                    cwd: snapshot.cwd,
                    state: summary.state,
                    summary: summary.summary,
                    agentIdentity: nil,
                    agentInteractionState: nil,
                    supportLevel: nil,
                    evidenceSummary: nil,
                    isFocused: snapshot.isFocused,
                    suggestedActions: [],
                    pendingAttention: pendingAttentionByTerminalID[snapshot.terminalID],
                    agentContextType: nil,
                    agentContextTitle: nil,
                    agentContextDescription: nil,
                    agentContextDetail: nil
                )
            }

            return TerminalSummaryRowModel(
                terminalID: snapshot.terminalID,
                title: snapshot.title,
                cwd: snapshot.cwd,
                state: Self.snapshotState(for: snapshot),
                summary: Self.snapshotSummary(for: snapshot),
                agentIdentity: nil,
                agentInteractionState: nil,
                supportLevel: nil,
                evidenceSummary: nil,
                isFocused: snapshot.isFocused,
                suggestedActions: [],
                pendingAttention: pendingAttentionByTerminalID[snapshot.terminalID],
                agentContextType: nil,
                agentContextTitle: nil,
                agentContextDescription: nil,
                agentContextDetail: nil
            )
        }

        let nextPendingTerminalID = dispatchQueue.first(where: { $0.state == .pending })?.terminalID
        let waitingTerminalID = terminalRows.first(where: {
            !$0.isFocused && ($0.agentContextType == "waitingApproval" ||
                             $0.agentContextType == "waitingChoice" ||
                             $0.agentContextType == "waitingText")
        })?.terminalID
        let focusedTerminalID = snapshots.first(where: { $0.isFocused })?.terminalID
        let firstTerminalID = snapshots.first?.terminalID

        if let selectedTerminalID,
           terminalRows.contains(where: { $0.terminalID == selectedTerminalID }) {
            return
        }

        selectedTerminalID = nextPendingTerminalID ?? waitingTerminalID ?? focusedTerminalID ?? firstTerminalID
    }

    private func reconcilePendingAttention(
        snapshots: [TerminalSnapshot],
        understandingsByTerminalID: [String: TerminalUnderstanding]
    ) {
        let activeTerminalIDs = Set(snapshots.map(\.terminalID))

        pendingAttentionByTerminalID = pendingAttentionByTerminalID.filter { terminalID, attention in
            guard activeTerminalIDs.contains(terminalID) else {
                return false
            }

            guard let understanding = understandingsByTerminalID[terminalID] else {
                return true
            }

            return Self.pendingAttentionIsStillRelevant(attention, for: understanding)
        }
    }

    private static func pendingAttentionIsStillRelevant(
        _ attention: PendingAgentAttention,
        for understanding: TerminalUnderstanding
    ) -> Bool {
        guard understanding.agentIdentity == attention.agentIdentity else {
            return false
        }

        guard understanding.agentInteractionState == attention.interactionState else {
            return false
        }

        switch understanding.agentInteractionState {
        case .waitingApproval, .waitingChoice, .waitingText, .error:
            return true
        case .unknown, .running, .completed:
            return false
        }
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

    func refreshAgentReadiness() {
        agentReadiness = ManagedAgentRegistry.supportedAgents.map { agent in
            (agent.identity, ManagedAgentRegistry.readiness(for: agent.identity))
        }
    }

    private func updatePendingAttention(
        terminalID: String,
        fingerprint: String,
        mutate: (inout PendingAgentAttention) -> Void
    ) {
        guard var attention = pendingAttentionByTerminalID[terminalID],
              attention.fingerprint == fingerprint else {
            return
        }

        mutate(&attention)
        pendingAttentionByTerminalID[terminalID] = attention
        updateTerminalRowPendingAttention(terminalID: terminalID)
    }

    private func updateTerminalRowPendingAttention(terminalID: String) {
        guard let index = terminalRows.firstIndex(where: { $0.terminalID == terminalID }) else {
            return
        }

        terminalRows[index].pendingAttention = pendingAttentionByTerminalID[terminalID]
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
