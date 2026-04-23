import SwiftUI

struct ForemanSidebarView: View {
    @ObservedObject var store: ForemanSidebarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Foreman")
                    .font(.system(size: 18, weight: .bold))
                Text("Summaries, queue state, and the next reviewed terminal drafts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
