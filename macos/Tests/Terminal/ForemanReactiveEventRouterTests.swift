import Foundation
import Testing
@testable import Ghostty

struct ForemanReactiveEventRouterTests {
    private struct AttentionCase {
        let event: AgentNeedsAttentionEvent
        let understanding: TerminalUnderstanding
    }

    private struct InitialDecisionSignature: Equatable {
        enum Kind: Equatable {
            case showPendingAttention
            case draftWaitingText
            case react
        }

        let kind: Kind
        let title: String?
        let description: String?
        let detail: String?
        let actions: [PendingAgentAction]
    }

    @Test
    func kimiApprovalInitialDecisionKeepsManagedLaunchParity() {
        let signatures = kimiApprovalCases().map { entry in
            signature(
                ForemanReactiveEventRouter.initialDecision(
                    for: entry.event,
                    understanding: entry.understanding
                )
            )
        }
        let firstSignature = signatures.first

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
        #expect(firstSignature?.kind == InitialDecisionSignature.Kind.showPendingAttention)
        #expect(firstSignature?.title == "Needs your approval")
        #expect(firstSignature?.description == "Kimi wants to edit auth.ts.")
        #expect(firstSignature?.detail == "WriteFile")
    }

    @Test
    func codexApprovalInitialDecisionKeepsManagedLaunchParity() {
        let signatures = codexApprovalCases().map { entry in
            signature(
                ForemanReactiveEventRouter.initialDecision(
                    for: entry.event,
                    understanding: entry.understanding
                )
            )
        }
        let firstSignature = signatures.first

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
        #expect(firstSignature?.kind == InitialDecisionSignature.Kind.showPendingAttention)
        #expect(firstSignature?.title == "Needs your approval")
        #expect(firstSignature?.description == "Codex wants to run the suggested command.")
        #expect(firstSignature?.detail == "Shell")
        #expect(firstSignature?.actions.map { $0.title } == ["Approve", "Reject"])
    }

    @Test
    func claudeApprovalInitialDecisionKeepsManagedLaunchParity() {
        let signatures = claudeApprovalCases().map { entry in
            signature(
                ForemanReactiveEventRouter.initialDecision(
                    for: entry.event,
                    understanding: entry.understanding
                )
            )
        }
        let firstSignature = signatures.first

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
        #expect(firstSignature?.kind == InitialDecisionSignature.Kind.showPendingAttention)
        #expect(firstSignature?.title == "Needs your approval")
        #expect(firstSignature?.description == "Claude wants to run the suggested command.")
        #expect(firstSignature?.detail == "Shell")
        #expect(firstSignature?.actions.map { $0.title } == ["Approve", "Reject"])
    }

    @Test
    func approvalInitialDecisionUsesVisibleCapabilitiesTruthfullyAcrossModelsAndLaunchPaths() {
        let cases: [
            (
                agentIdentity: AgentIdentity,
                description: String,
                tool: String,
                deltaText: String,
                expectedTitles: [String]
            )
        ] = [
            (
                agentIdentity: .kimi,
                description: "Kimi wants to edit auth.ts.",
                tool: "WriteFile",
                deltaText: """
                Shell is requesting approval to run command

                1. Approve once
                2. Approve for this session
                3. Reject, tell the model what to do instead
                """,
                expectedTitles: ["Approve once", "Approve for session", "Reject with feedback"]
            ),
            (
                agentIdentity: .codex,
                description: "Codex wants to run the suggested command.",
                tool: "Shell",
                deltaText: """
                Permission required

                [a] Accept once
                [s] Accept for session
                [d] Decline
                """,
                expectedTitles: ["Approve once", "Approve for session", "Reject"]
            ),
            (
                agentIdentity: .claudeCode,
                description: "Claude wants to run the suggested command.",
                tool: "Shell",
                deltaText: """
                Claude needs approval

                [y] Allow once
                [s] Always allow
                [n] Deny
                """,
                expectedTitles: ["Approve once", "Always allow", "Reject"]
            ),
        ]

        for entry in cases {
            let signatures = makeApprovalCases(
                agentIdentity: entry.agentIdentity,
                description: entry.description,
                tool: entry.tool,
                deltaText: entry.deltaText
            ).map { approvalCase in
                signature(
                    ForemanReactiveEventRouter.initialDecision(
                        for: approvalCase.event,
                        understanding: approvalCase.understanding
                    )
                )
            }
            let firstSignature = signatures.first

            #expect(signatures.count == 3)
            #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
            #expect(firstSignature?.kind == InitialDecisionSignature.Kind.showPendingAttention)
            #expect(firstSignature?.actions.map(\.title) == entry.expectedTitles)
        }
    }

    @Test
    func claudeChoiceInitialDecisionKeepsManagedLaunchParity() {
        let signatures = claudeChoiceCases().map { entry in
            signature(
                ForemanReactiveEventRouter.initialDecision(
                    for: entry.event,
                    understanding: entry.understanding
                )
            )
        }
        let firstSignature = signatures.first

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
        #expect(firstSignature?.kind == InitialDecisionSignature.Kind.showPendingAttention)
        #expect(firstSignature?.title == "Choose an option")
        #expect(firstSignature?.description == "What do you want to do next?")
        #expect(firstSignature?.actions.map { $0.title } == ["Continue", "Explain", "Stop", "Open docs"])
    }

    @Test
    func waitingTextInitialDecisionKeepsManagedLaunchParity() {
        let decisions: [ForemanReactiveEventRouter.InitialDecision] = waitingTextCases().map { entry in
            ForemanReactiveEventRouter.initialDecision(
                for: entry.event,
                understanding: entry.understanding
            )
        }

        #expect(decisions == [
            ForemanReactiveEventRouter.InitialDecision.draftWaitingText,
            ForemanReactiveEventRouter.InitialDecision.draftWaitingText,
            ForemanReactiveEventRouter.InitialDecision.draftWaitingText,
        ])
    }

    @Test
    func authoritativeWaitingTextSuggestionShowsPendingAttention() {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-41",
            revision: 41,
            observedAt: Date(timeIntervalSince1970: 1_748_222_222),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for a reply.",
                details: ["Asked whether the API should stay stable."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-41",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "preserve-api",
                    kind: .reply,
                    title: "Preserve the API",
                    payload: .text("Preserve the current API and adapt the internals."),
                    rationale: "Lowest migration risk.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-41"
                ),
            ]
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for a reply.",
            lastMeaningfulEvent: "Should I preserve the API?",
            importantDetails: [],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            workerSnapshot: snapshot
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            deltaText: "Should I preserve the API?",
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: snapshot.attentionFingerprint
        )

        let decision = ForemanReactiveEventRouter.initialDecision(
            for: event,
            understanding: understanding
        )

        #expect(signature(decision).kind == .showPendingAttention)
        #expect(signature(decision).title == "Suggested reply")
        #expect(signature(decision).actions.map(\.title) == ["Preserve the API"])
    }

    @Test
    func draftDecisionReturnsDraftedAttentionWhenPresent() {
        let attention = PendingAgentAttention(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingText,
            fingerprint: "fp-1",
            title: "Suggested reply",
            description: "Codex is waiting for direction.",
            detail: "What should I work on next?",
            actions: [
                .init(id: "reply", title: "Inspect the failing test.", payload: "Inspect the failing test.", style: .primary)
            ]
        )

        #expect(
            ForemanReactiveEventRouter.decisionAfterDraft(
                for: AgentInteractionState.waitingText,
                draftedAttention: attention
            ) == .showPendingAttention(attention)
        )
    }

    @Test
    func waitingTextWithoutDraftDoesNotFallBackToChatReaction() {
        #expect(
            ForemanReactiveEventRouter.decisionAfterDraft(
                for: AgentInteractionState.waitingText,
                draftedAttention: Optional<PendingAgentAttention>.none
            ) == .ignore
        )
    }

    @Test
    func nonTextWithoutDraftFallsBackToReaction() {
        #expect(
            ForemanReactiveEventRouter.decisionAfterDraft(
                for: AgentInteractionState.error,
                draftedAttention: Optional<PendingAgentAttention>.none
            ) == .react
        )
    }

    private func signature(
        _ decision: ForemanReactiveEventRouter.InitialDecision
    ) -> InitialDecisionSignature {
        switch decision {
        case .showPendingAttention(let attention):
            InitialDecisionSignature(
                kind: .showPendingAttention,
                title: attention.title,
                description: attention.description,
                detail: attention.detail,
                actions: attention.actions
            )
        case .draftWaitingText:
            InitialDecisionSignature(
                kind: .draftWaitingText,
                title: nil,
                description: nil,
                detail: nil,
                actions: []
            )
        case .react:
            InitialDecisionSignature(
                kind: .react,
                title: nil,
                description: nil,
                detail: nil,
                actions: []
            )
        }
    }

    private func kimiApprovalCases() -> [AttentionCase] {
        makeApprovalCases(
            agentIdentity: .kimi,
            description: "Kimi wants to edit auth.ts.",
            tool: "WriteFile",
            deltaText: "Allow edit to auth.ts? [1/2/3]"
        )
    }

    private func codexApprovalCases() -> [AttentionCase] {
        makeApprovalCases(
            agentIdentity: .codex,
            description: "Codex wants to run the suggested command.",
            tool: "Shell",
            deltaText: "Run the suggested command? [y/n]"
        )
    }

    private func claudeApprovalCases() -> [AttentionCase] {
        makeApprovalCases(
            agentIdentity: .claudeCode,
            description: "Claude wants to run the suggested command.",
            tool: "Shell",
            deltaText: "Run the suggested command? [y/n]"
        )
    }

    private func claudeChoiceCases() -> [AttentionCase] {
        let options = ["Continue", "Explain", "Stop", "Open docs", "Archive"]

        return [
            makeChoiceCase(
                terminalID: "claude-existing-choice",
                title: "nambouchara@host:~/speed2/ghostty",
                evidence: [.runtime],
                description: "What do you want to do next?",
                options: options
            ),
            makeChoiceCase(
                terminalID: "claude-new-tab-choice",
                title: "nambouchara@host:~/speed2/ghostty",
                evidence: [.runtime],
                description: "What do you want to do next?",
                options: options
            ),
            makeChoiceCase(
                terminalID: "claude-managed-choice",
                title: "Claude Code",
                evidence: [.managedLaunch],
                description: "What do you want to do next?",
                options: options
            ),
        ]
    }

    private func waitingTextCases() -> [AttentionCase] {
        [
            makeWaitingTextCase(
                terminalID: "codex-existing-text",
                title: "nambouchara@host:~/speed2/ghostty",
                evidence: [.runtime],
                agentIdentity: .codex,
                question: "• Hello. What do you want to work on in ghostty?"
            ),
            makeWaitingTextCase(
                terminalID: "codex-new-tab-text",
                title: "nambouchara@host:~/speed2/ghostty",
                evidence: [.runtime],
                agentIdentity: .codex,
                question: "• Hello. What do you want to work on in ghostty?"
            ),
            makeWaitingTextCase(
                terminalID: "codex-managed-text",
                title: "Codex",
                evidence: [.managedLaunch],
                agentIdentity: .codex,
                question: "• Hello. What do you want to work on in ghostty?"
            ),
        ]
    }

    private func makeApprovalCases(
        agentIdentity: AgentIdentity,
        description: String,
        tool: String,
        deltaText: String
    ) -> [AttentionCase] {
        [
            makeApprovalCase(
                terminalID: "\(agentIdentity.rawValue)-existing-approval",
                title: "nambouchara@host:~/speed2/ghostty",
                evidence: [.runtime],
                agentIdentity: agentIdentity,
                description: description,
                tool: tool,
                deltaText: deltaText
            ),
            makeApprovalCase(
                terminalID: "\(agentIdentity.rawValue)-new-tab-approval",
                title: "nambouchara@host:~/speed2/ghostty",
                evidence: [.runtime],
                agentIdentity: agentIdentity,
                description: description,
                tool: tool,
                deltaText: deltaText
            ),
            makeApprovalCase(
                terminalID: "\(agentIdentity.rawValue)-managed-approval",
                title: agentIdentity.displayName ?? agentIdentity.rawValue,
                evidence: [.managedLaunch],
                agentIdentity: agentIdentity,
                description: description,
                tool: tool,
                deltaText: deltaText
            ),
        ]
    }

    private func makeApprovalCase(
        terminalID: String,
        title: String,
        evidence: [UnderstandingEvidenceSource],
        agentIdentity: AgentIdentity,
        description: String,
        tool: String,
        deltaText: String
    ) -> AttentionCase {
        let understanding = TerminalUnderstanding(
            terminalID: terminalID,
            title: title,
            cwd: "/tmp/project",
            state: .waiting,
            agentIdentity: agentIdentity,
            agentInteractionState: .waitingApproval,
            supportLevel: .firstClass,
            lastMeaningfulEvent: description,
            shortExplanation: "Waiting for approval.",
            importantDetails: [deltaText],
            evidence: evidence.map {
                .init(source: $0, detail: "\($0.rawValue) evidence", confidence: 1.0)
            },
            suggestedNextActions: [],
            agentInteractionContext: .waitingApproval(description: description, tool: tool)
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: terminalID,
            agentIdentity: agentIdentity,
            interactionState: .waitingApproval,
            deltaText: deltaText,
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: "\(terminalID)|approval"
        )

        return AttentionCase(event: event, understanding: understanding)
    }

    private func makeChoiceCase(
        terminalID: String,
        title: String,
        evidence: [UnderstandingEvidenceSource],
        description: String,
        options: [String]
    ) -> AttentionCase {
        let understanding = TerminalUnderstanding(
            terminalID: terminalID,
            title: title,
            cwd: "/tmp/project",
            state: .waiting,
            agentIdentity: .claudeCode,
            agentInteractionState: .waitingChoice,
            supportLevel: .firstClass,
            lastMeaningfulEvent: description,
            shortExplanation: "Waiting for a choice.",
            importantDetails: options,
            evidence: evidence.map {
                .init(source: $0, detail: "\($0.rawValue) evidence", confidence: 1.0)
            },
            suggestedNextActions: [],
            agentInteractionContext: .waitingChoice(question: description, options: options)
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: terminalID,
            agentIdentity: .claudeCode,
            interactionState: .waitingChoice,
            deltaText: description,
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: "\(terminalID)|choice"
        )

        return AttentionCase(event: event, understanding: understanding)
    }

    private func makeWaitingTextCase(
        terminalID: String,
        title: String,
        evidence: [UnderstandingEvidenceSource],
        agentIdentity: AgentIdentity,
        question: String
    ) -> AttentionCase {
        let understanding = TerminalUnderstanding(
            terminalID: terminalID,
            title: title,
            cwd: "/tmp/project",
            state: .waiting,
            agentIdentity: agentIdentity,
            agentInteractionState: .waitingText,
            supportLevel: .firstClass,
            lastMeaningfulEvent: question,
            shortExplanation: "Waiting for a reply.",
            importantDetails: [question],
            evidence: evidence.map {
                .init(source: $0, detail: "\($0.rawValue) evidence", confidence: 1.0)
            },
            suggestedNextActions: [],
            agentInteractionContext: .waitingText(question: question)
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: terminalID,
            agentIdentity: agentIdentity,
            interactionState: .waitingText,
            deltaText: question,
            timestamp: Date(timeIntervalSince1970: 1),
            fingerprint: "\(terminalID)|waiting-text"
        )

        return AttentionCase(event: event, understanding: understanding)
    }
}
