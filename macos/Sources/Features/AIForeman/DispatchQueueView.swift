import SwiftUI

struct DispatchQueueView: View {
    @ObservedObject var store: ForemanSidebarStore
    let onSend: (DispatchQueueItem) -> Void
    let onSendAndNext: (DispatchQueueItem) -> Void
    let onSkip: (DispatchQueueItem) -> Void

    private var pendingItems: [DispatchQueueItem] {
        store.dispatchQueue.filter { $0.state == .pending }
    }

    private var completedItems: [DispatchQueueItem] {
        store.dispatchQueue.filter { $0.state != .pending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dispatch Queue")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                if !completedItems.isEmpty {
                    Text("(\(pendingItems.count) pending, \(completedItems.count) done)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if !completedItems.isEmpty {
                    Button("Clear Done") {
                        store.dispatchQueue.removeAll { $0.state != .pending }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if store.dispatchQueue.isEmpty {
                Text("No drafted terminal messages yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                if !pendingItems.isEmpty {
                    ForEach(pendingItems) { item in
                        pendingItemView(item)
                    }
                }

                if !completedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(completedItems) { item in
                            completedItemRow(item)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func pendingItemView(_ item: DispatchQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.terminalID)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Spacer(minLength: 8)
                Text(item.state.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
            }

            TextField(
                "Review draft before sending",
                text: Binding(
                    get: { item.message },
                    set: { store.updateDraftMessage(itemID: item.id, message: $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...6)
            .font(.system(size: 12))

            HStack(spacing: 8) {
                Button("Send") { onSend(item) }
                Button("Send + Next") { onSendAndNext(item) }
                Button("Skip") { onSkip(item) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }

    private func completedItemRow(_ item: DispatchQueueItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.state == .sent ? "paperplane.fill" : "arrow.uturn.forward")
                .font(.system(size: 9))
                .foregroundStyle(item.state == .sent ? .green : .secondary)

            Text(item.terminalID)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))

            Text(item.message)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text(item.state.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(item.state == .sent ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }
}
