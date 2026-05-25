import Foundation

enum PendingAgentAttentionFactory {
    static func make(
        from event: AgentNeedsAttentionEvent,
        understanding: TerminalUnderstanding?
    ) -> PendingAgentAttention? {
        if let authoritative = authoritativeAttention(from: event, understanding: understanding) {
            return authoritative
        }

        switch event.interactionState {
        case .waitingApproval:
            let actions = approvalActions(for: event, understanding: understanding)

            return PendingAgentAttention(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                fingerprint: event.fingerprint,
                title: "Needs your approval",
                description: understanding?.agentInteractionContext.descriptionString ?? event.deltaText,
                detail: understanding?.agentInteractionContext.detailString,
                actions: actions
            )

        case .waitingChoice:
            let options = understanding?.agentInteractionContext.optionsArray ?? []
            guard !options.isEmpty else {
                return nil
            }

            let actions = options.prefix(4).enumerated().map { index, option in
                PendingAgentAction(
                    id: "choice_\(index + 1)",
                    title: option,
                    payload: "\(index + 1)",
                    style: index == 0 ? .primary : .secondary
                )
            }

            return PendingAgentAttention(
                terminalID: event.terminalID,
                agentIdentity: event.agentIdentity,
                interactionState: event.interactionState,
                fingerprint: event.fingerprint,
                title: "Choose an option",
                description: understanding?.agentInteractionContext.descriptionString ?? event.deltaText,
                detail: nil,
                actions: actions
            )

        default:
            return nil
        }
    }

    private static func authoritativeAttention(
        from event: AgentNeedsAttentionEvent,
        understanding: TerminalUnderstanding?
    ) -> PendingAgentAttention? {
        guard let understanding,
              let snapshot = understanding.workerSnapshot,
              let request = snapshot.request else {
            return nil
        }

        let requestSuggestions = snapshot.suggestions.filter { suggestion in
            suggestion.requestID == nil || suggestion.requestID == request.id
        }

        switch request.kind {
        case .reply:
            let actions = requestSuggestions.prefix(4).map { makePendingAction(from: $0) }
            guard !actions.isEmpty else {
                return nil
            }

            return PendingAgentAttention(
                terminalID: snapshot.terminalID,
                agentIdentity: snapshot.agent.identity,
                interactionState: understanding.agentInteractionState,
                fingerprint: event.fingerprint,
                title: "Suggested reply",
                description: request.prompt,
                detail: snapshot.state.details.joined(separator: "\n").nilIfEmpty,
                actions: actions
            )

        case .choice:
            let actions = requestSuggestions.isEmpty
                ? fallbackChoiceActions(for: request)
                : requestSuggestions.prefix(4).map { makePendingAction(from: $0) }
            guard !actions.isEmpty else {
                return nil
            }

            return PendingAgentAttention(
                terminalID: snapshot.terminalID,
                agentIdentity: snapshot.agent.identity,
                interactionState: understanding.agentInteractionState,
                fingerprint: event.fingerprint,
                title: "Choose an option",
                description: request.prompt,
                detail: nil,
                actions: actions
            )

        case .approval:
            let actions = requestSuggestions.isEmpty
                ? approvalActions(for: event, understanding: understanding)
                : requestSuggestions.prefix(4).map { makePendingAction(from: $0) }
            guard !actions.isEmpty else {
                return nil
            }

            let detail = request.options.map(\.label).joined(separator: "\n").nilIfEmpty ??
                snapshot.state.details.joined(separator: "\n").nilIfEmpty

            return PendingAgentAttention(
                terminalID: snapshot.terminalID,
                agentIdentity: snapshot.agent.identity,
                interactionState: understanding.agentInteractionState,
                fingerprint: event.fingerprint,
                title: "Needs your approval",
                description: request.prompt,
                detail: detail,
                actions: actions
            )

        case .command:
            return nil
        }
    }

    private static func approvalActions(
        for event: AgentNeedsAttentionEvent,
        understanding: TerminalUnderstanding?
    ) -> [PendingAgentAction] {
        let promptText = [
            event.deltaText,
            understanding?.importantDetails.joined(separator: "\n"),
            understanding?.agentInteractionContext.descriptionString,
        ]
            .compactMap { text in
                guard let text else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n")

        let parsedActions = parsedApprovalActions(from: promptText)
        guard parsedActions.isEmpty else {
            return parsedActions
        }

        switch event.agentIdentity {
        case .kimi:
            return [
                .init(id: "approve_once", title: "Approve once", payload: "1", style: .primary),
                .init(id: "approve_session", title: "Approve for session", payload: "2", style: .secondary),
                .init(id: "reject", title: "Reject", payload: "3", style: .destructive),
            ]

        case .codex, .claudeCode:
            return [
                .init(id: "approve", title: "Approve", payload: "y", style: .primary),
                .init(id: "reject", title: "Reject", payload: "n", style: .destructive),
            ]

        case .none, .unknown:
            return []
        }
    }

    private static func parsedApprovalActions(from text: String) -> [PendingAgentAction] {
        let lines = text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var seenIDs = Set<String>()
        var actions: [PendingAgentAction] = []

        for line in lines {
            guard let option = parseApprovalOptionLine(line) else { continue }
            guard seenIDs.insert(option.id).inserted else { continue }
            actions.append(option)
        }

        return actions
    }

    private static func parseApprovalOptionLine(_ line: String) -> PendingAgentAction? {
        guard let option = optionPayloadAndLabel(from: line) else {
            return nil
        }

        let loweredLabel = option.label.lowercased()

        if containsAny(loweredLabel, markers: ["approve once", "accept once", "allow once"]) {
            return .init(id: "approve_once", title: "Approve once", payload: option.payload, style: .primary)
        }

        if containsAny(
            loweredLabel,
            markers: ["approve for this session", "approve session", "accept for session", "allow for this session"]
        ) {
            return .init(id: "approve_session", title: "Approve for session", payload: option.payload, style: .secondary)
        }

        if containsAny(loweredLabel, markers: ["always allow", "allow always", "accept and add to policy"]) {
            return .init(id: "approve_persistent", title: "Always allow", payload: option.payload, style: .secondary)
        }

        if loweredLabel.contains("reject, tell the model what to do instead") {
            return .init(id: "reject_with_feedback", title: "Reject with feedback", payload: option.payload, style: .destructive)
        }

        if containsAny(loweredLabel, markers: ["reject", "decline", "deny"]) {
            return .init(id: "reject", title: "Reject", payload: option.payload, style: .destructive)
        }

        if loweredLabel.contains("cancel turn") {
            return .init(id: "cancel_turn", title: "Cancel turn", payload: option.payload, style: .secondary)
        }

        return nil
    }

    private static func optionPayloadAndLabel(from line: String) -> (payload: String, label: String)? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("❯ ") {
            trimmed = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        if trimmed.hasPrefix("["),
           let closingBracket = trimmed.firstIndex(of: "]") {
            let payload = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracket])
            let label = String(trimmed[trimmed.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
            return payload.isEmpty || label.isEmpty ? nil : (payload, label)
        }

        if let dotRange = trimmed.range(of: ". "),
           dotRange.lowerBound != trimmed.startIndex {
            let payload = String(trimmed[..<dotRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let label = String(trimmed[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return payload.isEmpty || label.isEmpty ? nil : (payload, label)
        }

        if trimmed.count > 2 {
            let firstCharacter = trimmed[trimmed.startIndex]
            let secondIndex = trimmed.index(after: trimmed.startIndex)
            if trimmed[secondIndex] == ")" {
                let payload = String(firstCharacter)
                let label = String(trimmed[trimmed.index(after: secondIndex)...]).trimmingCharacters(in: .whitespaces)
                return label.isEmpty ? nil : (payload, label)
            }
        }

        return nil
    }

    private static func containsAny(_ text: String, markers: [String]) -> Bool {
        markers.contains(where: text.contains)
    }

    private static func fallbackChoiceActions(
        for request: TerminalWorkerSnapshot.Request
    ) -> [PendingAgentAction] {
        request.options.prefix(4).enumerated().map { index, option in
            PendingAgentAction(
                id: "choice_\(index + 1)",
                title: option.label,
                payload: option.id,
                style: option.recommended || index == 0 ? .primary : .secondary
            )
        }
    }

    private static func makePendingAction(
        from suggestion: TerminalWorkerSnapshot.Suggestion
    ) -> PendingAgentAction {
        PendingAgentAction(
            id: suggestion.id,
            title: suggestion.title,
            payload: payloadText(from: suggestion.payload),
            style: actionStyle(for: suggestion)
        )
    }

    private static func payloadText(
        from payload: TerminalWorkerSnapshot.Payload
    ) -> String {
        switch payload {
        case .text(let value), .command(let value), .option(let value), .approval(let value), .foremanPrompt(let value):
            return value
        }
    }

    private static func actionStyle(
        for suggestion: TerminalWorkerSnapshot.Suggestion
    ) -> PendingAgentAction.Style {
        let loweredTitle = suggestion.title.lowercased()
        if loweredTitle.contains("reject") || loweredTitle.contains("deny") {
            return .destructive
        }

        return suggestion.recommended ? .primary : .secondary
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
