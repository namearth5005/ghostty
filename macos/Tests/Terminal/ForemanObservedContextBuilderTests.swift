import Foundation
import Testing
@testable import Ghostty

struct ForemanObservedContextBuilderTests {
    private let builder = ForemanObservedContextBuilder()

    private struct ParitySignature: Equatable {
        let state: TerminalUnderstandingState
        let agentIdentity: AgentIdentity
        let interactionState: AgentInteractionState
        let supportLevel: AgentSupportLevel
        let lastMeaningfulEvent: String
        let shortExplanation: String
        let importantDetails: [String]
        let suggestedNextActions: [TerminalSuggestedAction]
        let interactionContext: AgentInteractionContext
    }

    @Test
    func managedManualAndNewTabKimiWireQuestionsShareObservedContext() {
        let question = "What should I do here?"
        let snapshots = [
            kimiInputSnapshot(
                terminalID: "kimi-existing",
                title: "shell",
                isFocused: true
            ),
            kimiInputSnapshot(
                terminalID: "kimi-new-tab",
                title: "nambouchara@Nams-MacBook-Pro:~"
            ),
            kimiInputSnapshot(
                terminalID: "kimi-managed",
                title: "Kimi Code"
            ),
        ]
        let wireRecordsByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.terminalID, [kimiQuestionRecord(question: question)]) }
        )

        let result = builder.build(
            snapshots: snapshots,
            kimiWireRecordsByTerminalID: wireRecordsByTerminalID
        )
        let understandings = result.context.understandings
        let signatures = understandings.map(signature)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.state == .waiting)
        #expect(signatures.first?.agentIdentity == .kimi)
        #expect(signatures.first?.interactionState == .waitingText)
        #expect(signatures.first?.lastMeaningfulEvent == question)
        #expect(signatures.first?.shortExplanation == "Kimi is waiting for your response: \(question)")
        #expect(signatures.first?.interactionContext == .waitingText(question: question))
        #expect(result.understandingsByTerminalID["kimi-managed"]?.agentInteractionContext == .waitingText(question: question))
    }

    @Test
    func managedManualAndNewTabKimiTurnEndQuestionsShareObservedContext() {
        let question = "What should I do here?"
        let snapshots = [
            kimiInputSnapshot(
                terminalID: "kimi-turn-end-existing",
                title: "shell",
                isFocused: true
            ),
            kimiInputSnapshot(
                terminalID: "kimi-turn-end-new-tab",
                title: "nambouchara@Nams-MacBook-Pro:~"
            ),
            kimiInputSnapshot(
                terminalID: "kimi-turn-end-managed",
                title: "Kimi Code"
            ),
        ]
        let wireRecords = [
            kimiContentPartRecord(text: "I looked through the repository.\n\(question)"),
            KimiWireRecord(
                timestamp: 2,
                message: KimiWireMessage(
                    type: "TurnEnd",
                    payload: KimiWirePayload()
                )
            ),
        ]
        let wireRecordsByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.terminalID, wireRecords) }
        )

        let result = builder.build(
            snapshots: snapshots,
            kimiWireRecordsByTerminalID: wireRecordsByTerminalID
        )
        let signatures = result.context.understandings.map(signature)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.agentIdentity == .kimi)
        #expect(signatures.first?.interactionState == .waitingText)
        #expect(signatures.first?.lastMeaningfulEvent == question)
        #expect(signatures.first?.interactionContext == .waitingText(question: question))
    }

    @Test
    func codexPromptParitySurvivesObservedContextBuild() {
        let visibleText = """
        • Hello. What do you want to work on in ghostty?

        ›
        """
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "codex-existing",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: visibleText,
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
                title: "nambouchara@Nams-MacBook-Pro:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: visibleText,
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
                visibleText: visibleText,
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: "codex",
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
        ]

        let result = builder.build(snapshots: snapshots)
        let signatures = result.context.understandings.map(signature)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.agentIdentity == .codex)
        #expect(signatures.first?.interactionState == .waitingText)
        #expect(signatures.first?.interactionContext == .waitingText(question: "• Hello. What do you want to work on in ghostty?"))
    }

    @Test
    func managedManualAndNewTabClaudeApprovalStatusesShareObservedContext() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "claude-existing",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "Claude is attached to the workspace.",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: 101,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "claude-new-tab",
                windowID: "win-1",
                tabID: "tab-2",
                title: "nambouchara@Nams-MacBook-Pro:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "Claude is attached to the workspace.",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: 202,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "claude-managed",
                windowID: "win-1",
                tabID: "tab-3",
                title: "Claude Code",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "Claude is attached to the workspace.",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessID: 303,
                foregroundProcessName: "claude",
                cursorIsAtPrompt: false,
                usingAlternateScreen: true
            ),
        ]
        let sessionStatesByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.enumerated().map { index, snapshot in
                (
                    snapshot.terminalID,
                    [
                        ClaudeSessionState(
                            pid: snapshot.runtime.foregroundProcessID ?? 0,
                            sessionId: "session-\(index)",
                            cwd: "/tmp/project",
                            status: "waiting_for_approval",
                            updatedAt: 1,
                            startedAt: 1,
                            version: "1",
                            kind: "session"
                        ),
                    ]
                )
            }
        )

        let result = builder.build(
            snapshots: snapshots,
            claudeWireRecordsByTerminalID: sessionStatesByTerminalID
        )
        let signatures = result.context.understandings.map(signature)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.agentIdentity == .claudeCode)
        #expect(signatures.first?.interactionState == .waitingApproval)
        let expected: AgentInteractionContext = .waitingApproval(description: "", tool: nil)
        #expect(signatures.first?.interactionContext == expected)
    }

    private func signature(_ understanding: TerminalUnderstanding) -> ParitySignature {
        ParitySignature(
            state: understanding.state,
            agentIdentity: understanding.agentIdentity,
            interactionState: understanding.agentInteractionState,
            supportLevel: understanding.supportLevel,
            lastMeaningfulEvent: understanding.lastMeaningfulEvent,
            shortExplanation: understanding.shortExplanation,
            importantDetails: understanding.importantDetails,
            suggestedNextActions: understanding.suggestedNextActions,
            interactionContext: understanding.agentInteractionContext
        )
    }

    private func kimiInputSnapshot(
        terminalID: String,
        title: String,
        isFocused: Bool = false
    ) -> TerminalSnapshot {
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-1",
            title: title,
            cwd: "/Users/nambouchara/speed2",
            isFocused: isFocused,
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
    }

    private func kimiQuestionRecord(question: String) -> KimiWireRecord {
        KimiWireRecord(
            timestamp: 1,
            message: KimiWireMessage(
                type: "QuestionRequest",
                payload: KimiWirePayload(
                    questions: [
                        QuestionItem(
                            question: question,
                            header: nil,
                            options: nil,
                            multi_select: nil
                        ),
                    ]
                )
            )
        )
    }

    private func kimiContentPartRecord(text: String) -> KimiWireRecord {
        KimiWireRecord(
            timestamp: 1,
            message: KimiWireMessage(
                type: "ContentPart",
                payload: KimiWirePayload(
                    text: text
                )
            )
        )
    }
}
