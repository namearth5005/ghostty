import Foundation
import SQLite3

actor ForemanMemoryStore {
    static let shared = ForemanMemoryStore()

    private var db: OpaquePointer?
    private let dbPath: URL

    init(dbPath: URL? = nil) {
        if let dbPath {
            let parentDirectory = dbPath.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true
            )
            self.dbPath = dbPath
            return
        }

        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let foremanDir = supportDir.appendingPathComponent("Foreman", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: foremanDir,
            withIntermediateDirectories: true
        )

        self.dbPath = foremanDir.appendingPathComponent("memory.sqlite3")
    }

    func open() throws {
        guard db == nil else { return }

        let path = dbPath.path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw MemoryError.openFailed
        }

        try createSchema()
    }

    func close() {
        guard let db = db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    private func createSchema() throws {
        let schema = """
            CREATE TABLE IF NOT EXISTS situation_outcomes (
                id TEXT PRIMARY KEY,
                terminal_id TEXT NOT NULL,
                situation_fingerprint INTEGER NOT NULL,
                cwd TEXT NOT NULL,
                action TEXT NOT NULL,
                outcome TEXT NOT NULL,
                visible_text TEXT,
                timestamp REAL NOT NULL,
                project_path TEXT
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS situation_fts USING fts5(
                visible_text,
                action,
                content='situation_outcomes',
                content_rowid='rowid'
            );

            CREATE TABLE IF NOT EXISTS session_summaries (
                id TEXT PRIMARY KEY,
                terminal_id TEXT NOT NULL,
                summary TEXT NOT NULL,
                keywords TEXT NOT NULL,
                project_path TEXT,
                timestamp REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS project_goals (
                project_path TEXT PRIMARY KEY,
                goal_text TEXT NOT NULL,
                status TEXT NOT NULL,
                updated_at REAL NOT NULL,
                completed_at REAL,
                last_evaluated_at REAL,
                last_evidence_snapshot TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_situation_cwd ON situation_outcomes(cwd);
            CREATE INDEX IF NOT EXISTS idx_situation_project ON situation_outcomes(project_path);
            CREATE INDEX IF NOT EXISTS idx_situation_timestamp ON situation_outcomes(timestamp);
            CREATE INDEX IF NOT EXISTS idx_summary_project ON session_summaries(project_path);
            CREATE INDEX IF NOT EXISTS idx_project_goal_status ON project_goals(status);

            PRAGMA user_version = 2;
            """

        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, schema, nil, nil, &errMsg) == SQLITE_OK else {
            if let errMsg = errMsg {
                let message = String(cString: errMsg)
                sqlite3_free(errMsg)
                throw MemoryError.schemaFailed(message)
            }
            throw MemoryError.schemaFailed("unknown error")
        }
    }

    func store(record: SituationOutcomeRecord) throws {
        try open()

        let sql = """
            INSERT INTO situation_outcomes
            (id, terminal_id, situation_fingerprint, cwd, action, outcome, visible_text, timestamp, project_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemoryError.insertFailed
        }

        sqlite3_bind_text(stmt, 1, (record.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (record.terminalID as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, Int64(record.situationFingerprint))
        sqlite3_bind_text(stmt, 4, (record.cwd as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (record.action as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (record.outcome.rawValue as NSString).utf8String, -1, nil)
        if let visibleText = record.visibleText {
            sqlite3_bind_text(stmt, 7, (visibleText as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_bind_double(stmt, 8, record.timestamp.timeIntervalSince1970)
        if let projectPath = record.projectPath {
            sqlite3_bind_text(stmt, 9, (projectPath as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 9)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            sqlite3_finalize(stmt)
            throw MemoryError.insertFailed
        }

        sqlite3_finalize(stmt)
    }

    func query(cwd: String, visibleText: String, limit: Int = 5) throws -> [SituationOutcomeRecord] {
        try open()

        let projectPath = ForemanProjectPathResolver.projectPath(from: cwd) ?? cwd
        let keywords = extractKeywords(from: visibleText)

        var results: [SituationOutcomeRecord] = []

        // Strategy 1: same project path, ordered by recency
        let projectSQL = """
            SELECT id, terminal_id, situation_fingerprint, cwd, action, outcome, visible_text, timestamp, project_path
            FROM situation_outcomes
            WHERE project_path = ? OR cwd = ?
            ORDER BY timestamp DESC
            LIMIT ?;
            """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, projectSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (projectPath as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (cwd as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 3, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let record = rowToRecord(stmt) {
                    results.append(record)
                }
            }
            sqlite3_finalize(stmt)
        }

        // Strategy 2: keyword overlap via FTS5 if we still need more
        if results.count < limit && !keywords.isEmpty {
            let ftsQuery = keywords.joined(separator: " OR ")
            let ftsSQL = """
                SELECT s.id, s.terminal_id, s.situation_fingerprint, s.cwd, s.action, s.outcome, s.visible_text, s.timestamp, s.project_path
                FROM situation_fts f
                JOIN situation_outcomes s ON s.rowid = f.rowid
                WHERE situation_fts MATCH ?
                ORDER BY s.timestamp DESC
                LIMIT ?;
                """

            if sqlite3_prepare_v2(db, ftsSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 2, Int32(limit - results.count))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let record = rowToRecord(stmt) {
                        // Deduplicate by fingerprint
                        if !results.contains(where: { $0.situationFingerprint == record.situationFingerprint }) {
                            results.append(record)
                        }
                    }
                }
                sqlite3_finalize(stmt)
            }
        }

        return Array(results.prefix(limit))
    }

    func store(summary: SessionSummary) throws {
        try open()

        let sql = """
            INSERT INTO session_summaries
            (id, terminal_id, summary, keywords, project_path, timestamp)
            VALUES (?, ?, ?, ?, ?, ?);
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemoryError.insertFailed
        }

        sqlite3_bind_text(stmt, 1, (summary.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (summary.terminalID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (summary.summary as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (summary.keywords.joined(separator: ",") as NSString).utf8String, -1, nil)
        if let projectPath = summary.projectPath {
            sqlite3_bind_text(stmt, 5, (projectPath as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_double(stmt, 6, summary.timestamp.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            sqlite3_finalize(stmt)
            throw MemoryError.insertFailed
        }

        sqlite3_finalize(stmt)
    }

    func store(projectGoal: ForemanProjectGoal) throws {
        try open()

        let sql = """
            INSERT INTO project_goals
            (project_path, goal_text, status, updated_at, completed_at, last_evaluated_at, last_evidence_snapshot)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(project_path) DO UPDATE SET
                goal_text = excluded.goal_text,
                status = excluded.status,
                updated_at = excluded.updated_at,
                completed_at = excluded.completed_at,
                last_evaluated_at = excluded.last_evaluated_at,
                last_evidence_snapshot = excluded.last_evidence_snapshot;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemoryError.insertFailed
        }

        sqlite3_bind_text(stmt, 1, (projectGoal.projectID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (projectGoal.goalText as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (encodedStatus(projectGoal.status) as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 4, projectGoal.updatedAt.timeIntervalSince1970)

        if let completedAt = projectGoal.completedAt {
            sqlite3_bind_double(stmt, 5, completedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 5)
        }

        if let lastEvaluatedAt = projectGoal.lastEvaluatedAt {
            sqlite3_bind_double(stmt, 6, lastEvaluatedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        if let lastEvidenceSnapshot = projectGoal.lastEvidenceSnapshot {
            sqlite3_bind_text(stmt, 7, (lastEvidenceSnapshot as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            sqlite3_finalize(stmt)
            throw MemoryError.insertFailed
        }

        sqlite3_finalize(stmt)
    }

    func projectGoals() throws -> [ForemanProjectGoal] {
        try open()

        let sql = """
            SELECT project_path, goal_text, status, updated_at, completed_at, last_evaluated_at, last_evidence_snapshot
            FROM project_goals
            ORDER BY updated_at DESC;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemoryError.queryFailed
        }

        var goals: [ForemanProjectGoal] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let goal = rowToProjectGoal(stmt) {
                goals.append(goal)
            }
        }

        sqlite3_finalize(stmt)
        return goals
    }

    func deleteProjectGoal(for projectID: String) throws {
        try open()

        let sql = "DELETE FROM project_goals WHERE project_path = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemoryError.deleteFailed
        }

        sqlite3_bind_text(stmt, 1, (projectID as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func compactOldRecords(before: Date) throws {
        try open()

        let sql = "DELETE FROM situation_outcomes WHERE timestamp < ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemoryError.deleteFailed
        }
        sqlite3_bind_double(stmt, 1, before.timeIntervalSince1970)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        let summarySQL = "DELETE FROM session_summaries WHERE timestamp < ?;"
        guard sqlite3_prepare_v2(db, summarySQL, -1, &stmt, nil) == SQLITE_OK else {
            throw MemoryError.deleteFailed
        }
        sqlite3_bind_double(stmt, 1, before.timeIntervalSince1970)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    private func rowToRecord(_ stmt: OpaquePointer?) -> SituationOutcomeRecord? {
        guard let stmt = stmt else { return nil }

        guard let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let id = UUID(uuidString: idStr) else { return nil }

        let terminalID = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let fingerprint = Int(sqlite3_column_int64(stmt, 2))
        let cwd = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
        let action = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
        let outcomeRaw = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "unknown"
        let outcome = TerminalOutcome(rawValue: outcomeRaw) ?? .unknown
        let visibleText = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        let projectPath = sqlite3_column_text(stmt, 8).map { String(cString: $0) }

        return SituationOutcomeRecord(
            id: id,
            terminalID: terminalID,
            situationFingerprint: fingerprint,
            cwd: cwd,
            action: action,
            outcome: outcome,
            visibleText: visibleText,
            timestamp: timestamp,
            projectPath: projectPath
        )
    }

    private func rowToProjectGoal(_ stmt: OpaquePointer?) -> ForemanProjectGoal? {
        guard let stmt = stmt else { return nil }

        let projectPath = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        let goalText = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let statusRawValue = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "active"
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let completedAt = sqlite3_column_type(stmt, 4) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        let lastEvaluatedAt = sqlite3_column_type(stmt, 5) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        let lastEvidenceSnapshot = sqlite3_column_text(stmt, 6).map { String(cString: $0) }

        let status: ForemanProjectGoalStatus
        switch statusRawValue {
        case "paused":
            status = .paused
        case "complete", "completed":
            status = .completed
        default:
            status = .active
        }

        return ForemanProjectGoal(
            projectID: projectPath,
            objective: goalText,
            status: status,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            lastEvaluatedAt: lastEvaluatedAt,
            lastEvidenceSnapshot: lastEvidenceSnapshot
        )
    }

    private func encodedStatus(_ status: ForemanProjectGoalStatus) -> String {
        switch status {
        case .active:
            return "active"
        case .paused:
            return "paused"
        case .completed:
            return "completed"
        }
    }

    private func extractKeywords(from text: String) -> [String] {
        let lowercased = text.lowercased()
        let tokens = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let stopWords = Set(["the", "and", "for", "are", "but", "not", "you", "all", "can", "had", "her", "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "man", "new", "now", "old", "see", "two", "way", "who", "boy", "did", "its", "let", "put", "say", "she", "too", "use"])
        return tokens
            .filter { $0.count > 2 && !stopWords.contains($0) }
            .uniqued()
    }
}

enum MemoryError: Error {
    case openFailed
    case schemaFailed(String)
    case insertFailed
    case queryFailed
    case deleteFailed
}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
