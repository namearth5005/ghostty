import Foundation
import Testing
@testable import Ghostty

struct ForemanAgentDeltaIntegrationTests {

    /// Simulates a terminal with a long build log. When the agent takes a second snapshot,
    /// only the newly appended lines should appear in the delta.
    @Test
    func buildLogDeltaOnlyShowsNewLines() {
        let previousSnapshot = TerminalSnapshot.makePreview(
            terminalID: "test-build",
            windowID: "w1",
            tabID: "t1",
            title: "Build",
            cwd: "/project",
            isFocused: true,
            visibleText: (1...50).map { "Compiling file_\($0).swift..." }.joined(separator: "\n"),
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let currentSnapshot = TerminalSnapshot.makePreview(
            terminalID: "test-build",
            windowID: "w1",
            tabID: "t1",
            title: "Build",
            cwd: "/project",
            isFocused: true,
            visibleText: (1...55).map { "Compiling file_\($0).swift..." }.joined(separator: "\n"),
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let delta = TerminalSnapshot.computeTextDelta(
            previous: previousSnapshot.visibleText,
            current: currentSnapshot.visibleText
        )

        let deltaLines = delta.split(separator: "\n").count
        let originalLines = currentSnapshot.visibleText.split(separator: "\n").count

        #expect(deltaLines == 5, "Delta should contain only the 5 new lines, got \(deltaLines)")
        #expect(deltaLines < originalLines, "Delta should be smaller than original")
        #expect(delta.contains("Compiling file_55.swift..."), "Delta should include the newest line")
        #expect(!delta.contains("Compiling file_1.swift..."), "Delta should not include old lines")
    }

    /// Simulates a Kimi terminal that was idle, then produced an approval request.
    /// The delta should capture just the approval prompt.
    @Test
    func kimiApprovalRequestDelta() {
        let previous = TerminalSnapshot.makePreview(
            terminalID: "test-kimi",
            windowID: "w1",
            tabID: "t1",
            title: "Kimi",
            cwd: "/project",
            isFocused: true,
            visibleText: "Welcome to Kimi Code CLI!\nDirectory: /project\nSession: abc-123\nModel: kimi-k2.6\n--- input ---",
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let current = TerminalSnapshot.makePreview(
            terminalID: "test-kimi",
            windowID: "w1",
            tabID: "t1",
            title: "Kimi",
            cwd: "/project",
            isFocused: true,
            visibleText: "Welcome to Kimi Code CLI!\nDirectory: /project\nSession: abc-123\nModel: kimi-k2.6\n--- input ---\nAllow edit to README.md?\n[y/n]",
            recentScrollbackLines: [],
            lastInputPreview: nil
        )

        let delta = TerminalSnapshot.computeTextDelta(
            previous: previous.visibleText,
            current: current.visibleText
        )

        #expect(delta.contains("Allow edit to README.md?"), "Delta should capture approval prompt")
        #expect(delta.contains("[y/n]"), "Delta should capture response options")
        #expect(!delta.contains("Welcome to Kimi"), "Delta should not include welcome screen")
    }

    /// Simulates a terminal where nothing changed between snapshots.
    @Test
    func noChangeReturnsNoNewOutput() {
        let text = "Line 1\nLine 2\nLine 3"

        let delta = TerminalSnapshot.computeTextDelta(
            previous: text,
            current: text
        )

        #expect(delta == "(no new output)", "Identical text should yield no new output")
    }

    /// Verifies that a long terminal output is truncated when there's no previous snapshot.
    @Test
    func freshTerminalTruncatesToMaxLines() {
        let longText = (1...200).map { "Line \($0)" }.joined(separator: "\n")

        let delta = TerminalSnapshot.computeTextDelta(
            previous: nil,
            current: longText,
            maxLines: 50
        )

        let deltaLines = delta.split(separator: "\n", omittingEmptySubsequences: false).count
        let deltaLineSet = Set(delta.split(separator: "\n").map(String.init))
        #expect(deltaLines <= 50, "Should cap to maxLines, got \(deltaLines)")
        #expect(deltaLineSet.contains("Line 200"), "Should include the most recent lines")
        #expect(!deltaLineSet.contains("Line 1"), "Should not include the oldest lines")
    }

    /// Verifies delta size savings on realistic multi-terminal output.
    @Test
    func deltaSavesSignificantContextTokens() {
        let previousText = (1...100).map { "Output line \($0)" }.joined(separator: "\n")
        let currentText = previousText + "\nNew error: permission denied\nRetrying..."

        let delta = TerminalSnapshot.computeTextDelta(
            previous: previousText,
            current: currentText
        )

        let savings = currentText.count - delta.count
        #expect(savings > 1000, "Delta should save significant tokens, saved \(savings)")
        #expect(delta.contains("permission denied"), "Delta should include the critical new line")
    }
}
