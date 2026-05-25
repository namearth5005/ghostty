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
    @Published var preferredSidebarTarget: ForemanSidebarTargetPreference?
    @Published var isSidebarVisible: Bool
    @Published var planSummary: String?
    @Published var errorMessage: String?
    @Published var isGeneratingDrafts: Bool
    @Published var activityLog: [DispatchActivityLogEntry]
    @Published var lastActionMessage: String?
    @Published private(set) var pendingAttentionByTerminalID: [String: PendingAgentAttention] = [:]
    @Published private(set) var workerSnapshotsByTerminalID: [String: TerminalWorkerSnapshot] = [:]

    // Agentic conversation state
    @Published var conversation: ForemanConversation
    @Published var runtimeState: ForemanRuntimeState
    @Published var chatInput: String = ""
    @Published var isAgentRunning: Bool = false
    @Published var agentReadiness: [(AgentIdentity, AgentReadinessState)] = []
    private(set) var sidebarSession: ForemanSidebarSessionControlling?
    private let sidebarRouter = ForemanSidebarRouter()
    var onStartAgent: ((String, AgentMode) -> Void)?
    var onSendChatMessage: ((String) -> Void)?
    var onStopAgent: (() -> Void)?
    var onApproveAction: (() -> Void)?
    var onSkipAction: (() -> Void)?
    var onLaunchAgent: ((AgentIdentity) -> Void)?
    var onDispatchSidebarIntent: ((ForemanSidebarIntent) -> Void)?
    var onExecuteSuggestion: ((String, String) -> Void)?
    var onExecutePendingAttentionAction: ((PendingAgentAttention, PendingAgentAction) -> Void)?

    private var latestSnapshots: [TerminalSnapshot] = []
    private var latestSummariesByTerminalID: [String: TerminalSummary] = [:]
    private var latestUnderstandingsByTerminalID: [String: TerminalUnderstanding] = [:]
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(
        terminalRows: [TerminalSummaryRowModel] = [],
        dispatchQueue: [DispatchQueueItem] = [],
        userInstruction: String = "",
        selectedTerminalID: String? = nil,
        preferredSidebarTarget: ForemanSidebarTargetPreference? = nil,
        isSidebarVisible: Bool = false,
        planSummary: String? = nil,
        errorMessage: String? = nil,
        isGeneratingDrafts: Bool = false,
        activityLog: [DispatchActivityLogEntry] = [],
        lastActionMessage: String? = nil,
        conversation: ForemanConversation? = nil,
        runtimeState: ForemanRuntimeState? = nil
    ) {
        let resolvedRuntimeState = runtimeState ?? conversation?.runtimeState ?? ForemanRuntimeState()
        let resolvedConversation = conversation ?? ForemanConversation(runtimeState: resolvedRuntimeState)
        assert(conversation == nil || runtimeState == nil || conversation!.runtimeState === resolvedRuntimeState)

        self.terminalRows = terminalRows
        self.dispatchQueue = dispatchQueue
        self.userInstruction = userInstruction
        self.selectedTerminalID = selectedTerminalID
        self.preferredSidebarTarget = preferredSidebarTarget
        self.isSidebarVisible = isSidebarVisible
        self.planSummary = planSummary
        self.errorMessage = errorMessage
        self.isGeneratingDrafts = isGeneratingDrafts
        self.activityLog = activityLog
        self.lastActionMessage = lastActionMessage
        self.conversation = resolvedConversation
        self.runtimeState = resolvedRuntimeState

        // Forward conversation changes so SwiftUI re-renders the sidebar
        self.conversation.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        self.runtimeState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        self.runtimeState.$activeProjectGoal.sink { [weak self] goal in
            self?.refreshTerminalRowsForGoalState(goal)
        }.store(in: &cancellables)

        refreshTerminalRowsForGoalState(self.runtimeState.activeProjectGoal)
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
        if ForemanProjectGoalCommand.parse(text) != nil {
            chatInput = ""
            onSendChatMessage?(text)
            return
        }

        if let onDispatchSidebarIntent {
            let routeResult = sidebarRouter.resolveChatInput(text, state: routingState())
            applyRouteResult(routeResult, defaultDraft: text)
            if case .dispatch(let intent) = routeResult.outcome {
                onDispatchSidebarIntent(intent)
            }
            return
        }

        chatInput = ""
        onSendChatMessage?(text)
    }

    var visibleConversationMessages: [ConversationMessage] {
        conversation.visibleMessages(selectedTerminalID: resolvedConversationTerminalID)
    }

    var selectedTerminalWorkerSnapshot: TerminalWorkerSnapshot? {
        guard let selectedTerminalID else {
            return nil
        }

        return workerSnapshotsByTerminalID[selectedTerminalID]
    }

    var selectedTerminalSuggestedWorkerAction: TerminalWorkerSnapshot.Suggestion? {
        selectedTerminalWorkerSnapshot?.preferredSuggestion
    }

    var selectedTerminalSuggestionProvenance: String? {
        guard let snapshot = selectedTerminalWorkerSnapshot,
              selectedTerminalSuggestedWorkerAction != nil else {
            return nil
        }

        return "Suggested by \(snapshot.agent.identity.displayName ?? "worker")"
    }

    var selectedTerminalPlanningNotice: String? {
        guard selectedTerminalWorkerSnapshot?.state.runtimeFlags.contains(.planning) == true else {
            return nil
        }

        return "This worker is in plan mode. Review the plan before continuing."
    }

    var attentionSummaryText: String? {
        let fragments = terminalRows.compactMap { row -> String? in
            attentionSummaryFragment(for: row)
        }

        guard fragments.count > 1 else {
            return nil
        }

        return "\(fragments.count) terminals need attention: \(fragments.joined(separator: "; "))."
    }

    var rollupStatusText: String? {
        let summary = attentionSummaryText
            ?? runtimeState.lastOverview?.summary
            ?? selectedTerminalWorkerSnapshot?.state.summary

        guard let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return summary
    }

    var resolvedSidebarTarget: ForemanSidebarTarget {
        sidebarRouter.resolveTarget(from: routingState())
    }

    var resolvedConversationTerminalID: String? {
        switch resolvedSidebarTarget {
        case .terminalReply(let terminalID, _):
            return terminalID

        case .project:
            if preferredSidebarTarget == .project {
                return nil
            }
            return selectedTerminalID

        case .ambiguous, .completedGoal:
            return nil
        }
    }

    var resolvedTargetOptions: [ForemanTargetOption] {
        guard case .ambiguous(let options) = resolvedSidebarTarget else {
            return []
        }

        return options
    }

    func stopAgent() {
        isAgentRunning = false
        onStopAgent?()
    }

    func attachSidebarSession(_ session: ForemanSidebarSessionControlling) {
        sidebarSession = session
    }

    func approveAction() {
        onApproveAction?()
    }

    func skipAction() {
        onSkipAction?()
    }

    func executeSuggestion(terminalID: String, command: String) {
        executeSuggestion(
            terminalID: terminalID,
            action: .init(
                title: command,
                command: command,
                reason: "",
                isRecommended: false
            )
        )
    }

    func executeSuggestion(terminalID: String, action: TerminalSuggestedAction) {
        if terminalRows.contains(where: { $0.terminalID == terminalID }) {
            selectTerminal(terminalID)
        }

        if action.authoritativePayload == nil,
           action.command == nil,
           action.guidancePrompt == nil,
           let attention = pendingAttentionByTerminalID[terminalID],
           let pendingAction = attention.actions.first(where: { $0.title == action.title }) {
            executePendingAttentionAction(attention, action: pendingAction)
            return
        }

        if let onDispatchSidebarIntent {
            let routeResult = sidebarRouter.resolveSuggestion(
                action,
                terminalID: terminalID,
                state: routingState()
            )
            applyRouteResult(routeResult)
            if case .dispatch(let intent) = routeResult.outcome {
                onDispatchSidebarIntent(intent)
            }
            return
        }

        guard let command = action.command else {
            return
        }

        onExecuteSuggestion?(terminalID, command)
    }

    func selectTerminal(_ terminalID: String) {
        selectedTerminalID = terminalID
        if pendingAttentionByTerminalID[terminalID] != nil {
            preferredSidebarTarget = .terminal(terminalID)
        } else if case .terminal = preferredSidebarTarget {
            preferredSidebarTarget = nil
        }
    }

    func selectSidebarTargetOption(_ option: ForemanTargetOption) {
        switch option {
        case .project:
            preferredSidebarTarget = .project
        case .terminalReply(let terminalID, _, _):
            selectedTerminalID = terminalID
            preferredSidebarTarget = .terminal(terminalID)
        }
    }

    func upsertPendingAttention(_ attention: PendingAgentAttention) {
        DebugLogger.log("[ForemanSidebarStore] upsertPendingAttention terminal=\(attention.terminalID.prefix(8)) fingerprint='\(attention.fingerprint)' title='\(attention.title)' actions=\(attention.actions.count)")
        pendingAttentionByTerminalID[attention.terminalID] = attention
        updateTerminalRowPendingAttention(terminalID: attention.terminalID)
        if shouldAdoptPendingAttentionSelection(for: attention.terminalID) {
            selectedTerminalID = attention.terminalID
        }
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
        if preferredSidebarTarget == .terminal(terminalID) {
            preferredSidebarTarget = nil
        }
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

        if let onDispatchSidebarIntent {
            let routeResult = sidebarRouter.resolveExplicitIntent(
                .sendPendingAttentionAction(
                    terminalID: attention.terminalID,
                    fingerprint: attention.fingerprint,
                    payload: action.payload
                ),
                state: routingState()
            )
            applyRouteResult(routeResult)
            if case .dispatch(let intent) = routeResult.outcome {
                onDispatchSidebarIntent(intent)
            }
            return
        }

        onExecutePendingAttentionAction?(attention, action)
    }

    func applySnapshots(
        _ snapshots: [TerminalSnapshot],
        summariesByTerminalID: [String: TerminalSummary] = [:],
        understandingsByTerminalID: [String: TerminalUnderstanding] = [:]
    ) {
        latestSnapshots = snapshots
        latestSummariesByTerminalID = summariesByTerminalID
        latestUnderstandingsByTerminalID = understandingsByTerminalID

        reconcilePendingAttention(
            snapshots: snapshots,
            understandingsByTerminalID: understandingsByTerminalID
        )
        workerSnapshotsByTerminalID = Dictionary(
            uniqueKeysWithValues: understandingsByTerminalID.compactMap { terminalID, understanding in
                guard let workerSnapshot = understanding.workerSnapshot else {
                    return nil
                }

                return (terminalID, workerSnapshot)
            }
        )

        rebuildTerminalRowsFromCachedState(
            suppressSuggestedActions: shouldSuppressSuggestedActionsForCompletedGoal
        )
    }

    private func rebuildTerminalRowsFromCachedState(
        suppressSuggestedActions: Bool = false
    ) {
        terminalRows = makeTerminalRows(
            snapshots: latestSnapshots,
            summariesByTerminalID: latestSummariesByTerminalID,
            understandingsByTerminalID: latestUnderstandingsByTerminalID,
            suppressSuggestedActions: suppressSuggestedActions
        )

        let nextPendingTerminalID = dispatchQueue.first(where: { $0.state == .pending })?.terminalID
        let waitingTerminalID = terminalRows.first(where: {
            !$0.isFocused && ($0.agentContextType == "waitingApproval" ||
                             $0.agentContextType == "waitingChoice" ||
                             $0.agentContextType == "waitingText")
        })?.terminalID
        let focusedTerminalID = latestSnapshots.first(where: { $0.isFocused })?.terminalID
        let firstTerminalID = latestSnapshots.first?.terminalID

        if let selectedTerminalID,
           terminalRows.contains(where: { $0.terminalID == selectedTerminalID }) {
            return
        }

        selectedTerminalID = nextPendingTerminalID ?? waitingTerminalID ?? focusedTerminalID ?? firstTerminalID
    }

    private func makeTerminalRows(
        snapshots: [TerminalSnapshot],
        summariesByTerminalID: [String: TerminalSummary],
        understandingsByTerminalID: [String: TerminalUnderstanding],
        suppressSuggestedActions: Bool
    ) -> [TerminalSummaryRowModel] {
        snapshots.map { snapshot in
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
                    suggestedActions: scopedSuggestedActions(
                        suggestedActions(for: understanding),
                        suppressSuggestedActions: suppressSuggestedActions
                    ),
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

        if case .terminal(let terminalID) = preferredSidebarTarget,
           pendingAttentionByTerminalID[terminalID] == nil {
            preferredSidebarTarget = nil
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

        if let workerSnapshot = understanding.workerSnapshot,
           workerSnapshot.request != nil,
           attention.fingerprint != workerSnapshot.attentionFingerprint {
            return false
        }

        switch understanding.agentInteractionState {
        case .waitingApproval, .waitingChoice, .waitingText, .error:
            return true
        case .unknown, .running, .completed:
            return false
        }
    }

    private func routingState() -> ForemanSidebarRoutingState {
        ForemanSidebarRoutingState(
            projectID: resolvedProjectID(),
            selectedTerminalID: selectedTerminalID,
            focusedTerminalID: terminalRows.first(where: \.isFocused)?.terminalID,
            preferredTarget: preferredSidebarTarget,
            pendingAttentionByTerminalID: pendingAttentionByTerminalID,
            terminalRows: terminalRows,
            workerSnapshotsByTerminalID: workerSnapshotsByTerminalID,
            activeProjectGoal: runtimeState.activeProjectGoal
        )
    }

    private func resolvedProjectID() -> String? {
        if let projectID = runtimeState.activeProjectGoal?.projectID {
            return projectID
        }

        if let selectedTerminalID,
           let row = terminalRows.first(where: { $0.terminalID == selectedTerminalID }),
           let projectID = ForemanProjectPathResolver.projectPath(from: row.cwd) {
            return projectID
        }

        if let focusedRow = terminalRows.first(where: \.isFocused),
           let projectID = ForemanProjectPathResolver.projectPath(from: focusedRow.cwd) {
            return projectID
        }

        return terminalRows.lazy.compactMap { row in
            ForemanProjectPathResolver.projectPath(from: row.cwd)
        }.first
    }

    private func applyRouteResult(
        _ routeResult: ForemanSidebarRouteResult,
        defaultDraft: String? = nil
    ) {
        switch routeResult.outcome {
        case .dispatch:
            errorMessage = nil
            if defaultDraft != nil {
                chatInput = ""
            }

        case .blocked(let message, let draftToPreserve):
            errorMessage = message
            if let draft = draftToPreserve ?? defaultDraft {
                chatInput = draft
            }

        case .suppressed(let message):
            errorMessage = message
            if let defaultDraft {
                chatInput = defaultDraft
            }
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

    private func refreshTerminalRowsForGoalState(_ goal: ForemanProjectGoal?) {
        guard goal != nil || !latestSnapshots.isEmpty else {
            return
        }

        rebuildTerminalRowsFromCachedState(
            suppressSuggestedActions: goal?.status == .completed
        )
    }

    private var shouldSuppressSuggestedActionsForCompletedGoal: Bool {
        runtimeState.activeProjectGoal?.status == .completed
    }

    private func scopedSuggestedActions(
        _ actions: [TerminalSuggestedAction],
        suppressSuggestedActions: Bool
    ) -> [TerminalSuggestedAction] {
        guard suppressSuggestedActions else {
            return actions
        }

        return []
    }

    private func suggestedActions(
        for understanding: TerminalUnderstanding
    ) -> [TerminalSuggestedAction] {
        if let workerSnapshot = understanding.workerSnapshot,
           !workerSnapshot.requestSuggestions.isEmpty {
            return workerSnapshot.requestSuggestions.map { suggestion in
                let command = snapshotCommand(for: suggestion.payload)
                let authoritativePayload = snapshotReplyPayload(for: suggestion.payload)
                let guidancePrompt = snapshotGuidancePrompt(for: suggestion.payload)
                return TerminalSuggestedAction(
                    title: suggestion.title,
                    command: command,
                    reason: suggestion.rationale,
                    isRecommended: suggestion.recommended,
                    authoritativeFingerprint: command == nil && authoritativePayload == nil && guidancePrompt == nil ? nil : workerSnapshot.attentionFingerprint,
                    authoritativePayload: authoritativePayload,
                    guidancePrompt: guidancePrompt
                )
            }
        }

        if let workerSnapshot = understanding.workerSnapshot,
           let guidancePrompt = authoritativeGuidancePrompt(for: workerSnapshot) {
            return understanding.suggestedNextActions.map { action in
                guard action.command == nil,
                      action.authoritativePayload == nil,
                      action.guidancePrompt == nil else {
                    return action
                }

                return TerminalSuggestedAction(
                    title: action.title,
                    command: nil,
                    reason: action.reason,
                    isRecommended: action.isRecommended,
                    authoritativeFingerprint: workerSnapshot.attentionFingerprint,
                    guidancePrompt: guidancePrompt
                )
            }
        }

        return understanding.suggestedNextActions
    }

    private func snapshotCommand(
        for payload: TerminalWorkerSnapshot.Payload
    ) -> String? {
        switch payload {
        case .command(let command):
            return command
        case .text, .option, .approval, .foremanPrompt:
            return nil
        }
    }

    private func snapshotReplyPayload(
        for payload: TerminalWorkerSnapshot.Payload
    ) -> String? {
        switch payload {
        case .text(let value), .option(let value), .approval(let value):
            return value
        case .command, .foremanPrompt:
            return nil
        }
    }

    private func snapshotGuidancePrompt(
        for payload: TerminalWorkerSnapshot.Payload
    ) -> String? {
        switch payload {
        case .foremanPrompt(let value):
            return value
        case .text, .command, .option, .approval:
            return nil
        }
    }

    private func authoritativeGuidancePrompt(
        for workerSnapshot: TerminalWorkerSnapshot
    ) -> String? {
        switch workerSnapshot.state.attention {
        case .replyRequired, .choiceRequired, .approvalRequired, .error:
            return workerSnapshot.request?.prompt ?? workerSnapshot.state.summary
        case .none:
            return nil
        }
    }

    private func shouldAdoptPendingAttentionSelection(for terminalID: String) -> Bool {
        guard let selectedTerminalID else {
            return true
        }

        if selectedTerminalID == terminalID {
            return true
        }

        if terminalRows.contains(where: { $0.terminalID == selectedTerminalID }) {
            return false
        }

        return pendingAttentionByTerminalID[selectedTerminalID] == nil
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

    private func attentionSummaryFragment(for row: TerminalSummaryRowModel) -> String? {
        if let workerSnapshot = workerSnapshotsByTerminalID[row.terminalID],
           let attentionText = attentionText(for: workerSnapshot.state.attention) {
            return "\(row.terminalID) \(attentionText)"
        }

        if let pendingAttention = row.pendingAttention,
           let attentionText = attentionText(for: pendingAttention.interactionState) {
            return "\(row.terminalID) \(attentionText)"
        }

        if let interactionState = row.agentInteractionState,
           let parsedState = AgentInteractionState(rawValue: interactionState),
           let attentionText = attentionText(for: parsedState) {
            return "\(row.terminalID) \(attentionText)"
        }

        return nil
    }

    private func attentionText(for attention: TerminalWorkerAttention) -> String? {
        switch attention {
        case .replyRequired:
            return "reply required"
        case .choiceRequired:
            return "choice required"
        case .approvalRequired:
            return "approval required"
        case .error:
            return "error requires review"
        case .none:
            return nil
        }
    }

    private func attentionText(for interactionState: AgentInteractionState) -> String? {
        switch interactionState {
        case .waitingText:
            return "reply required"
        case .waitingChoice:
            return "choice required"
        case .waitingApproval:
            return "approval required"
        case .error:
            return "error requires review"
        case .unknown, .running, .completed:
            return nil
        }
    }
}
