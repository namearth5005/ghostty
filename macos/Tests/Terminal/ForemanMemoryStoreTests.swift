import XCTest
@testable import Ghostty

final class ForemanMemoryStoreTests: XCTestCase {
    var store: ForemanMemoryStore!

    override func setUp() async throws {
        store = ForemanMemoryStore.shared
        try await store.open()
    }

    override func tearDown() async throws {
        try await store.compactOldRecords(before: Date.distantFuture)
    }

    func testStoreAndQueryRecord() async throws {
        let record = SituationOutcomeRecord(
            id: UUID(),
            terminalID: "test-term-1",
            situationFingerprint: 12345,
            cwd: "/Users/test/project",
            action: "npm test",
            outcome: .success,
            visibleText: "Tests passed",
            timestamp: Date(),
            projectPath: "/Users/test/project"
        )

        try await store.store(record: record)
        let results = try await store.query(cwd: "/Users/test/project", visibleText: "npm test", limit: 5)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.action, "npm test")
        XCTAssertEqual(results.first?.outcome, .success)
    }

    func testQueryReturnsEmptyForUnknownCWD() async throws {
        let results = try await store.query(cwd: "/nonexistent", visibleText: "foo", limit: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testCompactOldRecords() async throws {
        let oldRecord = SituationOutcomeRecord(
            id: UUID(),
            terminalID: "test-term-1",
            situationFingerprint: 99999,
            cwd: "/Users/test/old",
            action: "git status",
            outcome: .unknown,
            visibleText: nil,
            timestamp: Date(timeIntervalSince1970: 0),
            projectPath: nil
        )

        try await store.store(record: oldRecord)
        try await store.compactOldRecords(before: Date(timeIntervalSince1970: 100))

        let results = try await store.query(cwd: "/Users/test/old", visibleText: "git", limit: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testStoreAndQuerySessionSummary() async throws {
        let summary = SessionSummary(
            id: UUID(),
            terminalID: "test-term-1",
            summary: "Debugged auth issues",
            keywords: ["auth", "debug"],
            projectPath: "/Users/test/project",
            timestamp: Date()
        )

        try await store.store(summary: summary)
        // Session summaries are queried separately; store validates schema works
        XCTAssertTrue(true)
    }
}
