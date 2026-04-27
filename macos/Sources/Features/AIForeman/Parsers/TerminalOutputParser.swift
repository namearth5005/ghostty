import Foundation

protocol TerminalOutputParser: Sendable {
    var commandHints: [String] { get }
    func parse(visibleText: String, scrollback: String) -> ParsedTerminalOutput?
}

protocol ParsedTerminalOutput: Sendable {
    var parserType: String { get }
}

struct TestOutput: ParsedTerminalOutput, Equatable {
    let parserType = "test"
    let framework: String
    let passed: Int
    let failed: Int
    let skipped: Int
    let durationMs: Int?
    let failedTests: [String]
}

struct GitStatusOutput: ParsedTerminalOutput, Equatable {
    let parserType = "git"
    let branch: String
    let ahead: Int
    let behind: Int
    let modifiedFiles: Int
    let untrackedFiles: Int
    let isMergeConflict: Bool
}
