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

            // NEW: Rich agent context card
            if let contextType = row.agentContextType {
                HStack(spacing: 8) {
                    Image(systemName: iconForContextType(contextType))
                        .font(.system(size: 12))
                        .foregroundStyle(colorForContextType(contextType))

                    VStack(alignment: .leading, spacing: 2) {
                        if let title = row.agentContextTitle {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(colorForContextType(contextType))
                        }
                        if let description = row.agentContextDescription {
                            Text(description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let detail = row.agentContextDetail {
                            Text(detail)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.8))
                        }
                    }
                }
                .padding(.top, 4)
            }

            // Legacy metadata (only show if no rich context)
            if row.agentContextType == nil, row.agentIdentity != nil || row.evidenceSummary != nil {
                HStack(spacing: 8) {
                    if let agentIdentity = row.agentIdentity {
                        Text(agentIdentity.replacingOccurrences(of: "_", with: " "))
                    }
                    if let agentInteractionState = row.agentInteractionState {
                        Text(agentInteractionState.replacingOccurrences(of: "_", with: " "))
                    }
                    if let evidenceSummary = row.evidenceSummary {
                        Text(evidenceSummary.replacingOccurrences(of: "_", with: " "))
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            if !row.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(row.suggestedActions.prefix(2), id: \.title) { action in
                        HStack(spacing: 4) {
                            Image(systemName: action.isRecommended ? "star.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(action.isRecommended ? .yellow : .secondary)
                            Text(action.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(row.isFocused ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    attentionBorderColor,
                    lineWidth: attentionBorderWidth
                )
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

    private var attentionBorderColor: Color {
        if !row.isFocused, row.agentContextType == "waitingApproval" || row.agentContextType == "waitingChoice" || row.agentContextType == "waitingText" {
            return Color.orange.opacity(0.5)
        }
        return row.isFocused ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.08)
    }

    private var attentionBorderWidth: CGFloat {
        if !row.isFocused, row.agentContextType == "waitingApproval" || row.agentContextType == "waitingChoice" || row.agentContextType == "waitingText" {
            return 2
        }
        return 1
    }
}

// MARK: - Context type helpers

private func iconForContextType(_ type: String) -> String {
    switch type.lowercased() {
    case "running":
        return "arrow.triangle.2.circlepath"
    case "waitingapproval":
        return "exclamationmark.shield"
    case "waitingchoice":
        return "list.bullet.clipboard"
    case "waitingtext":
        return "bubble.left.and.bubble.right"
    case "completed":
        return "checkmark.circle"
    case "error":
        return "xmark.octagon"
    default:
        return "circle"
    }
}

private func colorForContextType(_ type: String) -> Color {
    switch type.lowercased() {
    case "running":
        return .blue
    case "waitingapproval":
        return .orange
    case "waitingchoice":
        return .yellow
    case "waitingtext":
        return .purple
    case "completed":
        return .green
    case "error":
        return .red
    default:
        return .secondary
    }
}
