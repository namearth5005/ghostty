import Testing
@testable import Ghostty

private struct StubSnapshotSource: TerminalSnapshotSource {
    let terminalSnapshotTerminalID: String
    let terminalSnapshotWindowID: String
    let terminalSnapshotTabID: String
    let terminalSnapshotTitle: String
    let terminalSnapshotWorkingDirectory: String?
    let terminalSnapshotIsFocused: Bool
    let terminalSnapshotVisibleText: String
    let terminalSnapshotRecentScrollbackLines: [String]
    let terminalSnapshotLastInputPreview: String?
}

struct TerminalSnapshotCaptureTests {
    @Test
    func captureSnapshotUsesMetadataAndBoundsScrollback() async {
        let source = StubSnapshotSource(
            terminalSnapshotTerminalID: "term-1",
            terminalSnapshotWindowID: "win-1",
            terminalSnapshotTabID: "tab-1",
            terminalSnapshotTitle: "nvim",
            terminalSnapshotWorkingDirectory: "/tmp/project",
            terminalSnapshotIsFocused: true,
            terminalSnapshotVisibleText: "error: failed to build",
            terminalSnapshotRecentScrollbackLines: Array(repeating: "line", count: 500),
            terminalSnapshotLastInputPreview: nil
        )

        let snapshot = await source.makeTerminalSnapshot()

        #expect(snapshot.terminalID == "term-1")
        #expect(snapshot.windowID == "win-1")
        #expect(snapshot.tabID == "tab-1")
        #expect(snapshot.title == "nvim")
        #expect(snapshot.cwd == "/tmp/project")
        #expect(snapshot.isFocused == true)
        #expect(snapshot.signals.likelyErrorState == true)
        #expect(snapshot.recentScrollback.split(separator: "\n").count == 250)
    }
}
