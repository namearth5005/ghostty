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
    func managedManualAndNewTabFreshSuccessOutcomesShareObservedContext() {
        let snapshots = [
            outcomeSummarySnapshot(
                terminalID: "success-existing",
                title: "shell",
                isFocused: true
            ),
            outcomeSummarySnapshot(
                terminalID: "success-new-tab",
                title: "nambouchara@Nams-MacBook-Pro:~"
            ),
            outcomeSummarySnapshot(
                terminalID: "success-managed",
                title: "OpenAI Codex"
            ),
        ]
        let outcomesByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map {
                (
                    $0.terminalID,
                    TerminalOutcomeReport(
                        terminalID: $0.terminalID,
                        sentCommand: "npm test",
                        outcome: .success,
                        detectedAt: .now,
                        summary: "Tests finished successfully."
                    )
                )
            }
        )

        let result = builder.build(
            snapshots: snapshots,
            lastOutcomesByTerminalID: outcomesByTerminalID
        )
        let signatures = result.context.understandings.map(signature)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.state == .succeeded)
        #expect(signatures.first?.lastMeaningfulEvent == "Tests finished successfully.")
        #expect(signatures.first?.shortExplanation.contains("Tests finished successfully.") == true)
    }

    @Test
    func managedManualAndNewTabGenericCodexWireStateShareRuntimeEntriesThroughBuilder() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-existing",
                windowID: "w1",
                tabID: "t1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-new-tab",
                windowID: "w1",
                tabID: "t2",
                title: "nambouchara@host:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-managed",
                windowID: "w1",
                tabID: "t3",
                title: "Codex",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
        ]
        let wireRecord = try! JSONDecoder().decode(
            CodexWireRecord.self,
            from: Data("""
            {
              "timestamp": "2026-05-23T00:00:00Z",
              "type": "event_msg",
              "payload": {
                "type": "task_complete",
                "turn_id": "turn-1",
                "completed_at": 1714828810,
                "duration_ms": 9000
              }
            }
            """.utf8)
        )
        let codexWireRecordsByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.terminalID, [wireRecord]) }
        )

        let result = builder.build(
            snapshots: snapshots,
            codexWireRecordsByTerminalID: codexWireRecordsByTerminalID
        )
        let entries = snapshots.map { try! #require(result.runtimeEntriesByTerminalID[$0.terminalID]) }

        #expect(entries.dropFirst().allSatisfy { $0.detection == entries.first?.detection })
        #expect(entries.dropFirst().allSatisfy { $0.monitorTarget == entries.first?.monitorTarget })
        #expect(entries.first?.detection?.identity == .codex)
        #expect(entries.first?.detection?.state == .blocked)
        #expect(entries.first?.monitorTarget == .codex(workingDirectory: "/tmp/project"))
    }

    @Test
    func builderCarriesRestartFlagsFromPreviousSnapshots() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "codex-turn",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "OpenAI Codex\nWhat should I work on next?\n›",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 777,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: true,
            usingAlternateScreen: true
        )
        let current = TerminalSnapshot.makePreview(
            terminalID: "codex-turn",
            windowID: "w1",
            tabID: "t1",
            title: "OpenAI Codex",
            cwd: "/tmp/project",
            isFocused: true,
            visibleText: "Working through the request...\nAnalyzing files",
            recentScrollbackLines: [],
            lastInputPreview: nil,
            foregroundProcessID: 777,
            foregroundProcessName: "codex",
            cursorIsAtPrompt: false,
            usingAlternateScreen: true
        )

        let result = builder.build(
            snapshots: [current],
            previousSnapshotsByTerminalID: [current.terminalID: previous]
        )

        #expect(result.runtimeEntriesByTerminalID[current.terminalID]?.shouldRestartMonitor == true)
    }

    @Test
    func managedManualAndNewTabGenericClaudeIdleStateShareRuntimeEntriesThroughBuilder() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-existing",
                windowID: "w1",
                tabID: "t1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-new-tab",
                windowID: "w1",
                tabID: "t2",
                title: "nambouchara@host:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-managed",
                windowID: "w1",
                tabID: "t3",
                title: "Claude",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
        ]
        let claudeWireRecordsByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map {
                (
                    $0.terminalID,
                    [
                        ClaudeSessionState(
                            pid: 12345,
                            sessionId: "session-\($0.terminalID)",
                            cwd: "/tmp/project",
                            status: "idle",
                            updatedAt: 1714828801000,
                            startedAt: 1714828800000,
                            version: "2.1.128",
                            kind: "interactive"
                        ),
                    ]
                )
            }
        )

        let result = builder.build(
            snapshots: snapshots,
            claudeWireRecordsByTerminalID: claudeWireRecordsByTerminalID
        )
        let entries = snapshots.map { try! #require(result.runtimeEntriesByTerminalID[$0.terminalID]) }

        #expect(entries.dropFirst().allSatisfy { $0.detection == entries.first?.detection })
        #expect(entries.dropFirst().allSatisfy { $0.monitorTarget == entries.first?.monitorTarget })
        #expect(entries.first?.detection?.identity == .claudeCode)
        #expect(entries.first?.detection?.state == .blocked)
        #expect(entries.first?.monitorTarget == .claudeWorkingDirectory("/tmp/project"))
    }

    @Test
    func managedManualAndNewTabCodexWireCompletionsShareObservedContextWhenSurfaceIsGeneric() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-existing",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-new-tab",
                windowID: "win-1",
                tabID: "tab-2",
                title: "nambouchara@Nams-MacBook-Pro:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "codex-wire-managed",
                windowID: "win-1",
                tabID: "tab-3",
                title: "Codex",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "codex",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
        ]
        let codexWireRecordsByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map {
                (
                    $0.terminalID,
                    [
                        CodexWireRecord(
                            timestamp: "2026-05-04T12:00:10Z",
                            type: "event_msg",
                            payload: CodexWirePayload(
                                id: nil,
                                cwd: "/tmp/project",
                                originator: nil,
                                cliVersion: nil,
                                type: "task_complete",
                                turnId: "turn-1",
                                startedAt: nil,
                                completedAt: 1714828810,
                                durationMs: 9000,
                                reason: nil,
                                lastAgentMessage: nil,
                                callId: nil,
                                processId: nil,
                                command: nil,
                                status: nil,
                                message: nil,
                                phase: nil
                            ),
                        ),
                    ]
                )
            }
        )

        let result = builder.build(
            snapshots: snapshots,
            codexWireRecordsByTerminalID: codexWireRecordsByTerminalID
        )
        let signatures = result.context.understandings.map(signature)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.agentIdentity == .codex)
        #expect(signatures.first?.interactionState == .waitingText)
        #expect(signatures.first?.interactionContext == .waitingText(question: nil))
    }

    @Test
    func managedManualAndNewTabClaudeIdleSessionsShareObservedContextWhenSurfaceIsGeneric() {
        let snapshots = [
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-existing",
                windowID: "win-1",
                tabID: "tab-1",
                title: "shell",
                cwd: "/tmp/project",
                isFocused: true,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-new-tab",
                windowID: "win-1",
                tabID: "tab-2",
                title: "nambouchara@Nams-MacBook-Pro:~",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
            TerminalSnapshot.makePreview(
                terminalID: "claude-wire-managed",
                windowID: "win-1",
                tabID: "tab-3",
                title: "Claude",
                cwd: "/tmp/project",
                isFocused: false,
                visibleText: "claude",
                recentScrollbackLines: [],
                lastInputPreview: nil,
                foregroundProcessName: nil,
                cursorIsAtPrompt: true,
                usingAlternateScreen: true
            ),
        ]
        let claudeWireRecordsByTerminalID = Dictionary(
            uniqueKeysWithValues: snapshots.map {
                (
                    $0.terminalID,
                    [
                        ClaudeSessionState(
                            pid: 12345,
                            sessionId: "session-\($0.terminalID)",
                            cwd: "/tmp/project",
                            status: "idle",
                            updatedAt: 1714828801000,
                            startedAt: 1714828800000,
                            version: "2.1.128",
                            kind: "interactive"
                        ),
                    ]
                )
            }
        )

        let result = builder.build(
            snapshots: snapshots,
            claudeWireRecordsByTerminalID: claudeWireRecordsByTerminalID
        )
        let signatures = result.context.understandings.map(signature)

        #expect(signatures.count == 3)
        #expect(signatures.dropFirst().allSatisfy { $0 == signatures.first })
        #expect(signatures.first?.agentIdentity == .claudeCode)
        #expect(signatures.first?.interactionState == .waitingText)
        #expect(signatures.first?.interactionContext == .waitingText(question: nil))
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

    private func outcomeSummarySnapshot(
        terminalID: String,
        title: String,
        isFocused: Bool = false
    ) -> TerminalSnapshot {
        TerminalSnapshot.makePreview(
            terminalID: terminalID,
            windowID: "win-1",
            tabID: "tab-1",
            title: title,
            cwd: "/tmp/project",
            isFocused: isFocused,
            visibleText: "npm test\nuser@host %",
            recentScrollbackLines: [
                "npm test",
                "user@host %",
            ],
            lastInputPreview: "npm test",
            cursorIsAtPrompt: true,
            usingAlternateScreen: false
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
