import SwiftUI

struct DispatchQueueView: View {
    @ObservedObject var store: ForemanSidebarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dispatch Queue")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            if store.dispatchQueue.isEmpty {
                Text("No drafted terminal messages yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.dispatchQueue) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.terminalID)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Spacer(minLength: 8)
                            Text(item.state.rawValue.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(stateColor(for: item.state))
                        }

                        Text(item.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.04))
                    )
                }
            }
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
}
