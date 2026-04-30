import SwiftUI

struct TerminalSummaryRow: View {
    let row: TerminalSummaryRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title.isEmpty ? row.terminalID : row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(row.state.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusColor)
            }

            if let cwd = row.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(row.summary)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(row.isFocused ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(row.isFocused ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch row.state.lowercased() {
        case "failed", "blocked":
            return .red
        case "running", "active", "noisy_healthy":
            return .orange
        case "succeeded":
            return .green
        case "waiting":
            return .yellow
        case "idle":
            return .orange
        default:
            return .secondary
        }
    }
}
