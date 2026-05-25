import Foundation
import Testing
@testable import Ghostty

struct PendingAgentAttentionFactoryTests {
    private struct AttentionCase {
        let event: AgentNeedsAttentionEvent
        let understanding: TerminalUnderstanding
    }

    private struct AttentionParitySignature: Equatable {
        let agentIdentity: AgentIdentity
        let interactionState: AgentInteractionState
        let title: String
        let description: String
        let detail: String?
        let actions: [PendingAgentAction]
    }

    @Test
    func kimiApprovalAttentionKeepsManagedLaunchParity() throws {
        let signatures = try kimiApprovalCases().map { entry in
            let attention = try #require(
                PendingAgentAttentionFactory.make(from: entry.event, understanding: entry.understanding)
            )
            return paritySignature(attention)
        }
        let firstSignature = try #require(signatures.first)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
        #expect(firstSignature.title == "Needs your approval")
        #expect(firstSignature.description == "Kimi wants to edit auth.ts.")
        #expect(firstSignature.detail == "WriteFile")
        #expect(firstSignature.actions == [
            PendingAgentAction(id: "approve_once", title: "Approve once", payload: "1", style: .primary),
            PendingAgentAction(id: "approve_session", title: "Approve for session", payload: "2", style: .secondary),
            PendingAgentAction(id: "reject", title: "Reject", payload: "3", style: .destructive),
        ])
    }

    @Test
    func codexApprovalAttentionKeepsManagedLaunchParity() throws {
        let signatures = try codexApprovalCases().map { entry in
            let attention = try #require(
                PendingAgentAttentionFactory.make(from: entry.event, understanding: entry.understanding)
            )
            return paritySignature(attention)
        }
        let firstSignature = try #require(signatures.first)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
        #expect(firstSignature.title == "Needs your approval")
        #expect(firstSignature.description == "Codex wants to run the suggested command.")
        #expect(firstSignature.detail == "Shell")
        #expect(firstSignature.actions == [
            PendingAgentAction(id: "approve", title: "Approve", payload: "y", style: .primary),
            PendingAgentAction(id: "reject", title: "Reject", payload: "n", style: .destructive),
        ])
    }

    @Test
    func claudeApprovalAttentionKeepsManagedLaunchParity() throws {
        let signatures = try claudeApprovalCases().map { entry in
            let attention = try #require(
                PendingAgentAttentionFactory.make(from: entry.event, understanding: entry.understanding)
            )
            return paritySignature(attention)
        }
        let firstSignature = try #require(signatures.first)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
        #expect(firstSignature.title == "Needs your approval")
        #expect(firstSignature.description == "Claude wants to run the suggested command.")
        #expect(firstSignature.detail == "Shell")
        #expect(firstSignature.actions == [
            PendingAgentAction(id: "approve", title: "Approve", payload: "y", style: .primary),
            PendingAgentAction(id: "reject", title: "Reject", payload: "n", style: .destructive),
        ])
    }

    @Test
    func approvalAttentionUsesVisibleCapabilitiesTruthfullyAcrossModelsAndLaunchPaths() throws {
        let cases: [
            (
                agentIdentity: AgentIdentity,
                description: String,
                tool: String,
                deltaText: String,
                expectedActions: [PendingAgentAction]
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
                expectedActions: [
                    PendingAgentAction(id: "approve_once", title: "Approve once", payload: "1", style: .primary),
                    PendingAgentAction(id: "approve_session", title: "Approve for session", payload: "2", style: .secondary),
                    PendingAgentAction(id: "reject_with_feedback", title: "Reject with feedback", payload: "3", style: .destructive),
                ]
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
                expectedActions: [
                    PendingAgentAction(id: "approve_once", title: "Approve once", payload: "a", style: .primary),
                    PendingAgentAction(id: "approve_session", title: "Approve for session", payload: "s", style: .secondary),
                    PendingAgentAction(id: "reject", title: "Reject", payload: "d", style: .destructive),
                ]
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
                expectedActions: [
                    PendingAgentAction(id: "approve_once", title: "Approve once", payload: "y", style: .primary),
                    PendingAgentAction(id: "approve_persistent", title: "Always allow", payload: "s", style: .secondary),
                    PendingAgentAction(id: "reject", title: "Reject", payload: "n", style: .destructive),
                ]
            ),
        ]

        for entry in cases {
            let signatures = try makeApprovalCases(
                agentIdentity: entry.agentIdentity,
                description: entry.description,
                tool: entry.tool,
                deltaText: entry.deltaText
            ).map { approvalCase in
                let attention = try #require(
                    PendingAgentAttentionFactory.make(
                        from: approvalCase.event,
                        understanding: approvalCase.understanding
                    )
                )
                return paritySignature(attention)
            }
            let firstSignature = try #require(signatures.first)

            #expect(signatures.count == 3)
            #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
            #expect(firstSignature.actions == entry.expectedActions)
        }
    }

    @Test
    func claudeChoiceAttentionKeepsManagedLaunchParity() throws {
        let signatures = try claudeChoiceCases().map { entry in
            let attention = try #require(
                PendingAgentAttentionFactory.make(from: entry.event, understanding: entry.understanding)
            )
            return paritySignature(attention)
        }
        let firstSignature = try #require(signatures.first)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == firstSignature })
        #expect(firstSignature.title == "Choose an option")
        #expect(firstSignature.description == "What do you want to do next?")
        #expect(firstSignature.detail == nil)
        #expect(firstSignature.actions == [
            PendingAgentAction(id: "choice_1", title: "Continue", payload: "1", style: .primary),
            PendingAgentAction(id: "choice_2", title: "Explain", payload: "2", style: .secondary),
            PendingAgentAction(id: "choice_3", title: "Stop", payload: "3", style: .secondary),
            PendingAgentAction(id: "choice_4", title: "Open docs", payload: "4", style: .secondary),
        ])
    }

    @Test
    func authoritativeReplySuggestionBecomesPrimaryAction() throws {
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
            timestamp: Date(),
            fingerprint: snapshot.attentionFingerprint
        )

        let attention = try #require(
            PendingAgentAttentionFactory.make(from: event, understanding: understanding)
        )

        #expect(attention.title == "Suggested reply")
        #expect(attention.actions.first?.title == "Preserve the API")
        #expect(attention.fingerprint == snapshot.attentionFingerprint)
    }

    @Test
    func authoritativeReplyWithoutSuggestionEscalatesNeedsDirection() throws {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-42",
            revision: 42,
            observedAt: Date(timeIntervalSince1970: 1_748_222_223),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for your reply.",
                details: ["Should I preserve the API?"],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-42",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: []
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for your reply.",
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
            timestamp: Date(),
            fingerprint: snapshot.attentionFingerprint
        )

        let attention = try #require(
            PendingAgentAttentionFactory.make(from: event, understanding: understanding)
        )

        #expect(attention.title == "Needs direction")
        #expect(attention.description == "Should I preserve the API?")
        #expect(attention.detail == nil)
        #expect(attention.actions.isEmpty)
        #expect(attention.fingerprint == snapshot.attentionFingerprint)
    }

    @Test
    func authoritativeReplyIgnoresSuggestionsFromOlderRequests() throws {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-42",
            revision: 43,
            observedAt: Date(timeIntervalSince1970: 1_748_222_224),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for your reply.",
                details: ["A stale recommendation should not be used."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-current",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "stale",
                    kind: .reply,
                    title: "Follow the old plan",
                    payload: .text("Use the previous migration path."),
                    rationale: "This suggestion belongs to the old request.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-old"
                ),
            ]
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for your reply.",
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
            timestamp: Date(),
            fingerprint: snapshot.attentionFingerprint
        )

        let attention = try #require(
            PendingAgentAttentionFactory.make(from: event, understanding: understanding)
        )

        #expect(attention.title == "Needs direction")
        #expect(attention.description == "Should I preserve the API?")
        #expect(attention.detail == "A stale recommendation should not be used.")
        #expect(attention.actions.isEmpty)
    }

    @Test
    func authoritativeReplyForemanPromptSuggestionEscalatesNeedsDirection() throws {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-43",
            revision: 43,
            observedAt: Date(timeIntervalSince1970: 1_748_222_224),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .replyRequired,
                summary: "Codex is waiting for direction.",
                details: ["Two migration paths are viable."],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-43",
                kind: .reply,
                prompt: "Should I preserve the API?",
                options: []
            ),
            suggestions: [
                .init(
                    id: "guide-foreman",
                    kind: .foremanPrompt,
                    title: "Guide Foreman",
                    payload: .foremanPrompt("Ask Foreman which migration path to take."),
                    rationale: "The worker needs a planner-level decision.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-43"
                ),
            ]
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex is waiting for direction.",
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
            timestamp: Date(),
            fingerprint: snapshot.attentionFingerprint
        )

        let attention = try #require(
            PendingAgentAttentionFactory.make(from: event, understanding: understanding)
        )

        #expect(attention.title == "Needs direction")
        #expect(attention.description == "Should I preserve the API?")
        #expect(attention.detail == "Two migration paths are viable.")
        #expect(attention.actions.isEmpty)
    }

    @Test
    func authoritativeChoiceForemanPromptSuggestionFallsBackToWorkerOptions() throws {
        let snapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "term-1",
            workerSessionID: "codex-session-44",
            revision: 44,
            observedAt: Date(timeIntervalSince1970: 1_748_222_225),
            ttlMilliseconds: 15_000,
            workerGoal: "choose the migration path",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .running,
                attention: .choiceRequired,
                summary: "Codex needs a direction choice.",
                details: [],
                runtimeFlags: []
            ),
            request: .init(
                id: "req-44",
                kind: .choice,
                prompt: "Which migration path should I take?",
                options: [
                    .init(id: "keep-api", label: "Keep the API", recommended: true),
                    .init(id: "break-api", label: "Break the API", recommended: false),
                ]
            ),
            suggestions: [
                .init(
                    id: "guide-foreman",
                    kind: .foremanPrompt,
                    title: "Guide Foreman",
                    payload: .foremanPrompt("Ask Foreman which migration path to take."),
                    rationale: "The worker wants planner-level direction.",
                    recommended: true,
                    execution: .manualOnly,
                    requestID: "req-44"
                ),
            ]
        )
        let understanding = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Codex needs a direction choice.",
            lastMeaningfulEvent: "Which migration path should I take?",
            importantDetails: [],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingChoice,
            workerSnapshot: snapshot
        )
        let event = AgentNeedsAttentionEvent(
            terminalID: "term-1",
            agentIdentity: .codex,
            interactionState: .waitingChoice,
            deltaText: "Which migration path should I take?",
            timestamp: Date(),
            fingerprint: snapshot.attentionFingerprint
        )

        let attention = try #require(
            PendingAgentAttentionFactory.make(from: event, understanding: understanding)
        )

        #expect(attention.title == "Choose an option")
        #expect(attention.actions == [
            PendingAgentAction(id: "choice_1", title: "Keep the API", payload: "keep-api", style: .primary),
            PendingAgentAction(id: "choice_2", title: "Break the API", payload: "break-api", style: .secondary),
        ])
    }

    private func paritySignature(_ attention: PendingAgentAttention) -> AttentionParitySignature {
        AttentionParitySignature(
            agentIdentity: attention.agentIdentity,
            interactionState: attention.interactionState,
            title: attention.title,
            description: attention.description,
            detail: attention.detail,
            actions: attention.actions
        )
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
        let options = [
            "Continue",
            "Explain",
            "Stop",
            "Open docs",
            "Archive",
        ]

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
}
