import Foundation
import Testing
@testable import Ghostty

struct TerminalUnderstandingProjectorTests {
    private let projector = TerminalUnderstandingProjector()

    private struct ProjectionParitySignature: Equatable {
        let state: TerminalUnderstandingState
        let agentIdentity: AgentIdentity
        let interactionState: AgentInteractionState
        let shortExplanation: String
        let importantDetails: [String]
        let suggestedNextActions: [TerminalSuggestedAction]
        let agentInteractionContext: AgentInteractionContext
    }

    @Test
    func approvalProjectionUsesApprovalExplanationAndSuggestions() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "kimi-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Shell is requesting approval to run command",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )
        let classification = AgentMeaningDetector.Detection(
            identity: .kimi,
            interactionState: .waitingApproval,
            runtimeState: .blocked,
            supportLevel: .firstClass,
            evidence: [.init(source: .screenHeuristic, detail: "approval UI", confidence: 1.0)],
            context: .waitingApproval(description: "Kimi wants to edit auth.ts.", tool: "WriteFile")
        )

        let understanding = projector.project(
            current: snapshot,
            classification: classification,
            lastOutcome: Optional<TerminalOutcomeReport>.none,
            lastEvent: "Kimi wants to edit auth.ts."
        )

        #expect(understanding.state == TerminalUnderstandingState.waiting)
        #expect(understanding.shortExplanation == "Kimi is waiting for approval to continue.")
        #expect(understanding.suggestedNextActions.map { $0.title } == [
            "Review the approval request",
            "Let Foreman explain the requested action",
        ])
        #expect(understanding.agentInteractionContext == AgentInteractionContext.waitingApproval(description: "Kimi wants to edit auth.ts.", tool: "WriteFile"))
    }

    @Test
    func authoritativeWorkerSnapshotOverridesHeuristicProjection() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "codex-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "zsh: command not found: hfind",
            recentScrollbackLines: ["zsh: command not found: hfind"],
            lastInputPreview: "hfind . -print",
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let workerSnapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "codex-term",
            workerSessionID: "codex-session-41",
            revision: 41,
            observedAt: Date(timeIntervalSince1970: 1_748_222_222),
            ttlMilliseconds: 15_000,
            workerGoal: "stabilize the API",
            agent: .init(identity: .codex),
            state: .init(
                lifecycle: .blocked,
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

        let understanding = projector.project(
            current: snapshot,
            classification: Optional<AgentMeaningDetector.Detection>.none,
            lastOutcome: Optional<TerminalOutcomeReport>.none,
            lastEvent: "zsh: command not found: hfind",
            workerSnapshot: workerSnapshot
        )

        #expect(understanding.state == .waiting)
        #expect(understanding.agentIdentity == .codex)
        #expect(understanding.agentInteractionState == .waitingText)
        #expect(understanding.shortExplanation == "Codex is waiting for a reply.")
        #expect(understanding.suggestedNextActions.map(\.title) == ["Preserve the API"])
        #expect(understanding.workerSnapshot == workerSnapshot)
        #expect(
            understanding.agentInteractionContext ==
            .waitingText(
                question: "Should I preserve the API?",
                requestID: "req-41",
                sessionID: "codex-session-41",
                revision: 41,
                isPlanning: false
            )
        )
    }

    @Test
    func authoritativeWorkerLifecycleMapsToInteractionStateWhenAttentionIsNone() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "kimi-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Kimi is applying the selected API direction.",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let runningSnapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "kimi-term",
            workerSessionID: "kimi-session-12",
            revision: 12,
            observedAt: Date(timeIntervalSince1970: 1_748_333_334),
            ttlMilliseconds: 15_000,
            workerGoal: "compare API directions",
            agent: .init(identity: .kimi),
            state: .init(
                lifecycle: .running,
                attention: .none,
                summary: "Kimi is applying the selected API direction.",
                details: ["The worker is continuing with the approved choice."],
                runtimeFlags: []
            ),
            request: nil,
            suggestions: []
        )
        let completedSnapshot = TerminalWorkerSnapshot(
            schemaVersion: 1,
            terminalID: "kimi-term",
            workerSessionID: "kimi-session-13",
            revision: 13,
            observedAt: Date(timeIntervalSince1970: 1_748_333_335),
            ttlMilliseconds: 15_000,
            workerGoal: "compare API directions",
            agent: .init(identity: .kimi),
            state: .init(
                lifecycle: .completed,
                attention: .none,
                summary: "Kimi completed the API comparison.",
                details: ["A recommended direction is ready."],
                runtimeFlags: []
            ),
            request: nil,
            suggestions: []
        )

        let runningUnderstanding = projector.project(
            current: snapshot,
            classification: Optional<AgentMeaningDetector.Detection>.none,
            lastOutcome: Optional<TerminalOutcomeReport>.none,
            lastEvent: "Kimi is applying the selected API direction.",
            workerSnapshot: runningSnapshot
        )
        let completedUnderstanding = projector.project(
            current: snapshot,
            classification: Optional<AgentMeaningDetector.Detection>.none,
            lastOutcome: Optional<TerminalOutcomeReport>.none,
            lastEvent: "Kimi completed the API comparison.",
            workerSnapshot: completedSnapshot
        )

        #expect(runningUnderstanding.agentInteractionState == .running)
        #expect(runningUnderstanding.agentInteractionContext == .running(
            stepDescription: "Kimi is applying the selected API direction.",
            sessionID: "kimi-session-12",
            revision: 12
        ))
        #expect(completedUnderstanding.agentInteractionState == .completed)
        #expect(completedUnderstanding.agentInteractionContext == .completed(
            summary: "Kimi completed the API comparison.",
            sessionID: "kimi-session-13",
            revision: 13
        ))
    }

    @Test
    func codexWaitingTextProjectionKeepsManagedLaunchParity() {
        let question = "• Hello. What do you want to work on in ghostty?"
        let classification = AgentMeaningDetector.Detection(
            identity: .codex,
            interactionState: .waitingText,
            runtimeState: .blocked,
            supportLevel: .firstClass,
            evidence: [.init(source: .screenHeuristic, detail: "codex prompt", confidence: 1.0)],
            context: .waitingText(question: question)
        )
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "codex-existing",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: question,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-new-tab",
                windowID: "win-1",
                tabID: "tab-2",
                title: "nambouchara@host:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: question,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-managed",
                windowID: "win-1",
                tabID: "tab-3",
                title: "OpenAI Codex",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: question,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
        ]

        let signatures = snapshots.map {
            projectionParitySignature(
                projector.project(
                    current: $0,
                    classification: classification,
                    lastOutcome: Optional<TerminalOutcomeReport>.none,
                    lastEvent: question
                )
            )
        }

        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.shortExplanation == "Codex is waiting for your response: • Hello. What do you want to work on in ghostty?")
        #expect(signatures.first?.suggestedNextActions.map { $0.title } == ["Reply to the agent"])
    }

    @Test
    func failedCommandNotFoundProjectionBuildsRankedSuggestions() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "term-1",
            windowID: "win-1",
            tabID: "tab-1",
            title: "shell",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "hfind . -print\nzsh: command not found: hfind\nuser@host %",
            recentScrollbackLines: ["hfind . -print", "zsh: command not found: hfind"],
            lastInputPreview: "hfind . -print"
        )

        let understanding = projector.project(
            current: snapshot,
            classification: Optional<AgentMeaningDetector.Detection>.none,
            lastOutcome: Optional<TerminalOutcomeReport>.none,
            lastEvent: "zsh: command not found: hfind"
        )

        #expect(understanding.state == TerminalUnderstandingState.failed)
        #expect(understanding.suggestedNextActions.map { $0.title } == [
            "Run the likely intended find command",
            "Try fd if a faster file search was intended",
            "Confirm whether hfind was intentional",
        ])
        #expect(understanding.recommendedAction?.command == "find . -print")
    }

    @Test
    func waitingProjectionFiltersInputChromeOutOfImportantDetails() {
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "kimi-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            What would you like me to do here?
            ---------- input ----------
            agent (Kimi-k2.6) context: project
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let classification = AgentMeaningDetector.Detection(
            identity: .kimi,
            interactionState: .waitingText,
            runtimeState: .blocked,
            supportLevel: .firstClass,
            evidence: [.init(source: .screenHeuristic, detail: "kimi input", confidence: 1.0)],
            context: .waitingText(question: "What would you like me to do here?")
        )

        let understanding = projector.project(
            current: snapshot,
            classification: classification,
            lastOutcome: Optional<TerminalOutcomeReport>.none,
            lastEvent: "What would you like me to do here?"
        )

        #expect(understanding.state == TerminalUnderstandingState.waiting)
        #expect(understanding.importantDetails == ["What would you like me to do here?"])
    }

    @Test
    func waitingProjectionFallsBackToInteractionQuestionWhenScreenHasNoMeaningfulEvent() {
        let question = "What should I do here?"
        let snapshot = TerminalSnapshot.makePreview(
            terminalID: "kimi-term",
            windowID: "win-1",
            tabID: "tab-1",
            title: "Kimi Code",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: """
            ─ input ─────────────────────────────────────────────────────────

            agent (Kimi-k2.6 ●)  ~/speed2  ctrl-x: toggle mode | shift-tab: plan mode
            context: 5.4% (14.3k/262.1k)
            """,
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessName: "kimi",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let classification = AgentMeaningDetector.Detection(
            identity: .kimi,
            interactionState: .waitingText,
            runtimeState: .blocked,
            supportLevel: .firstClass,
            evidence: [.init(source: .wireSignal, detail: "question request", confidence: 1.0)],
            context: .waitingText(question: question)
        )

        let understanding = projector.project(
            current: snapshot,
            classification: classification,
            lastOutcome: Optional<TerminalOutcomeReport>.none,
            lastEvent: "No meaningful terminal event detected."
        )

        #expect(understanding.lastMeaningfulEvent == question)
        #expect(understanding.shortExplanation == "Kimi is waiting for your response: \(question)")
        #expect(understanding.suggestedNextActions.first?.reason == question)
    }

    private func projectionParitySignature(_ understanding: TerminalUnderstanding) -> ProjectionParitySignature {
        ProjectionParitySignature(
            state: understanding.state,
            agentIdentity: understanding.agentIdentity,
            interactionState: understanding.agentInteractionState,
            shortExplanation: understanding.shortExplanation,
            importantDetails: understanding.importantDetails,
            suggestedNextActions: understanding.suggestedNextActions,
            agentInteractionContext: understanding.agentInteractionContext
        )
    }
}
