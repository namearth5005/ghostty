import SwiftUI

struct ForemanSidebarView: View {
    @ObservedObject var store: ForemanSidebarStore
    let onDraftQueue: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Foreman")
                        .font(.system(size: 18, weight: .bold))
                    Text("Summaries, queue state, and the next reviewed terminal drafts.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: onClose) {
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Terminals")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)

                        if store.terminalRows.isEmpty {
                            Text("No terminal summaries yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.terminalRows) { row in
                                TerminalSummaryRow(row: row)
                            }
                        }
                    }

                    DispatchQueueView(
                        store: store,
                        onSend: { item in
                            (NSApp.delegate as? AppDelegate)?.sendForemanQueueItem(item, store: store, advance: false)
                        },
                        onSendAndNext: { item in
                            (NSApp.delegate as? AppDelegate)?.sendForemanQueueItem(item, store: store, advance: true)
                        },
                        onSkip: { item in
                            (NSApp.delegate as? AppDelegate)?.skipForemanQueueItem(item, store: store)
                        }
                    )

                    ActivityLogView(store: store)
                }
                .padding(16)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Instruction")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                TextField("Tell the foreman what to do next", text: $store.userInstruction, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                HStack(spacing: 8) {
                    Button(store.isGeneratingDrafts ? "Drafting…" : "Draft Queue") {
                        onDraftQueue()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isGeneratingDrafts || store.userInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let planSummary = store.planSummary, !planSummary.isEmpty {
                        Text(planSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                if let lastActionMessage = store.lastActionMessage, !lastActionMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(lastActionMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { store.clearLastActionMessage() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage = store.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let selectedTerminalID = store.selectedTerminalID {
                    Text("Next terminal: \(selectedTerminalID)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
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
    }
}


struct ActivityLogView: View {
    @ObservedObject var store: ForemanSidebarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity Log")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if !store.activityLog.isEmpty {
                    Button("Clear") {
                        store.clearActivityLog()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if store.activityLog.isEmpty {
                Text("No dispatches yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.activityLog.suffix(10).reversed()) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: entry.state))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(stateColor(for: entry.state))

                            Text(entry.terminalID)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))

                            Text(entry.message)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 4)

                            Text(relativeTime(from: entry.timestamp))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func iconName(for state: DispatchQueueItemState) -> String {
        switch state {
        case .sent:
            return "paperplane.fill"
        case .skipped:
            return "arrow.uturn.forward"
        case .pending:
            return "circle"
        }
    }

    private func stateColor(for state: DispatchQueueItemState) -> Color {
        switch state {
        case .pending:
            return .orange
        case .sent:
            return .green
        case .skipped:
            return .secondary
        }
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 10 {
            return "just now"
        } else if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
}
