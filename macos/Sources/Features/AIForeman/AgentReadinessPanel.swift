import SwiftUI

struct AgentReadinessPanel: View {
    struct AgentRow: Identifiable {
        let id = UUID()
        let identity: AgentIdentity
        let state: AgentReadinessState
    }

    let agents: [AgentRow]
    let onLaunch: (AgentIdentity) -> Void

    init(agents: [(AgentIdentity, AgentReadinessState)], onLaunch: @escaping (AgentIdentity) -> Void) {
        self.agents = agents.map { AgentRow(identity: $0.0, state: $0.1) }
        self.onLaunch = onLaunch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            ForEach(Array(agents.enumerated()), id: \.element.id) { _, agent in
                rowView(for: agent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.03)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("foreman.agent-readiness")
    }

    @ViewBuilder
    private func rowView(for agent: AgentRow) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(agent.state))
                .frame(width: 6, height: 6)

            Text(agent.identity.displayName ?? "Unknown")
                .font(.system(size: 11, weight: .medium))

            Spacer()

            if case .installed = agent.state {
                Button("Launch") {
                    onLaunch(agent.identity)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .accessibilityLabel("Launch \(agent.identity.displayName ?? "Unknown")")
                .accessibilityIdentifier("foreman.launch.\(agent.identity.rawValue)")
            } else {
                Text(statusLabel(agent.state))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("foreman.agent.\(agent.identity.rawValue)")
    }

    private func statusColor(_ state: AgentReadinessState) -> Color {
        switch state {
        case .unknown:
            return .secondary
        case .notInstalled:
            return .red
        case .installed(let loginStatus):
            switch loginStatus {
            case .unknown:
                return .green
            case .notLoggedIn:
                return .yellow
            case .loggedIn:
                return .green
            }
        }
    }

    private func statusLabel(_ state: AgentReadinessState) -> String {
        switch state {
        case .unknown:
            return "Checking..."
        case .notInstalled:
            return "Not installed"
        case .installed(let loginStatus):
            switch loginStatus {
            case .unknown:
                return "Ready"
            case .notLoggedIn:
                return "Login needed"
            case .loggedIn:
                return "Ready"
            }
        }
    }
}
