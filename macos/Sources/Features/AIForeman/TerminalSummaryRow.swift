import SwiftUI

struct TerminalSummaryRow: View {
    let row: TerminalSummaryRowModel
    var onExecuteSuggestion: ((String, TerminalSuggestedAction) -> Void)?
    var onExecutePendingAttentionAction: ((PendingAgentAttention, PendingAgentAction) -> Void)?

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

            if let attention = row.pendingAttention {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: iconForContextType(attention.interactionState.rawValue))
                            .font(.system(size: 11))
                            .foregroundStyle(colorForContextType(attention.interactionState.rawValue))

                        Text(attention.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colorForContextType(attention.interactionState.rawValue))

                        Spacer(minLength: 8)

                        if attention.status == .sending {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Text(attention.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = attention.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    HStack(spacing: 6) {
                        ForEach(attention.actions.prefix(4)) { action in
                            Button(action.title) {
                                onExecutePendingAttentionAction?(attention, action)
                            }
                            .buttonStyle(PendingAgentActionButtonStyle(style: action.style))
                            .controlSize(.small)
                            .disabled(attention.status == .sending)
                        }
                    }

                    if let errorMessage = attention.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
            }

            if !row.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(row.suggestedActions.prefix(2), id: \.title) { action in
                        Button(action: {
                            onExecuteSuggestion?(row.terminalID, action)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: suggestionIcon(for: action))
                                    .font(.system(size: 8))
                                Text(action.title)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(SuggestedActionButtonStyle(isRecommended: action.isRecommended))
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
        if row.pendingAttention != nil {
            return Color.orange.opacity(0.6)
        }
        if !row.isFocused, row.agentContextType == "waitingApproval" || row.agentContextType == "waitingChoice" || row.agentContextType == "waitingText" {
            return Color.orange.opacity(0.5)
        }
        return row.isFocused ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.08)
    }

    private var attentionBorderWidth: CGFloat {
        if row.pendingAttention != nil {
            return 2
        }
        if !row.isFocused, row.agentContextType == "waitingApproval" || row.agentContextType == "waitingChoice" || row.agentContextType == "waitingText" {
            return 2
        }
        return 1
    }
}

private func suggestionIcon(for action: TerminalSuggestedAction) -> String {
    if action.isRecommended {
        return "star.fill"
    }

    return action.command == nil ? "bubble.left.and.bubble.right" : "bolt.fill"
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

struct PendingAgentActionButtonStyle: ButtonStyle {
    let style: PendingAgentAction.Style

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return .white
        case .secondary:
            return .primary
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch style {
        case .primary:
            return isPressed ? Color.blue.opacity(0.75) : Color.blue
        case .secondary:
            return isPressed ? Color.secondary.opacity(0.25) : Color.secondary.opacity(0.12)
        case .destructive:
            return isPressed ? Color.red.opacity(0.75) : Color.red
        }
    }
}

// MARK: - Suggested Action Button Style

struct SuggestedActionButtonStyle: ButtonStyle {
    let isRecommended: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isRecommended ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecommended
                        ? (configuration.isPressed ? Color.blue.opacity(0.7) : Color.blue)
                        : (configuration.isPressed ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.1))
                    )
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
