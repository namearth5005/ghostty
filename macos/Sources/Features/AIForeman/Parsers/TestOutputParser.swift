import Foundation

struct TestOutputParser: TerminalOutputParser {
    let commandHints = ["jest", "vitest", "pytest", "cargo test", "npm test", "pnpm test", "yarn test"]

    func parse(visibleText: String, scrollback: String) -> ParsedTerminalOutput? {
        let combined = visibleText + "\n" + scrollback

        if let jest = parseJest(combined) {
            return jest
        }
        if let pytest = parsePytest(combined) {
            return pytest
        }
        if let cargo = parseCargo(combined) {
            return cargo
        }

        return nil
    }

    private func parseJest(_ text: String) -> TestOutput? {
        let pattern = /Tests:\s+(?:(\d+) failed,?\s*)?(?:(\d+) passed,?\s*)?(?:(\d+) skipped,?\s*)?(?:(\d+) total)?/
        guard let match = text.firstMatch(of: pattern) else { return nil }

        let failed = Int(match.output.1 ?? "0") ?? 0
        let passed = Int(match.output.2 ?? "0") ?? 0
        let skipped = Int(match.output.3 ?? "0") ?? 0

        let failPattern = /FAIL\s+(.+)/
        let failedTests = text.matches(of: failPattern).map { String($0.output.1).trimmingCharacters(in: .whitespaces) }

        return TestOutput(
            framework: "jest",
            passed: passed,
            failed: failed,
            skipped: skipped,
            durationMs: nil,
            failedTests: failedTests
        )
    }

    private func parsePytest(_ text: String) -> TestOutput? {
        let patterns = [
            "(\\d+) passed.*?[,;]\\s*(\\d+) failed.*?[,;]\\s*(\\d+) skipped",
            "(\\d+) failed.*?[,;]\\s*(\\d+) passed.*?[,;]\\s*(\\d+) skipped",
            "(\\d+) passed.*?[,;]\\s*(\\d+) skipped",
            "(\\d+) failed.*?[,;]\\s*(\\d+) passed",
        ]

        var passed = 0, failed = 0, skipped = 0
        var matched = false
        for patternStr in patterns {
            guard let regex = try? Regex(patternStr) else { continue }
            if let match = text.firstMatch(of: regex) {
                let ints = match.output.dropFirst().compactMap { Int($0.substring ?? "") }
                if ints.count >= 2 {
                    if patternStr.contains("passed") && patternStr.contains("failed") && patternStr.contains("skipped") {
                        passed = ints[0]; failed = ints[1]; skipped = ints[2]
                    } else if patternStr.contains("failed") && patternStr.contains("passed") && patternStr.contains("skipped") {
                        failed = ints[0]; passed = ints[1]; skipped = ints[2]
                    } else if patternStr.contains("passed") && patternStr.contains("skipped") {
                        passed = ints[0]; skipped = ints[1]
                    } else if patternStr.contains("failed") && patternStr.contains("passed") {
                        failed = ints[0]; passed = ints[1]
                    }
                    matched = true
                    break
                }
            }
        }
        guard matched else { return nil }

        let failPattern = /FAILED\s+(.+)/
        let failedTests = text.matches(of: failPattern).map { String($0.output.1).trimmingCharacters(in: .whitespaces) }

        return TestOutput(
            framework: "pytest",
            passed: passed,
            failed: failed,
            skipped: skipped,
            durationMs: nil,
            failedTests: failedTests
        )
    }

    private func parseCargo(_ text: String) -> TestOutput? {
        let pattern = /test result:\s*(?:FAILED|ok)\.\s*(\d+) passed\s*[,;]?\s*(\d+) failed\s*[,;]?\s*(\d+) ignored/
        guard let match = text.firstMatch(of: pattern) else { return nil }

        let passed = Int(match.output.1) ?? 0
        let failed = Int(match.output.2) ?? 0
        let skipped = Int(match.output.3) ?? 0

        let failPattern = /test\s+(.+?)\s+\.\.\.\s+FAILED/
        let failedTests = text.matches(of: failPattern).map { String($0.output.1).trimmingCharacters(in: .whitespaces) }

        return TestOutput(
            framework: "cargo",
            passed: passed,
            failed: failed,
            skipped: skipped,
            durationMs: nil,
            failedTests: failedTests
        )
    }
}
