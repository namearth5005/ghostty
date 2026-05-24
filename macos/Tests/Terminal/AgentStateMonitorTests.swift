import Foundation
import Testing
@testable import Ghostty

struct AgentStateMonitorTests {

    @Test
    func urgentStatesFireOnFirstDetection() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        // waitingApproval is URGENT → should fire on first detection
        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for approval.",
                lastMeaningfulEvent: "Allow edit to auth.ts? [y/n]",
                importantDetails: ["Allow edit to auth.ts? [y/n]"],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingApproval
            )
        ])
        #expect(capturedEvents.count == 1)
        #expect(capturedEvents.first?.interactionState == .waitingApproval)
        #expect(capturedEvents.first?.fingerprint == "term-1|kimi|waiting_approval|Allow edit to auth.ts? [y/n]")

        // Same waitingApproval fingerprint → unresolved fingerprint blocks re-fire
        monitor.observe(understandings: [
            makeUnderstanding(
                terminalID: "term-1",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to auth.ts? [y/n]"]
            )
        ])
        #expect(capturedEvents.count == 1)
    }

    @Test
    func waitingTextWelcomeScreenDoesNotFireOnFirstDetection() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        // Kimi welcome/input screen is not a user-facing request yet.
        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "Welcome to Kimi Code CLI!",
                importantDetails: [
                    "Welcome to Kimi Code CLI!",
                    "agent (Kimi-k2.6) ~/speed2 context: 0.0%",
                ],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText
            )
        ])
        #expect(capturedEvents.isEmpty)

        // Still waitingText → still no fire
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .waiting, interactionState: .waitingText)
        ])
        #expect(capturedEvents.isEmpty)
    }

    @Test
    func waitingTextBecomingMeaningfulAfterWelcomeFiresEvenIfRunningWasMissed() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "Welcome to Kimi Code CLI!",
                importantDetails: [
                    "Welcome to Kimi Code CLI!",
                    "agent (Kimi-k2.6) ~/speed2 context: 0.0%",
                ],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText
            )
        ])
        #expect(capturedEvents.isEmpty)

        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "What would you like me to do here?",
                importantDetails: ["What would you like me to do here?"],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: "What would you like me to do here?")
            )
        ])

        #expect(capturedEvents.count == 1)
        #expect(capturedEvents.first?.deltaText == "What would you like me to do here?")
    }

    @Test
    func waitingTextWithMeaningfulPromptFiresOnFirstDetection() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response: What would you like me to do here?",
                lastMeaningfulEvent: "What would you like me to do here?",
                importantDetails: [
                    "I'm now in the mend directory.",
                    "What would you like me to do here?",
                ],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText
            )
        ])

        #expect(capturedEvents.count == 1)
        #expect(capturedEvents.first?.terminalID == "term-1")
        #expect(capturedEvents.first?.interactionState == .waitingText)
        #expect(capturedEvents.first?.fingerprint == "term-1|kimi|waiting_text|I'm now in the mend directory. What would you like me to do here?")
    }

    @Test
    func waitingTextWithQuestionOnlyInInteractionContextFiresOnFirstDetection() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "context: 5.4% (14.3k/262.1k)",
                importantDetails: [
                    "agent (Kimi-k2.6) ~/speed2",
                    "context: 5.4% (14.3k/262.1k)",
                ],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: "What would you like to do here?")
            )
        ])

        #expect(capturedEvents.count == 1)
        #expect(capturedEvents.first?.deltaText == "What would you like to do here?")
        #expect(capturedEvents.first?.fingerprint == "term-1|kimi|waiting_text|What would you like to do here?")
    }

    @Test
    func waitingTextDoesNotRefireWithChangedTextWhileStillPending() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "What should I do next?",
                importantDetails: ["What should I do next?"],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: "What should I do next?")
            )
        ])
        #expect(capturedEvents.count == 1)

        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "done",
                importantDetails: ["done"],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: "done")
            )
        ])

        #expect(capturedEvents.count == 1)
    }

    @Test
    func resolvedWaitingTextDoesNotRefireUntilAgentLeavesAttentionState() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let waiting = TerminalUnderstanding.preview(
            terminalID: "term-1",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "What should I do next?",
            importantDetails: ["What should I do next?"],
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText,
            agentInteractionContext: .waitingText(question: "What should I do next?")
        )

        monitor.observe(understandings: [waiting])
        #expect(capturedEvents.count == 1)

        monitor.resolve(terminalID: "term-1", fingerprint: capturedEvents[0].fingerprint)
        monitor.observe(understandings: [waiting])
        #expect(capturedEvents.count == 1)

        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .running, interactionState: .running)
        ])
        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "What should I test now?",
                importantDetails: ["What should I test now?"],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: "What should I test now?")
            )
        ])

        #expect(capturedEvents.count == 2)
    }

    @Test
    func firesEventWhenRunningTransitionsToWaitingApproval() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        // First: running
        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .running,
                shortExplanation: "Kimi is working.",
                lastMeaningfulEvent: "Thinking...",
                importantDetails: ["Thinking..."],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .running
            )
        ])
        #expect(capturedEvents.isEmpty)

        // Then: waitingApproval
        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Kimi is waiting for approval.",
                lastMeaningfulEvent: "Allow edit to auth.ts? [y/n]",
                importantDetails: ["Allow edit to auth.ts? [y/n]"],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingApproval
            )
        ])
        #expect(capturedEvents.count == 1)
        #expect(capturedEvents.first?.terminalID == "term-1")
        #expect(capturedEvents.first?.agentIdentity == .kimi)
        #expect(capturedEvents.first?.interactionState == .waitingApproval)
    }

    @Test
    func runningToRunningDoesNotEmitEvent() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .running, interactionState: .running)
        ])
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .running, interactionState: .running)
        ])

        #expect(capturedEvents.isEmpty)
    }

    @Test
    func ignoresShellTerminals() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        // Shell terminal at prompt — agentIdentity is .none
        monitor.observe(understandings: [
            TerminalUnderstanding.preview(
                terminalID: "term-1",
                state: .waiting,
                shortExplanation: "Terminal is idle.",
                lastMeaningfulEvent: "$ ",
                importantDetails: ["$ "],
                suggestedNextActions: [],
                agentIdentity: .none,
                agentInteractionState: .unknown
            )
        ])
        #expect(capturedEvents.isEmpty)
    }

    @Test
    func unresolvedFingerprintPreventsDuplicateEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        // running → waitingApproval
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .running, interactionState: .running)
        ])
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .waiting, interactionState: .waitingApproval)
        ])
        #expect(capturedEvents.count == 1)

        // Same state and fingerprint again — unresolved fingerprint should prevent re-fire
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .waiting, interactionState: .waitingApproval)
        ])
        #expect(capturedEvents.count == 1)
    }

    @Test
    func unresolvedFingerprintClearsWhenAgentLeavesAttentionState() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        // running → waitingApproval
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .running, interactionState: .running)
        ])
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .waiting, interactionState: .waitingApproval)
        ])
        #expect(capturedEvents.count == 1)

        // Agent goes back to running, which means the original prompt is no longer pending.
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .running, interactionState: .running)
        ])
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .waiting, interactionState: .waitingApproval)
        ])
        #expect(capturedEvents.count == 2)
    }

    @Test
    func firesForClaudeCodeAndCodex() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        // Claude Code: running → waitingChoice
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .running, interactionState: .running, identity: .claudeCode)
        ])
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-1", state: .waiting, interactionState: .waitingChoice, identity: .claudeCode)
        ])

        // Codex: running → waitingText
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-2", state: .running, interactionState: .running, identity: .codex)
        ])
        monitor.observe(understandings: [
            makeUnderstanding(terminalID: "term-2", state: .waiting, interactionState: .waitingText, identity: .codex)
        ])

        #expect(capturedEvents.count == 2)
        #expect(capturedEvents.contains { $0.agentIdentity == .claudeCode })
        #expect(capturedEvents.contains { $0.agentIdentity == .codex })
    }

    @Test
    func unchangedWaitingApprovalFingerprintFiresOnlyOnceUntilResolved() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            makeUnderstanding(
                terminalID: "term-1",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to auth.ts? [y/n]"]
            )
        ])
        monitor.observe(understandings: [
            makeUnderstanding(
                terminalID: "term-1",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to auth.ts? [y/n]"]
            )
        ])

        #expect(capturedEvents.count == 1)
    }

    @Test
    func changedApprovalFingerprintFiresAgain() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            makeUnderstanding(
                terminalID: "term-1",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to auth.ts? [y/n]"]
            )
        ])
        monitor.observe(understandings: [
            makeUnderstanding(
                terminalID: "term-1",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to profile.ts? [y/n]"]
            )
        ])

        #expect(capturedEvents.count == 2)
        #expect(capturedEvents[0].fingerprint != capturedEvents[1].fingerprint)
    }

    @Test
    func sameApprovalFingerprintFiresIndependentlyForDifferentTerminals() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            makeUnderstanding(
                terminalID: "term-1",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to auth.ts? [y/n]"]
            ),
            makeUnderstanding(
                terminalID: "term-2",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to auth.ts? [y/n]"]
            ),
        ])

        #expect(capturedEvents.count == 2)
        #expect(capturedEvents[0].terminalID == "term-1")
        #expect(capturedEvents[1].terminalID == "term-2")
        #expect(capturedEvents[0].fingerprint != capturedEvents[1].fingerprint)
    }

    @Test
    func resolvedFingerprintCanFireAgain() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        monitor.observe(understandings: [
            makeUnderstanding(
                terminalID: "term-1",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to auth.ts? [y/n]"]
            )
        ])

        let fingerprint = capturedEvents[0].fingerprint
        monitor.resolve(terminalID: "term-1", fingerprint: fingerprint)

        monitor.observe(understandings: [
            makeUnderstanding(
                terminalID: "term-1",
                state: .waiting,
                interactionState: .waitingApproval,
                details: ["Allow edit to auth.ts? [y/n]"]
            )
        ])

        #expect(capturedEvents.count == 2)
        #expect(capturedEvents[1].fingerprint == fingerprint)
    }

    @Test
    func managedManualAndNewTabKimiWelcomeScreensDoNotFireAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let manual = TerminalUnderstanding.preview(
            terminalID: "kimi-manual",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "Welcome to Kimi Code CLI!",
            importantDetails: [
                "Welcome to Kimi Code CLI!",
                "Directory: /tmp/kimi",
            ],
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText
        )
        let newTab = TerminalUnderstanding.preview(
            terminalID: "kimi-new-tab",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "Welcome to Kimi Code CLI!",
            importantDetails: [
                "Welcome to Kimi Code CLI!",
                "Directory: /tmp/kimi",
            ],
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText
        )
        let managed = TerminalUnderstanding.preview(
            terminalID: "kimi-managed",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "Welcome to Kimi Code CLI!",
            importantDetails: [
                "Welcome to Kimi Code CLI!",
                "Directory: /tmp/kimi",
            ],
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText
        )

        monitor.observe(understandings: [manual, newTab, managed])

        #expect(capturedEvents.isEmpty)
    }

    @Test
    func managedManualAndNewTabKimiInputRegionsDoNotFireAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let details: [String] = []
        let manual = TerminalUnderstanding.preview(
            terminalID: "kimi-input-manual",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "No meaningful terminal event detected.",
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText
        )
        let newTab = TerminalUnderstanding.preview(
            terminalID: "kimi-input-new-tab",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "No meaningful terminal event detected.",
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText
        )
        let managed = TerminalUnderstanding.preview(
            terminalID: "kimi-input-managed",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "No meaningful terminal event detected.",
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText
        )

        monitor.observe(understandings: [manual, newTab, managed])

        #expect(capturedEvents.isEmpty)
    }

    @Test
    func managedManualAndNewTabKimiContextOnlyQuestionsFireEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let question = "What should I do here?"
        let details = [
            "agent (Kimi-k2.6) ~/speed2",
            "context: 5.4% (14.3k/262.1k)",
        ]
        let manual = TerminalUnderstanding.preview(
            terminalID: "kimi-context-manual",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "context: 5.4% (14.3k/262.1k)",
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText,
            agentInteractionContext: .waitingText(question: question)
        )
        let newTab = TerminalUnderstanding.preview(
            terminalID: "kimi-context-new-tab",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "context: 5.4% (14.3k/262.1k)",
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText,
            agentInteractionContext: .waitingText(question: question)
        )
        let managed = TerminalUnderstanding.preview(
            terminalID: "kimi-context-managed",
            state: .waiting,
            shortExplanation: "Kimi is waiting for your response.",
            lastMeaningfulEvent: "context: 5.4% (14.3k/262.1k)",
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingText,
            agentInteractionContext: .waitingText(question: question)
        )

        monitor.observe(understandings: [manual, newTab, managed])

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .kimi })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingText })
        #expect(Set(capturedEvents.map(\.deltaText)) == [question])
    }

    @Test
    func managedManualAndNewTabKimiWelcomeToContextQuestionTransitionFiresEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let welcomeStates = [
            TerminalUnderstanding.preview(
                terminalID: "kimi-transition-manual",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "Welcome to Kimi Code CLI!",
                importantDetails: [
                    "Welcome to Kimi Code CLI!",
                    "Directory: /tmp/kimi",
                ],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText
            ),
            TerminalUnderstanding.preview(
                terminalID: "kimi-transition-new-tab",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "Welcome to Kimi Code CLI!",
                importantDetails: [
                    "Welcome to Kimi Code CLI!",
                    "Directory: /tmp/kimi",
                ],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText
            ),
            TerminalUnderstanding.preview(
                terminalID: "kimi-transition-managed",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "Welcome to Kimi Code CLI!",
                importantDetails: [
                    "Welcome to Kimi Code CLI!",
                    "Directory: /tmp/kimi",
                ],
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText
            ),
        ]
        monitor.observe(understandings: welcomeStates)
        #expect(capturedEvents.isEmpty)

        let question = "What should I do here?"
        let details = [
            "agent (Kimi-k2.6) ~/speed2",
            "context: 5.4% (14.3k/262.1k)",
        ]
        let actionableStates = [
            TerminalUnderstanding.preview(
                terminalID: "kimi-transition-manual",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "context: 5.4% (14.3k/262.1k)",
                importantDetails: details,
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: question)
            ),
            TerminalUnderstanding.preview(
                terminalID: "kimi-transition-new-tab",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "context: 5.4% (14.3k/262.1k)",
                importantDetails: details,
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: question)
            ),
            TerminalUnderstanding.preview(
                terminalID: "kimi-transition-managed",
                state: .waiting,
                shortExplanation: "Kimi is waiting for your response.",
                lastMeaningfulEvent: "context: 5.4% (14.3k/262.1k)",
                importantDetails: details,
                suggestedNextActions: [],
                agentIdentity: .kimi,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: question)
            ),
        ]
        monitor.observe(understandings: actionableStates)

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .kimi })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingText })
        #expect(Set(capturedEvents.map(\.deltaText)) == [question])
    }

    @Test
    func managedManualAndNewTabCodexQuestionPromptsFireEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let manual = TerminalUnderstanding.preview(
            terminalID: "codex-manual",
            state: .waiting,
            shortExplanation: "Codex is waiting for your response.",
            lastMeaningfulEvent: "What should I work on next?",
            importantDetails: ["What should I work on next?"],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            agentInteractionContext: .waitingText(question: "What should I work on next?")
        )
        let newTab = TerminalUnderstanding.preview(
            terminalID: "codex-new-tab",
            state: .waiting,
            shortExplanation: "Codex is waiting for your response.",
            lastMeaningfulEvent: "What should I work on next?",
            importantDetails: ["What should I work on next?"],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            agentInteractionContext: .waitingText(question: "What should I work on next?")
        )
        let managed = TerminalUnderstanding.preview(
            terminalID: "codex-managed",
            state: .waiting,
            shortExplanation: "Codex is waiting for your response.",
            lastMeaningfulEvent: "What should I work on next?",
            importantDetails: ["What should I work on next?"],
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingText,
            agentInteractionContext: .waitingText(question: "What should I work on next?")
        )

        monitor.observe(understandings: [manual, newTab, managed])

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .codex })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingText })
        #expect(Set(capturedEvents.map(\.deltaText)) == ["What should I work on next?"])
    }

    @Test
    func managedManualAndNewTabCodexRunningToReplyTransitionFiresEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let runningStates = [
            TerminalUnderstanding.preview(
                terminalID: "codex-transition-manual",
                state: .running,
                shortExplanation: "Codex is working.",
                lastMeaningfulEvent: "Working on the next step",
                importantDetails: ["Working on the next step"],
                suggestedNextActions: [],
                agentIdentity: .codex,
                agentInteractionState: .running,
                agentInteractionContext: .running(stepDescription: "Working on the next step")
            ),
            TerminalUnderstanding.preview(
                terminalID: "codex-transition-new-tab",
                state: .running,
                shortExplanation: "Codex is working.",
                lastMeaningfulEvent: "Working on the next step",
                importantDetails: ["Working on the next step"],
                suggestedNextActions: [],
                agentIdentity: .codex,
                agentInteractionState: .running,
                agentInteractionContext: .running(stepDescription: "Working on the next step")
            ),
            TerminalUnderstanding.preview(
                terminalID: "codex-transition-managed",
                state: .running,
                shortExplanation: "Codex is working.",
                lastMeaningfulEvent: "Working on the next step",
                importantDetails: ["Working on the next step"],
                suggestedNextActions: [],
                agentIdentity: .codex,
                agentInteractionState: .running,
                agentInteractionContext: .running(stepDescription: "Working on the next step")
            ),
        ]
        monitor.observe(understandings: runningStates)
        #expect(capturedEvents.isEmpty)

        let waitingStates = [
            TerminalUnderstanding.preview(
                terminalID: "codex-transition-manual",
                state: .waiting,
                shortExplanation: "Codex is waiting for your response.",
                lastMeaningfulEvent: "What should I work on next?",
                importantDetails: ["What should I work on next?"],
                suggestedNextActions: [],
                agentIdentity: .codex,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: "What should I work on next?")
            ),
            TerminalUnderstanding.preview(
                terminalID: "codex-transition-new-tab",
                state: .waiting,
                shortExplanation: "Codex is waiting for your response.",
                lastMeaningfulEvent: "What should I work on next?",
                importantDetails: ["What should I work on next?"],
                suggestedNextActions: [],
                agentIdentity: .codex,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: "What should I work on next?")
            ),
            TerminalUnderstanding.preview(
                terminalID: "codex-transition-managed",
                state: .waiting,
                shortExplanation: "Codex is waiting for your response.",
                lastMeaningfulEvent: "What should I work on next?",
                importantDetails: ["What should I work on next?"],
                suggestedNextActions: [],
                agentIdentity: .codex,
                agentInteractionState: .waitingText,
                agentInteractionContext: .waitingText(question: "What should I work on next?")
            ),
        ]
        monitor.observe(understandings: waitingStates)

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .codex })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingText })
        #expect(Set(capturedEvents.map(\.deltaText)) == ["What should I work on next?"])
    }

    @Test
    func managedManualAndNewTabKimiApprovalPromptsFireEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let prompt = "Allow edit to auth.ts? [y/n]"
        let details = [prompt]
        let manual = TerminalUnderstanding.preview(
            terminalID: "kimi-approval-manual",
            state: .waiting,
            shortExplanation: "Kimi is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Kimi wants to edit auth.ts.", tool: "WriteFile")
        )
        let newTab = TerminalUnderstanding.preview(
            terminalID: "kimi-approval-new-tab",
            state: .waiting,
            shortExplanation: "Kimi is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Kimi wants to edit auth.ts.", tool: "WriteFile")
        )
        let managed = TerminalUnderstanding.preview(
            terminalID: "kimi-approval-managed",
            state: .waiting,
            shortExplanation: "Kimi is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .kimi,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Kimi wants to edit auth.ts.", tool: "WriteFile")
        )

        monitor.observe(understandings: [manual, newTab, managed])

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .kimi })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingApproval })
        #expect(Set(capturedEvents.map(\.deltaText)) == [prompt])
    }

    @Test
    func managedManualAndNewTabCodexApprovalPromptsFireEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let prompt = "Run the suggested command? [y/n]"
        let details = [prompt]
        let manual = TerminalUnderstanding.preview(
            terminalID: "codex-approval-manual",
            state: .waiting,
            shortExplanation: "Codex is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Codex wants to run the suggested command.", tool: "Shell")
        )
        let newTab = TerminalUnderstanding.preview(
            terminalID: "codex-approval-new-tab",
            state: .waiting,
            shortExplanation: "Codex is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Codex wants to run the suggested command.", tool: "Shell")
        )
        let managed = TerminalUnderstanding.preview(
            terminalID: "codex-approval-managed",
            state: .waiting,
            shortExplanation: "Codex is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .codex,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Codex wants to run the suggested command.", tool: "Shell")
        )

        monitor.observe(understandings: [manual, newTab, managed])

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .codex })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingApproval })
        #expect(Set(capturedEvents.map(\.deltaText)) == [prompt])
    }

    @Test
    func managedManualAndNewTabClaudeApprovalPromptsFireEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let prompt = "Run the suggested command? [y/n]"
        let details = [prompt]
        let manual = TerminalUnderstanding.preview(
            terminalID: "claude-approval-manual",
            state: .waiting,
            shortExplanation: "Claude Code is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .claudeCode,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Claude wants to run the suggested command.", tool: "Shell")
        )
        let newTab = TerminalUnderstanding.preview(
            terminalID: "claude-approval-new-tab",
            state: .waiting,
            shortExplanation: "Claude Code is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .claudeCode,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Claude wants to run the suggested command.", tool: "Shell")
        )
        let managed = TerminalUnderstanding.preview(
            terminalID: "claude-approval-managed",
            state: .waiting,
            shortExplanation: "Claude Code is waiting for approval.",
            lastMeaningfulEvent: prompt,
            importantDetails: details,
            suggestedNextActions: [],
            agentIdentity: .claudeCode,
            agentInteractionState: .waitingApproval,
            agentInteractionContext: .waitingApproval(description: "Claude wants to run the suggested command.", tool: "Shell")
        )

        monitor.observe(understandings: [manual, newTab, managed])

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .claudeCode })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingApproval })
        #expect(Set(capturedEvents.map(\.deltaText)) == [prompt])
    }

    @Test
    func managedManualAndNewTabClaudeTrustPromptsFireEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let trustPrompt = "Do you trust the files in this folder?"
        let existingTab = TerminalUnderstanding.preview(
            terminalID: "claude-existing",
            state: .waiting,
            shortExplanation: "Claude Code is waiting for your selection.",
            lastMeaningfulEvent: trustPrompt,
            importantDetails: [trustPrompt],
            suggestedNextActions: [],
            agentIdentity: .claudeCode,
            agentInteractionState: .waitingChoice
        )
        let newTab = TerminalUnderstanding.preview(
            terminalID: "claude-new-tab",
            state: .waiting,
            shortExplanation: "Claude Code is waiting for your selection.",
            lastMeaningfulEvent: trustPrompt,
            importantDetails: [trustPrompt],
            suggestedNextActions: [],
            agentIdentity: .claudeCode,
            agentInteractionState: .waitingChoice
        )
        let managed = TerminalUnderstanding.preview(
            terminalID: "claude-managed",
            state: .waiting,
            shortExplanation: "Claude Code is waiting for your selection.",
            lastMeaningfulEvent: trustPrompt,
            importantDetails: [trustPrompt],
            suggestedNextActions: [],
            agentIdentity: .claudeCode,
            agentInteractionState: .waitingChoice
        )

        monitor.observe(understandings: [existingTab, newTab, managed])

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .claudeCode })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingChoice })
        #expect(Set(capturedEvents.map(\.deltaText)) == [trustPrompt])
    }

    @Test
    func managedManualAndNewTabClaudeRunningToTrustPromptTransitionFiresEquivalentAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let runningStates = [
            TerminalUnderstanding.preview(
                terminalID: "claude-transition-existing",
                state: .running,
                shortExplanation: "Claude Code is working.",
                lastMeaningfulEvent: "Thinking...",
                importantDetails: ["Thinking..."],
                suggestedNextActions: [],
                agentIdentity: .claudeCode,
                agentInteractionState: .running,
                agentInteractionContext: .running(stepDescription: "Thinking...")
            ),
            TerminalUnderstanding.preview(
                terminalID: "claude-transition-new-tab",
                state: .running,
                shortExplanation: "Claude Code is working.",
                lastMeaningfulEvent: "Thinking...",
                importantDetails: ["Thinking..."],
                suggestedNextActions: [],
                agentIdentity: .claudeCode,
                agentInteractionState: .running,
                agentInteractionContext: .running(stepDescription: "Thinking...")
            ),
            TerminalUnderstanding.preview(
                terminalID: "claude-transition-managed",
                state: .running,
                shortExplanation: "Claude Code is working.",
                lastMeaningfulEvent: "Thinking...",
                importantDetails: ["Thinking..."],
                suggestedNextActions: [],
                agentIdentity: .claudeCode,
                agentInteractionState: .running,
                agentInteractionContext: .running(stepDescription: "Thinking...")
            ),
        ]
        monitor.observe(understandings: runningStates)
        #expect(capturedEvents.isEmpty)

        let trustPrompt = "Do you trust the files in this folder?"
        let waitingStates = [
            TerminalUnderstanding.preview(
                terminalID: "claude-transition-existing",
                state: .waiting,
                shortExplanation: "Claude Code is waiting for your selection.",
                lastMeaningfulEvent: trustPrompt,
                importantDetails: [trustPrompt],
                suggestedNextActions: [],
                agentIdentity: .claudeCode,
                agentInteractionState: .waitingChoice
            ),
            TerminalUnderstanding.preview(
                terminalID: "claude-transition-new-tab",
                state: .waiting,
                shortExplanation: "Claude Code is waiting for your selection.",
                lastMeaningfulEvent: trustPrompt,
                importantDetails: [trustPrompt],
                suggestedNextActions: [],
                agentIdentity: .claudeCode,
                agentInteractionState: .waitingChoice
            ),
            TerminalUnderstanding.preview(
                terminalID: "claude-transition-managed",
                state: .waiting,
                shortExplanation: "Claude Code is waiting for your selection.",
                lastMeaningfulEvent: trustPrompt,
                importantDetails: [trustPrompt],
                suggestedNextActions: [],
                agentIdentity: .claudeCode,
                agentInteractionState: .waitingChoice
            ),
        ]
        monitor.observe(understandings: waitingStates)

        #expect(capturedEvents.count == 3)
        #expect(capturedEvents.allSatisfy { $0.agentIdentity == .claudeCode })
        #expect(capturedEvents.allSatisfy { $0.interactionState == .waitingChoice })
        #expect(Set(capturedEvents.map(\.deltaText)) == [trustPrompt])
    }

    @Test
    func managedManualAndNewTabGenericCodexWireWaitingStatesDoNotFireAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let understandings = genericCodexWireUnderstandings()

        #expect(understandings.count == 3)
        #expect(understandings.allSatisfy { $0.agentIdentity == .codex })
        #expect(understandings.allSatisfy { $0.agentInteractionState == .waitingText })
        #expect(understandings.allSatisfy { $0.agentInteractionContext == .waitingText(question: nil) })

        monitor.observe(understandings: understandings)

        #expect(capturedEvents.isEmpty)
    }

    @Test
    func managedManualAndNewTabGenericClaudeWireWaitingStatesDoNotFireAttentionEvents() {
        let monitor = AgentStateMonitor()
        var capturedEvents: [AgentNeedsAttentionEvent] = []
        monitor.onEvent = { event in
            capturedEvents.append(event)
        }

        let understandings = genericClaudeWireUnderstandings()

        #expect(understandings.count == 3)
        #expect(understandings.allSatisfy { $0.agentIdentity == .claudeCode })
        #expect(understandings.allSatisfy { $0.agentInteractionState == .waitingText })
        #expect(understandings.allSatisfy { $0.agentInteractionContext == .waitingText(question: nil) })

        monitor.observe(understandings: understandings)

        #expect(capturedEvents.isEmpty)
    }
}

private func makeUnderstanding(
    terminalID: String,
    state: TerminalUnderstandingState,
    interactionState: AgentInteractionState,
    identity: AgentIdentity = .kimi,
    details: [String] = ["Test detail"]
) -> TerminalUnderstanding {
    TerminalUnderstanding.preview(
        terminalID: terminalID,
        state: state,
        shortExplanation: "Test understanding",
        lastMeaningfulEvent: "Test event",
        importantDetails: details,
        suggestedNextActions: [],
        agentIdentity: identity,
        agentInteractionState: interactionState
    )
}

private func genericCodexWireUnderstandings() -> [TerminalUnderstanding] {
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

    return ForemanObservedContextBuilder()
        .build(
            snapshots: snapshots,
            codexWireRecordsByTerminalID: codexWireRecordsByTerminalID
        )
        .context
        .understandings
}

private func genericClaudeWireUnderstandings() -> [TerminalUnderstanding] {
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

    return ForemanObservedContextBuilder()
        .build(
            snapshots: snapshots,
            claudeWireRecordsByTerminalID: claudeWireRecordsByTerminalID
        )
        .context
        .understandings
}
