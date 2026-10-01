import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum AppPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("CatchMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var databaseURL: URL { supportDirectory.appendingPathComponent("catchmeup.db") }
    public static var storageDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("storage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

public enum SQLValue: Sendable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)

    public var stringValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }
    public var intValue: Int64? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int64(d)
        default: return nil
        }
    }
    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }
    public var boolValue: Bool? {
        guard let i = intValue else { return nil }
        return i != 0
    }
}

public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.catchmeup.db")

    public init(url: URL = AppPaths.databaseURL) throws {
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw CatchMeUpError.ingest(L.f("无法打开数据库：%@", msg))
        }
        try exec("PRAGMA foreign_keys = ON;")
        try migrate()
    }

    deinit { sqlite3_close(handle) }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            title TEXT,
            raw_content TEXT,
            summary TEXT,
            tags TEXT,
            category TEXT,
            metadata TEXT,
            source_path TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            priority TEXT NOT NULL DEFAULT 'normal',
            due_at REAL,
            reminder_at REAL,
            notification_id TEXT,
            calendar_event_id TEXT,
            item_id TEXT,
            tags TEXT,
            recurrence TEXT DEFAULT 'none',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            completed_at REAL
        );
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            topic TEXT,
            started_at REAL NOT NULL,
            ended_at REAL,
            summary TEXT,
            next_steps TEXT,
            status TEXT NOT NULL DEFAULT 'active'
        );
        CREATE TABLE IF NOT EXISTS reminders_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT,
            fired_at REAL NOT NULL,
            delivered INTEGER NOT NULL DEFAULT 0,
            error TEXT
        );
        CREATE TABLE IF NOT EXISTS settings_kv (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_items_kind ON items(kind);
        CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
        CREATE INDEX IF NOT EXISTS idx_tasks_due_at ON tasks(due_at);
        CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);
        """)
    }

    // MARK: - Low level

    public func exec(_ sql: String) throws {
        try queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? "exec failed"
                sqlite3_free(err)
                throw CatchMeUpError.ingest(msg)
            }
        }
    }

    @discardableResult
    public func run(_ sql: String, _ params: [SQLValue] = []) throws -> Int {
        try queue.sync {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, params)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw CatchMeUpError.ingest(String(cString: sqlite3_errmsg(handle)))
            }
            return Int(sqlite3_changes(handle))
        }
    }

    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[String: SQLValue]] {
        try queue.sync {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, params)
            var rows: [[String: SQLValue]] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: SQLValue] = [:]
                for i in 0..<sqlite3_column_count(stmt) {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    row[name] = column(stmt, Int32(i))
                }
                rows.append(row)
            }
            return rows
        }
    }

    public func lastInsertRowID() -> Int64 { sqlite3_last_insert_rowid(handle) }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw CatchMeUpError.ingest(String(cString: sqlite3_errmsg(handle)))
        }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer, _ params: [SQLValue]) throws {
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, SQLITE_TRANSIENT)
            }
        }
    }

    private func column(_ stmt: OpaquePointer, _ idx: Int32) -> SQLValue {
        switch sqlite3_column_type(stmt, idx) {
        case SQLITE_INTEGER: return .int(sqlite3_column_int64(stmt, idx))
        case SQLITE_FLOAT: return .double(sqlite3_column_double(stmt, idx))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(stmt, idx)))
        case SQLITE_NULL: return .null
        default: return .null
        }
    }
}

// MARK: - Typed accessors

extension Database {
    private static func encodedJSON(_ values: [String]) -> String {
        (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    private static func decodeJSONArray(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }
    private static func decodeJSONDict(_ raw: String?) -> [String: String] {
        guard let raw, let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private func date(_ v: SQLValue?) -> Date? {
        guard let ts = v?.doubleValue, ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    // MARK: Items

    @discardableResult
    public func insertItem(_ item: Item) throws -> Item {
        try run("""
        INSERT INTO items (id, kind, title, raw_content, summary, tags, category, metadata,
                           source_path, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(item.id), .text(item.kind.rawValue), .text(item.title ?? ""),
            .text(item.rawContent ?? ""), .text(item.summary ?? ""),
            .text(Self.encodedJSON(item.tags)), .text(item.category ?? ""),
            .text((try? JSONEncoder().encode(item.metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"),
            .text(item.sourcePath ?? ""),
            .double(item.createdAt.timeIntervalSince1970), .double(item.updatedAt.timeIntervalSince1970)
        ])
        return item
    }

    public func item(id: String) throws -> Item? {
        try query("SELECT * FROM items WHERE id = ?", [.text(id)]).first.map(mapItem)
    }

    public func updateItem(_ item: Item) throws {
        try run("""
        UPDATE items SET kind = ?, title = ?, raw_content = ?, summary = ?, tags = ?,
                         category = ?, metadata = ?, source_path = ?, updated_at = ?
        WHERE id = ?
        """, [
            .text(item.kind.rawValue), .text(item.title ?? ""), .text(item.rawContent ?? ""),
            .text(item.summary ?? ""), .text(Self.encodedJSON(item.tags)),
            .text(item.category ?? ""),
            .text((try? JSONEncoder().encode(item.metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"),
            .text(item.sourcePath ?? ""),
            .double(Date().timeIntervalSince1970),
            .text(item.id)
        ])
    }

    public func items(kind: ItemKind? = nil, search: String? = nil, limit: Int = 200) throws -> [Item] {
        var sql = "SELECT * FROM items"
        var clauses: [String] = []
        var params: [SQLValue] = []
        if let kind { clauses.append("kind = ?"); params.append(.text(kind.rawValue)) }
        if let search, !search.isEmpty {
            clauses.append("(title LIKE ? OR summary LIKE ? OR raw_content LIKE ?)")
            let s = SQLValue.text("%\(search)%"); params.append(s); params.append(s); params.append(s)
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY created_at DESC LIMIT ?"
        params.append(.int(Int64(limit)))
        return try query(sql, params).map(mapItem)
    }

    public func deleteItem(id: String) throws { try run("DELETE FROM items WHERE id = ?", [.text(id)]) }

    /// Lightweight list query that does NOT load `raw_content` (avoids UI lag on large folders/files).
    public func itemSummaries(kind: ItemKind? = nil, limit: Int = 500) throws -> [Item] {
        var sql = """
        SELECT id, kind, title, summary, tags, category, metadata, source_path, created_at, updated_at
        FROM items
        """
        var params: [SQLValue] = []
        if let kind { sql += " WHERE kind = ?"; params.append(.text(kind.rawValue)) }
        sql += " ORDER BY created_at DESC LIMIT ?"
        params.append(.int(Int64(limit)))
        return try query(sql, params).map(mapItem)
    }

    public func countItems() throws -> Int {
        Int(try query("SELECT COUNT(*) AS c FROM items").first?["c"]?.intValue ?? 0)
    }

    public func openTaskDueDates() throws -> [Date?] {
        try query("SELECT due_at FROM tasks WHERE status NOT IN ('done', 'cancelled')").map { date($0["due_at"]) }
    }

    private func mapItem(_ row: [String: SQLValue]) -> Item {
        Item(id: row["id"]?.stringValue ?? UUID().uuidString,
             kind: ItemKind(rawValue: row["kind"]?.stringValue ?? "text") ?? .text,
             title: row["title"]?.stringValue,
             rawContent: row["raw_content"]?.stringValue,
             summary: row["summary"]?.stringValue,
             tags: Self.decodeJSONArray(row["tags"]?.stringValue),
             category: row["category"]?.stringValue?.isEmpty == true ? nil : row["category"]?.stringValue,
             metadata: Self.decodeJSONDict(row["metadata"]?.stringValue),
             sourcePath: row["source_path"]?.stringValue?.isEmpty == true ? nil : row["source_path"]?.stringValue,
             createdAt: date(row["created_at"]) ?? Date(),
             updatedAt: date(row["updated_at"]) ?? Date())
    }

    // MARK: Tasks

    @discardableResult
    public func insertTask(_ task: TaskItem) throws -> TaskItem {
        try run("""
        INSERT INTO tasks (id, title, description, status, priority, due_at, reminder_at,
                           notification_id, calendar_event_id, item_id, tags, recurrence,
                           created_at, updated_at, completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, taskParams(task))
        return task
    }

    public func updateTask(_ task: TaskItem) throws -> TaskItem {
        var updated = task
        updated.updatedAt = Date()
        try run("""
        UPDATE tasks SET title = ?, description = ?, status = ?, priority = ?, due_at = ?,
                         reminder_at = ?, notification_id = ?, calendar_event_id = ?, item_id = ?,
                         tags = ?, recurrence = ?, created_at = ?, updated_at = ?, completed_at = ?
        WHERE id = ?
        """, Array(taskParams(updated).dropFirst()) + [.text(updated.id)])
        return updated
    }

    private func taskParams(_ t: TaskItem) -> [SQLValue] {
        [
            .text(t.id), .text(t.title), .text(t.detail ?? ""), .text(t.status.rawValue),
            .text(t.priority.rawValue),
            t.dueAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            t.reminderAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .text(t.notificationID ?? ""), .text(t.calendarEventID ?? ""), .text(t.itemID ?? ""),
            .text(Self.encodedJSON(t.tags)), .text(t.recurrence.rawValue),
            .double(t.createdAt.timeIntervalSince1970), .double(t.updatedAt.timeIntervalSince1970),
            t.completedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }

    public func task(id: String) throws -> TaskItem? {
        try query("SELECT * FROM tasks WHERE id = ?", [.text(id)]).first.map(mapTask)
    }

    public func tasks(status: TaskStatus? = nil,
                      includeCompleted: Bool = true,
                      search: String? = nil,
                      limit: Int = 300) throws -> [TaskItem] {
        var sql = "SELECT * FROM tasks"
        var clauses: [String] = []
        var params: [SQLValue] = []
        if let status {
            clauses.append("status = ?"); params.append(.text(status.rawValue))
        } else if !includeCompleted {
            clauses.append("status != 'done' AND status != 'cancelled'")
        }
        if let search, !search.isEmpty {
            clauses.append("(title LIKE ? OR description LIKE ?)")
            params.append(.text("%\(search)%")); params.append(.text("%\(search)%"))
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY COALESCE(due_at, 9999999999) ASC, created_at DESC LIMIT ?"
        params.append(.int(Int64(limit)))
        return try query(sql, params).map(mapTask)
    }

    public func deleteTask(id: String) throws { try run("DELETE FROM tasks WHERE id = ?", [.text(id)]) }

    private func mapTask(_ row: [String: SQLValue]) -> TaskItem {
        TaskItem(id: row["id"]?.stringValue ?? UUID().uuidString,
             title: row["title"]?.stringValue ?? "",
             detail: row["description"]?.stringValue?.isEmpty == true ? nil : row["description"]?.stringValue,
             status: TaskStatus(rawValue: row["status"]?.stringValue ?? "pending") ?? .pending,
             priority: TaskPriority(rawValue: row["priority"]?.stringValue ?? "normal") ?? .normal,
             dueAt: date(row["due_at"]),
             reminderAt: date(row["reminder_at"]),
             notificationID: row["notification_id"]?.stringValue?.isEmpty == true ? nil : row["notification_id"]?.stringValue,
             calendarEventID: row["calendar_event_id"]?.stringValue?.isEmpty == true ? nil : row["calendar_event_id"]?.stringValue,
             itemID: row["item_id"]?.stringValue?.isEmpty == true ? nil : row["item_id"]?.stringValue,
             tags: Self.decodeJSONArray(row["tags"]?.stringValue),
             recurrence: Recurrence(rawValue: row["recurrence"]?.stringValue ?? "none") ?? .none,
             createdAt: date(row["created_at"]) ?? Date(),
             updatedAt: date(row["updated_at"]) ?? Date(),
             completedAt: date(row["completed_at"]))
    }

    // MARK: Sessions

    @discardableResult
    public func insertSession(_ s: Session) throws -> Session {
        try run("INSERT INTO sessions (id, topic, started_at, ended_at, summary, next_steps, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [.text(s.id), .text(s.topic ?? ""),
                 .double(s.startedAt.timeIntervalSince1970),
                 s.endedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                 .text(s.summary ?? ""), .text(Self.encodedJSON(s.nextSteps)),
                 .text(s.status.rawValue)])
        return s
    }

    public func updateSession(_ s: Session) throws {
        try run("UPDATE sessions SET topic = ?, ended_at = ?, summary = ?, next_steps = ?, status = ? WHERE id = ?",
                [.text(s.topic ?? ""),
                 s.endedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                 .text(s.summary ?? ""), .text(Self.encodedJSON(s.nextSteps)),
                 .text(s.status.rawValue), .text(s.id)])
    }

    public func activeSession() throws -> Session? {
        try query("SELECT * FROM sessions WHERE status = 'active' ORDER BY started_at DESC LIMIT 1").first.map(mapSession)
    }

    public func sessions(limit: Int = 50) throws -> [Session] {
        try query("SELECT * FROM sessions ORDER BY started_at DESC LIMIT ?", [.int(Int64(limit))]).map(mapSession)
    }

    private func mapSession(_ row: [String: SQLValue]) -> Session {
        Session(id: row["id"]?.stringValue ?? UUID().uuidString,
                topic: row["topic"]?.stringValue?.isEmpty == true ? nil : row["topic"]?.stringValue,
                startedAt: date(row["started_at"]) ?? Date(),
                endedAt: date(row["ended_at"]),
                summary: row["summary"]?.stringValue?.isEmpty == true ? nil : row["summary"]?.stringValue,
                nextSteps: Self.decodeJSONArray(row["next_steps"]?.stringValue),
                status: SessionStatus(rawValue: row["status"]?.stringValue ?? "active") ?? .active)
    }

    // MARK: Reminder log

    public func logReminder(taskID: String?, delivered: Bool, error: String?) throws {
        try run("INSERT INTO reminders_log (task_id, fired_at, delivered, error) VALUES (?, ?, ?, ?)",
                [.text(taskID ?? ""), .double(Date().timeIntervalSince1970), .int(delivered ? 1 : 0), .text(error ?? "")])
    }

    // MARK: Settings KV

    public func setSetting(_ key: String, _ value: String) throws {
        try run("INSERT INTO settings_kv (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
                [.text(key), .text(value), .double(Date().timeIntervalSince1970)])
    }

    public func getSetting(_ key: String) throws -> String? {
        try query("SELECT value FROM settings_kv WHERE key = ?", [.text(key)]).first?["value"]?.stringValue
    }
}
