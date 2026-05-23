import Foundation

struct ForemanObservedTerminalContext: Equatable, Sendable {
    let terminals: [TerminalSnapshot]
    let understandings: [TerminalUnderstanding]
}
