import SwiftUI

struct ForemanChatView: View {
    @ObservedObject var store: ForemanSidebarStore
    @State private var mode: AgentMode = .interactive

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Foreman Agent")
                        .font(.system(size: 18, weight: .bold))
                    Text(contextTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let contextSubtitle {
                        Text(contextSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.85))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Button(action: { store.hideSidebar() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide AI Foreman")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            let isConfigured = (NSApp.delegate as? AppDelegate)?.aiForemanIsConfigured ?? false
            if !isConfigured {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text("Add API keys to enable AI drafting:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    APIKeyInputRow(label: "Anthropic", defaultsKey: "foreman.api.anthropic")
                    APIKeyInputRow(label: "OpenAI", defaultsKey: "foreman.api.openai")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            // Agent readiness panel
            if !store.agentReadiness.isEmpty {
                AgentReadinessPanel(
                    agents: store.agentReadiness,
                    onLaunch: { identity in
                        store.onLaunchAgent?(identity)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Divider()
            }

            // Status bar
            HStack {
                StatusBadge(display: statusDisplay)
                Spacer()
                if statusDisplay.showsIterationCount {
                    Text("Iter: \(store.conversation.iterationCount)/20")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let planningNotice = store.selectedTerminalPlanningNotice {
                sidebarNotice(
                    title: "Planning Mode",
                    message: planningNotice,
                    tint: .orange
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            if let suggestion = store.selectedTerminalSuggestedWorkerAction {
                VStack(alignment: .leading, spacing: 6) {
                    if let provenance = store.selectedTerminalSuggestionProvenance {
                        Text(provenance)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(suggestion.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    if !suggestion.rationale.isEmpty {
                        Text(suggestion.rationale)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            if !store.resolvedTargetOptions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose where the next message goes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    FlowingTargetOptions(options: store.resolvedTargetOptions) { option in
                        store.selectSidebarTargetOption(option)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            Divider()

            // Terminal inspect surface
            if !store.terminalRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Terminals")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ForEach(store.terminalRows) { row in
                        TerminalSummaryRow(
                            row: row,
                            isSelected: store.selectedTerminalID == row.terminalID,
                            onSelect: { terminalID in
                                store.selectTerminal(terminalID)
                            },
                            onExecuteSuggestion: { terminalID, action in
                                store.executeSuggestion(terminalID: terminalID, action: action)
                            },
                            onExecutePendingAttentionAction: { attention, action in
                                store.executePendingAttentionAction(attention, action: action)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
            }

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.visibleConversationMessages) { message in
                            ChatBubble(message: message)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: store.visibleConversationMessages.count) { _ in
                    if let last = store.visibleConversationMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            VStack(alignment: .leading, spacing: 8) {
                switch inputPhase {
                case .awaitingApproval(let pendingCommand):
                    HStack(spacing: 8) {
                        Text("Run `\(pendingCommand)`?")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.skipAction()
                        } label: {
                            Label("Skip", systemImage: "forward")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            store.approveAction()
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                case .processing:
                    HStack {
                        Spacer()
                        Button {
                            store.stopAgent()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        Spacer()
                    }

                case .choosingTarget(let options):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select a waiting terminal or switch to project guidance before sending a reply.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        FlowingTargetOptions(options: options) { option in
                            store.selectSidebarTargetOption(option)
                        }
                    }

                case .goalCompleted:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This project goal is marked complete. Reopen it, clear it, or save a follow-up goal before dispatching more work.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            TextField("Set a new or extended goal", text: $store.chatInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    saveGoalFromCompletedState()
                                }

                            Button("Save Goal") {
                                saveGoalFromCompletedState()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        HStack(spacing: 8) {
                            Button("Reopen Goal") {
                                store.sendChatMessage("/goal reopen")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Clear Goal") {
                                store.sendChatMessage("/goal clear")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                case .awaitingReply, .chatting:
                    HStack(spacing: 8) {
                        TextField("Message...", text: $store.chatInput, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .onSubmit {
                                if !store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    store.sendChatMessage(store.chatInput)
                                }
                            }

                        Button {
                            if !store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                store.sendChatMessage(store.chatInput)
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    HStack {
                        Button {
                            store.stopAgent()
                        } label: {
                            Label("End Session", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                        Spacer()
                    }

                case .readyToStart:
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Mode", selection: $mode) {
                            Text("Interactive").tag(AgentMode.interactive)
                            Text("Autonomous").tag(AgentMode.autonomous)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)

                        HStack(spacing: 8) {
                            TextField("What should I do?", text: $store.chatInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    startAgent()
                                }

                            Button {
                                startAgent()
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if let errorMessage = displayedErrorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 300, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("foreman.sidebar")
    }

    private func startAgent() {
        let goal = store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        store.startAgent(goal: goal, mode: mode)
    }

    private var inputPhase: ConversationUIPhase {
        ConversationUIPhase.resolve(
            goal: store.conversation.goal,
            isRunning: store.conversation.isRunning,
            status: store.conversation.status,
            lastAction: store.visibleConversationMessages.last?.action,
            resolvedTarget: store.resolvedSidebarTarget
        )
    }

    private var statusDisplay: ConversationStatusDisplay {
        ConversationStatusDisplay.resolve(
            status: store.conversation.status,
            phase: inputPhase
        )
    }

    private var contextTitle: String {
        switch store.resolvedSidebarTarget {
        case .terminalReply(let terminalID, _):
            return "Replying to \(terminalDisplayName(for: terminalID))"
        case .project(let projectID):
            return "Guiding Foreman for \(projectDisplayName(from: projectID))"
        case .ambiguous:
            return "Choose a terminal target"
        case .completedGoal(let projectID):
            return "Goal complete for \(projectDisplayName(from: projectID))"
        }
    }

    private var contextSubtitle: String? {
        switch store.resolvedSidebarTarget {
        case .terminalReply(let terminalID, _):
            return store.workerSnapshotsByTerminalID[terminalID]?.state.summary
                ?? store.terminalRows.first(where: { $0.terminalID == terminalID })?.summary
        case .project:
            return store.conversation.activeProjectGoal?.objective
        case .ambiguous:
            return "Several terminals are waiting. Pick one or switch to project guidance."
        case .completedGoal:
            return store.conversation.activeProjectGoal?.objective
        }
    }

    private var displayedErrorMessage: String? {
        let routingError = store.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let routingError, !routingError.isEmpty {
            return routingError
        }

        let conversationError = store.conversation.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let conversationError, !conversationError.isEmpty {
            return conversationError
        }

        return nil
    }

    private func terminalDisplayName(for terminalID: String) -> String {
        guard let row = store.terminalRows.first(where: { $0.terminalID == terminalID }) else {
            return terminalID
        }

        let title = row.title.isEmpty ? terminalID : row.title
        if let agentIdentity = row.agentIdentity, !agentIdentity.isEmpty {
            return "\(displayAgentIdentity(agentIdentity)) · \(title)"
        }
        return title
    }

    private func projectDisplayName(from projectID: String?) -> String {
        guard let projectID, !projectID.isEmpty else {
            return "this project"
        }

        let name = URL(fileURLWithPath: projectID).lastPathComponent
        return name.isEmpty ? projectID : name
    }

    private func displayAgentIdentity(_ rawValue: String) -> String {
        switch rawValue {
        case AgentIdentity.claudeCode.rawValue:
            return "Claude Code"
        case AgentIdentity.codex.rawValue:
            return "Codex"
        case AgentIdentity.kimi.rawValue:
            return "Kimi"
        default:
            return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func saveGoalFromCompletedState() {
        let goal = store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        store.sendChatMessage("/goal set \(goal)")
    }
}

@ViewBuilder
private func sidebarNotice(title: String, message: String, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(tint)

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)
    }
    .padding(12)
    .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.08))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(tint.opacity(0.18), lineWidth: 1)
    )
}

private struct FlowingTargetOptions: View {
    let options: [ForemanTargetOption]
    let onSelect: (ForemanTargetOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(targetLabel(for: option)) {
                    onSelect(option)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func targetLabel(for option: ForemanTargetOption) -> String {
        switch option {
        case .project(let title):
            return title
        case .terminalReply(_, _, let title):
            return title
        }
    }
}

struct ChatBubble: View {
    let message: ConversationMessage

    private var badgeAction: AgentAction? {
        guard let action = message.action else { return nil }
        switch action {
        case .sendCommand:
            return action
        default:
            return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .agent {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 20, height: 20)
            } else {
                Spacer(minLength: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(message.role == .user ? .primary : .secondary)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(message.role == .user
                                ? Color(nsColor: .selectedControlColor).opacity(0.3)
                                : Color(nsColor: .controlBackgroundColor).opacity(0.6)
                            )
                    )

                if let action = badgeAction {
                    ActionBadge(action: action)
                }
            }

            if message.role == .user {
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            } else {
                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .id(message.id)
    }
}

struct ActionBadge: View {
    let action: AgentAction

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.15))
        )
    }

    private var iconName: String {
        switch action {
        case .respond: return "bubble.left.fill"
        case .sendCommand: return "terminal.fill"
        case .askUser: return "questionmark.bubble.fill"
        case .declareComplete: return "checkmark.circle.fill"
        case .declareStuck: return "exclamationmark.triangle.fill"
        }
    }

    private var label: String {
        switch action {
        case .respond(let message):
            return message
        case .sendCommand(_, let command, _):
            return command
        case .askUser(let question):
            return question
        case .declareComplete:
            return "Complete"
        case .declareStuck:
            return "Stuck"
        }
    }

    private var color: Color {
        switch action {
        case .respond: return .secondary
        case .sendCommand: return .blue
        case .askUser: return .orange
        case .declareComplete: return .green
        case .declareStuck: return .red
        }
    }
}

struct StatusBadge: View {
    let display: ConversationStatusDisplay

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .opacity(display == .idle || display == .complete || display == .stuck || display == .chatting ? 1.0 : 0.6)
                .overlay(
                    display == .observing || display == .planning || display == .executing
                        ? Circle().stroke(color, lineWidth: 1).scaleEffect(1.5).opacity(0.5)
                        : nil
                )

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var label: String {
        switch display {
        case .idle: return "Idle"
        case .chatting: return "Chatting"
        case .observing: return "Observing..."
        case .planning: return "Planning..."
        case .executing: return "Executing..."
        case .awaitingApproval: return "Approval needed"
        case .awaitingReply: return "Waiting for reply"
        case .complete: return "Complete"
        case .stuck: return "Stuck"
        }
    }

    private var color: Color {
        switch display {
        case .idle: return .secondary
        case .chatting: return .secondary
        case .observing: return .blue
        case .planning: return .purple
        case .executing: return .green
        case .awaitingApproval: return .orange
        case .awaitingReply: return .orange
        case .complete: return .green
        case .stuck: return .red
        }
    }
}
