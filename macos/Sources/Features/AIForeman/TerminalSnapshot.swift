import Foundation

struct TerminalSnapshot: Codable, Equatable, Sendable {
    struct Signals: Codable, Equatable, Sendable {
        var likelyWaitingForInput: Bool
        var likelyLongRunning: Bool
        var likelyErrorState: Bool
        var likelyTUI: Bool
    }

    let terminalID: String
    let windowID: String
    let tabID: String
    let title: String
    let cwd: String?
    let isFocused: Bool
    let captureMode: String
    let visibleText: String
    let recentScrollback: String
    let lastInputPreview: String?
    let signals: Signals

    var summaryInput: String {
        var components: [String] = [title]
        if let cwd, !cwd.isEmpty {
            components.append(cwd)
        }
        if let lastInputPreview, !lastInputPreview.isEmpty {
            components.append(lastInputPreview)
        }
        if !visibleText.isEmpty {
            components.append(visibleText)
        }
        if !recentScrollback.isEmpty {
            components.append(recentScrollback)
        }
        return components.joined(separator: "\n")
    }

    static func makePreview(
        terminalID: String,
        windowID: String,
        tabID: String,
        title: String,
        cwd: String?,
        isFocused: Bool,
        visibleText: String,
        recentScrollbackLines: [String],
        lastInputPreview: String?
    ) -> TerminalSnapshot {
        let capped = Array(recentScrollbackLines.suffix(250)).joined(separator: "\n")
        let normalizedVisible = normalizeTerminalText(visibleText)
        let normalizedScrollback = normalizeTerminalText(capped)
        let commandSignals = [normalizedVisible, lastInputPreview]
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
        let trimmedVisible = normalizedVisible.trimmingCharacters(in: .whitespacesAndNewlines)
        return TerminalSnapshot(
            terminalID: terminalID,
            windowID: windowID,
            tabID: tabID,
            title: title,
            cwd: cwd,
            isFocused: isFocused,
            captureMode: "shell",
            visibleText: normalizedVisible,
            recentScrollback: normalizedScrollback,
            lastInputPreview: lastInputPreview,
            signals: .init(
                likelyWaitingForInput: isLikelyWaitingForInput(trimmedVisible),
                likelyLongRunning: isLikelyLongRunning(commandSignals),
                likelyErrorState: isLikelyErrorState(normalizedVisible),
                likelyTUI: isLikelyTUI(commandSignals)
            )
        )
    }

    private static func normalizeTerminalText(_ text: String) -> String {
        let canonicalLineEndings = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let scalars = Array(canonicalLineEndings.unicodeScalars)
        var index = 0
        var normalized = String()
        normalized.reserveCapacity(canonicalLineEndings.count)

        while index < scalars.count {
            let scalar = scalars[index]

            if scalar == "\u{1B}" {
                index = skipEscapeSequence(in: scalars, from: index)
                continue
            }

            if scalar == "\u{7}" {
                index += 1
                continue
            }

            if scalar == "\t" {
                normalized.append(" ")
                index += 1
                continue
            }

            if scalar != "\n" && (scalar.value < 0x20 || scalar.value == 0x7F) {
                index += 1
                continue
            }

            normalized.unicodeScalars.append(scalar)
            index += 1
        }

        return normalized
    }

    private static func skipEscapeSequence(in scalars: [UnicodeScalar], from start: Int) -> Int {
        guard start + 1 < scalars.count else {
            return scalars.count
        }

        let introducer = scalars[start + 1]
        if introducer == "[" {
            var index = start + 2
            while index < scalars.count {
                let scalar = scalars[index]
                if (0x40...0x7E).contains(scalar.value) {
                    return index + 1
                }
                index += 1
            }
            return scalars.count
        }

        if introducer == "]" || introducer == "P" || introducer == "_" || introducer == "^" {
            var index = start + 2
            while index < scalars.count {
                if scalars[index] == "\u{7}" {
                    return index + 1
                }

                if scalars[index] == "\u{1B}", index + 1 < scalars.count, scalars[index + 1] == "\\" {
                    return index + 2
                }

                index += 1
            }
            return scalars.count
        }

        return min(start + 2, scalars.count)
    }

    private static func isLikelyTUI(_ commandSignals: String) -> Bool {
        if commandSignals.contains("\u{1b}[?1049h") {
            return true
        }

        return [
            "vim",
            "nvim",
            "less",
            "top",
            "htop",
            "fzf",
            "tmux",
            "nano",
            "emacs",
        ].contains { commandSignals.contains($0) }
    }

    private static func isLikelyLongRunning(_ commandSignals: String) -> Bool {
        [
            "building",
            "compiling",
            "running",
            "watching",
            "bundling",
            "transpiling",
            "make ",
            "cargo ",
            "npm ",
            "yarn ",
            "pnpm ",
            "pytest",
            "xcodebuild",
            "swift test",
            "docker build",
            "docker compose",
            "webpack",
            "vite ",
            "jest",
            "vitest",
            "playwright",
            "cypress",
        ].contains { commandSignals.contains($0) }
    }

    private static func isLikelyWaitingForInput(_ visibleText: String) -> Bool {
        guard !visibleText.isEmpty else { return false }
        let promptChars: [Character] = ["$", "%", "#", ">", "λ", "❯", "➜", "→", "⇒"]
        let lastLine = visibleText.split(separator: "\n").last?.trimmingCharacters(in: .whitespaces) ?? visibleText
        return promptChars.contains(where: { lastLine.hasSuffix(String($0)) })
    }

    private static func isLikelyErrorState(_ visibleText: String) -> Bool {
        let errorMarkers = [
            "error", "fail", "fatal", "panic", "assertion",
            "exception", "segfault", "timeout", "denied",
            "unauthorized", "not found", "cannot", "could not",
        ]
        let lowered = visibleText.lowercased()
        return errorMarkers.contains { lowered.contains($0) }
    }
}
