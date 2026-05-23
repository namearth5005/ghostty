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
                    Text("Autonomous terminal foreman")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
                            onExecuteSuggestion: { terminalID, command in
                                store.executeSuggestion(terminalID: terminalID, command: command)
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

                if let errorMessage = store.conversation.errorMessage, !errorMessage.isEmpty {
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
            lastAction: store.visibleConversationMessages.last?.action
        )
    }

    private var statusDisplay: ConversationStatusDisplay {
        ConversationStatusDisplay.resolve(
            status: store.conversation.status,
            phase: inputPhase
        )
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
