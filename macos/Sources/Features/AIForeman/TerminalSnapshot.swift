import Foundation

struct TerminalSnapshot: Codable, Equatable, Sendable {
    struct Signals: Codable, Equatable, Sendable {
        var likelyWaitingForInput: Bool
        var likelyLongRunning: Bool
        var likelyErrorState: Bool
        var likelyTUI: Bool
    }

    struct Runtime: Codable, Equatable, Sendable {
        var foregroundProcessID: Int?
        var foregroundProcessName: String?
        var cursorIsAtPrompt: Bool
        var usingAlternateScreen: Bool
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
    let runtime: Runtime
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
        lastInputPreview: String?,
        foregroundProcessID: Int? = nil,
        foregroundProcessName: String? = nil,
        cursorIsAtPrompt: Bool? = nil,
        usingAlternateScreen: Bool = false
    ) -> TerminalSnapshot {
        let capped = Array(recentScrollbackLines.suffix(250)).joined(separator: "\n")
        let normalizedVisible = normalizeTerminalText(visibleText)
        let normalizedScrollback = normalizeTerminalText(capped)
        let commandSignals = [normalizedVisible, lastInputPreview]
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
        let trimmedVisible = normalizedVisible.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptSignal = cursorIsAtPrompt ?? isLikelyWaitingForInput(trimmedVisible)
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
            runtime: .init(
                foregroundProcessID: foregroundProcessID,
                foregroundProcessName: foregroundProcessName,
                cursorIsAtPrompt: promptSignal,
                usingAlternateScreen: usingAlternateScreen
            ),
            signals: .init(
                likelyWaitingForInput: promptSignal,
                likelyLongRunning: isLikelyLongRunning(commandSignals),
                likelyErrorState: isLikelyErrorState(normalizedVisible),
                likelyTUI: usingAlternateScreen || isLikelyTUI(commandSignals)
            )
        )
    }

    /// Computes the delta between a previous terminal text and the current one,
    /// returning only lines that are new or changed. Falls back to the last
    /// portion of current text when no previous snapshot exists.
    static func computeTextDelta(previous: String?, current: String, maxLines: Int = 50, maxChars: Int = 2000) -> String {
        let currentNormalized = normalizeTerminalText(current)
        
        guard let previous, !previous.isEmpty else {
            // No previous snapshot — return truncated current text
            let lines = currentNormalized.split(separator: "\n", omittingEmptySubsequences: false)
            let capped = Array(lines.suffix(maxLines))
            let result = capped.joined(separator: "\n")
            return String(result.suffix(maxChars))
        }
        
        let previousNormalized = normalizeTerminalText(previous)
        
        // Fast path: current starts with previous (text was appended)
        if currentNormalized.hasPrefix(previousNormalized) {
            let delta = String(currentNormalized.dropFirst(previousNormalized.count))
            let trimmed = delta.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "(no new output)" }
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            let capped = Array(lines.suffix(maxLines))
            let result = capped.joined(separator: "\n")
            return String(result.suffix(maxChars))
        }
        
        // Line-based diff: find lines in current not in previous
        let prevLines = Set(previousNormalized.split(separator: "\n").map(String.init))
        let currLines = currentNormalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        // Find consecutive new lines at the end (most common pattern)
        var newLineCount = 0
        for line in currLines.reversed() {
            if !prevLines.contains(line) {
                newLineCount += 1
            } else {
                break
            }
        }
        
        let resultLines = Array(currLines.suffix(min(newLineCount, maxLines)))
        let result = resultLines.joined(separator: "\n")
        
        if result.isEmpty {
            return "(no new output)"
        }
        
        return String(result.suffix(maxChars))
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
        // Check for alternate screen buffer escape sequence (TUI apps use this)
        if commandSignals.contains("\u{1b}[?1049h") {
            return true
        }

        // Use word-boundary matching to avoid false positives like "Desktop" matching "top"
        let tuiCommands = [
            "vim", "nvim", "less", "top", "htop", "fzf", "tmux", "nano", "emacs"
        ]
        let words = commandSignals.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let wordSet = Set(words)
        return tuiCommands.contains { wordSet.contains($0) }
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

    static func isLikelyErrorState(_ visibleText: String) -> Bool {
        let errorMarkers = [
            "error", "fail", "fatal", "panic", "assertion",
            "exception", "segfault", "timeout", "denied",
            "unauthorized", "not found", "cannot", "could not",
        ]
        let lowered = visibleText.lowercased()
        return errorMarkers.contains { lowered.contains($0) }
    }
}
