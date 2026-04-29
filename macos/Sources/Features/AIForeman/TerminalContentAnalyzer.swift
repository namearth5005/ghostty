import Foundation

enum TerminalContentType {
    case shellPromptOnly
    case directoryListing
    case gitStatus
    case testOutput
    case buildOutput
    case errorOutput
    case progressOutput
    case generalOutput
}

struct TerminalContentAnalysis {
    let type: TerminalContentType
    let summary: String
}

enum TerminalContentAnalyzer {
    static func analyze(_ snapshot: TerminalSnapshot) -> TerminalContentAnalysis {
        let lines = snapshot.visibleText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return .init(type: .shellPromptOnly, summary: "Waiting for terminal output.")
        }

        // Single line = probably just a prompt
        if lines.count == 1 {
            return .init(type: .shellPromptOnly, summary: "Idle")
        }

        // Check for specific content types in priority order
        if isGitStatus(lines) {
            return .init(type: .gitStatus, summary: summarizeGitStatus(lines))
        }

        if isTestOutput(lines) {
            return .init(type: .testOutput, summary: summarizeTestOutput(lines))
        }

        if isBuildOutput(lines) {
            return .init(type: .buildOutput, summary: summarizeBuildOutput(lines))
        }

        if isErrorOutput(lines) {
            return .init(type: .errorOutput, summary: summarizeErrorOutput(lines))
        }

        if isProgressOutput(lines) {
            return .init(type: .progressOutput, summary: summarizeProgressOutput(lines))
        }

        if isDirectoryListing(lines) {
            return .init(type: .directoryListing, summary: summarizeDirectoryListing(lines))
        }

        // Fallback: general output — show last meaningful line
        return .init(type: .generalOutput, summary: summarizeGeneralOutput(lines))
    }

    // MARK: - Detectors

    private static func isDirectoryListing(_ lines: [String]) -> Bool {
        guard lines.count >= 5 else { return false }
        let avgLength = lines.reduce(0) { $0 + $1.count } / lines.count
        // Directory listings: many lines, short, often colored (contain ANSI or common patterns)
        let hasShortLines = avgLength < 60
        // Check for common ls patterns: no sentence punctuation, mostly alphanumeric + common symbols
        let cleanLines = lines.filter { line in
            !line.contains(".") || line.split(separator: ".").count <= 2
        }
        return hasShortLines && cleanLines.count > lines.count / 2
    }

    private static func isGitStatus(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("On branch") || $0.contains("Changes to be committed") || $0.contains("Untracked files") }
    }

    private static func isTestOutput(_ lines: [String]) -> Bool {
        let testPatterns = ["PASS", "FAIL", "ok ", "running", "test result:", "tests passed", "tests failed"]
        return lines.contains { line in
            testPatterns.contains { line.contains($0) }
        }
    }

    private static func isBuildOutput(_ lines: [String]) -> Bool {
        let buildPatterns = ["compiling", "building", "linking", " Finished", " Built", " Compiling", " Building"]
        return lines.contains { line in
            buildPatterns.contains { line.lowercased().contains($0) }
        }
    }

    private static func isErrorOutput(_ lines: [String]) -> Bool {
        let errorPatterns = ["error:", "fatal:", "panic:", "exception:", "traceback", "failed to"]
        return lines.contains { line in
            errorPatterns.contains { line.lowercased().contains($0) }
        }
    }

    private static func isProgressOutput(_ lines: [String]) -> Bool {
        // Single or few lines with percentage or progress indicators
        guard lines.count <= 3 else { return false }
        return lines.contains { line in
            line.contains("%") || line.contains("/s") || line.contains("ETA")
        }
    }

    // MARK: - Summarizers

    private static func summarizeDirectoryListing(_ lines: [String]) -> String {
        let itemCount = lines.count
        let names = lines.prefix(5).joined(separator: ", ")
        let extensions = lines.compactMap { line -> String? in
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard let dot = clean.lastIndex(of: ".") else { return nil }
            let ext = String(clean[dot...]).lowercased()
            return ext.count <= 6 ? ext : nil
        }
        let uniqueExts = Array(Set(extensions)).sorted().prefix(3)
        let extPart = uniqueExts.isEmpty ? "" : " (\(uniqueExts.joined(separator: ", "))...)"

        if itemCount <= 5 {
            return "\(itemCount) items: \(names)"
        }
        return "\(itemCount) items: \(names)\(extPart)"
    }

    private static func summarizeGitStatus(_ lines: [String]) -> String {
        let branchLine = lines.first { $0.contains("On branch") }
        let branch = branchLine?.replacingOccurrences(of: "On branch ", with: "") ?? "unknown"

        let modified = lines.filter { $0.contains("modified:") || $0.contains("deleted:") || $0.contains("new file:") }.count
        let untracked = lines.filter { $0.contains("Untracked") }.count

        var parts: [String] = []
        if modified > 0 { parts.append("\(modified) changed") }
        if untracked > 0 { parts.append("\(untracked) untracked") }

        let status = parts.isEmpty ? "clean" : parts.joined(separator: ", ")
        return "\(branch) — \(status)"
    }

    private static func summarizeTestOutput(_ lines: [String]) -> String {
        let lastRelevant = lines.reversed().first { line in
            line.contains("passed") || line.contains("failed") || line.contains("PASS") || line.contains("FAIL")
        }
        return lastRelevant ?? lines.last ?? "Tests running..."
    }

    private static func summarizeBuildOutput(_ lines: [String]) -> String {
        // Show the most recent progress or completion line
        let progress = lines.reversed().first { line in
            line.contains("Building") || line.contains("Compiling") || line.contains("Finished") || line.contains("Built")
        }
        return progress ?? lines.last ?? "Building..."
    }

    private static func summarizeErrorOutput(_ lines: [String]) -> String {
        let firstError = lines.first { line in
            line.lowercased().contains("error:") || line.lowercased().contains("fatal:")
        }
        if let error = firstError {
            return String(error.prefix(120))
        }
        return lines.last ?? "Error occurred"
    }

    private static func summarizeProgressOutput(_ lines: [String]) -> String {
        return lines.last ?? "In progress..."
    }

    private static func summarizeGeneralOutput(_ lines: [String]) -> String {
        // For general output, show the last non-prompt line if possible
        let lastMeaningful = lines.reversed().first { line in
            !isShellPrompt(line)
        }
        return String((lastMeaningful ?? lines.last ?? "").prefix(120))
    }

    private static func isShellPrompt(_ line: String) -> Bool {
        let promptPatterns = ["$ ", "# ", "~ ", "> ", "% ", "→ "]
        return promptPatterns.contains { line.hasSuffix($0) || line.contains($0) }
    }
}
