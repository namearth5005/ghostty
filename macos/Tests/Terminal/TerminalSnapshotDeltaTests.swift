import Foundation
import Testing
@testable import Ghostty

struct TerminalSnapshotDeltaTests {

    @Test
    func noPreviousReturnsTruncatedCurrent() {
        let current = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
        let delta = TerminalSnapshot.computeTextDelta(previous: nil, current: current)
        #expect(delta == current, "With no previous, should return current text")
    }

    @Test
    func appendedTextReturnsOnlyDelta() {
        let previous = "Line 1\nLine 2"
        let current = "Line 1\nLine 2\nLine 3\nLine 4"
        let delta = TerminalSnapshot.computeTextDelta(previous: previous, current: current)
        #expect(delta == "Line 3\nLine 4", "Should return only newly appended lines")
    }

    @Test
    func identicalTextReturnsNoNewOutput() {
        let previous = "Line 1\nLine 2"
        let current = "Line 1\nLine 2"
        let delta = TerminalSnapshot.computeTextDelta(previous: previous, current: current)
        #expect(delta == "(no new output)", "Identical text should indicate no new output")
    }

    @Test
    func partialChangeReturnsNewTailLines() {
        let previous = "Line 1\nLine 2\nLine 3"
        let current = "Line 1\nLine 2 changed\nLine 3\nLine 4"
        let delta = TerminalSnapshot.computeTextDelta(previous: previous, current: current)
        #expect(delta.contains("Line 4"), "Should include the new line at the end")
    }

    @Test
    func respectsMaxLines() {
        let previous = "Line 1"
        let current = (1...100).map { "Line \($0)" }.joined(separator: "\n")
        let delta = TerminalSnapshot.computeTextDelta(previous: previous, current: current, maxLines: 10)
        let lineCount = delta.split(separator: "\n").count
        #expect(lineCount <= 10, "Should cap to maxLines, got \(lineCount)")
    }

    @Test
    func respectsMaxChars() {
        let previous = "Line 1"
        let current = String(repeating: "a", count: 5000)
        let delta = TerminalSnapshot.computeTextDelta(previous: previous, current: current, maxChars: 100)
        #expect(delta.count <= 100, "Should cap to maxChars, got \(delta.count)")
    }

    @Test
    func stripsAnsiEscapeCodes() {
        let previous = ""
        let current = "\u{1B}[32mGreen text\u{1B}[0m\nNormal text"
        let delta = TerminalSnapshot.computeTextDelta(previous: nil, current: current)
        #expect(!delta.contains("\u{1B}"), "Should strip ANSI escape codes")
        #expect(delta.contains("Green text"), "Should preserve text content")
    }
}
