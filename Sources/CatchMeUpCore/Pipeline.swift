import Foundation

/// Business logic: ingest → organize → store → schedule reminder → calendar.
@MainActor
public final class Pipeline {
    public let db: Database
    public let client: DeepSeekClient
    public let scheduler: ReminderScheduler
    public let calendar: CalendarService

    public init(db: Database,
                client: DeepSeekClient,
                scheduler: ReminderScheduler,
                calendar: CalendarService) {
        self.db = db
        self.client = client
        self.scheduler = scheduler
        self.calendar = calendar
    }

    // MARK: Ingest

    public struct IngestResult {
        public let item: Item
        public let tasks: [TaskItem]
    }

    @discardableResult
    public func ingest(_ ingested: Ingested,
                       hint: String? = nil,
                       intent: IngestIntent = .auto,
                       autoExtractTasks: Bool = true,
                       writeToCalendar: Bool? = nil) async throws -> IngestResult {
        // Resolve "auto" by input type so behavior is predictable:
        // folders/projects → hand-off; text/screenshot/url/file → task.
        let effectiveIntent = Self.resolveIntent(intent, kind: ingested.kind)

        let organized: OrganizedInput
        do {
            organized = try await client.organize(kind: ingested.kind,
                                                  content: ingested.rawContent,
                                                  hint: hint,
                                                  imageData: ingested.imageData,
                                                  intent: effectiveIntent)
        } catch {
            organized = OrganizedInput(summary: L.f("(整理失败：%@)", error.localizedDescription))
        }

        var metadata = ingested.metadata
        metadata["intent"] = effectiveIntent.rawValue
        if let handoff = organized.handoff {
            Self.applyHandoff(handoff, to: &metadata)
        }

        let item = Item(kind: ingested.kind,
                        title: organized.title ?? ingested.titleHint,
                        rawContent: ingested.rawContent,
                        summary: organized.summary,
                        tags: organized.tags,
                        category: organized.category,
                        metadata: metadata,
                        sourcePath: ingested.sourcePath)
        try db.insertItem(item)

        var created: [TaskItem] = []
        if autoExtractTasks {
            for extracted in organized.tasks {
                guard !extracted.title.isEmpty else { continue }
                let due = DateParser.parse(extracted.dueAtRaw)
                let priority = TaskPriority(rawValue: (extracted.priority ?? "normal").lowercased()) ?? .normal
                let task = try await createTask(title: extracted.title,
                                                detail: extracted.detail,
                                                priority: priority,
                                                dueAt: due,
                                                itemID: item.id,
                                                tags: organized.tags,
                                                writeToCalendar: writeToCalendar)
                created.append(task)
            }
        }
        return IngestResult(item: item, tasks: created)
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private static func applyHandoff(_ handoff: HandoffResult, to metadata: inout [String: String]) {
        metadata["handoff_goals"] = encodeStringArray(handoff.goals)
        metadata["handoff_logic"] = handoff.logic
        metadata["handoff_progress"] = handoff.progressSummary
        metadata["handoff_next_steps"] = encodeStringArray(handoff.nextSteps)
        metadata["handoff_risks"] = encodeStringArray(handoff.risks)
    }

    /// Resolve the `.auto` intent: a folder/project is a hand-off, everything else is a task.
    public nonisolated static func resolveIntent(_ intent: IngestIntent, kind: ItemKind) -> IngestIntent {
        guard intent == .auto else { return intent }
        return kind == .folder ? .handoff : .task
    }

    /// Re-read the source and re-run analysis for a single item (no confirmation).
    /// Updates the item fields/hand-off and adds any newly discovered tasks.
    @discardableResult
    public func refreshItem(for item: Item) async throws -> Item {
        var content = item.rawContent ?? ""
        var imageData: Data?

        switch item.kind {
        case .folder:
            if let root = item.metadata["root"], FileManager.default.fileExists(atPath: root),
               let fresh = try? Ingest.folder(root) {
                content = fresh.rawContent
            }
        case .file:
            if let path = item.sourcePath, FileManager.default.fileExists(atPath: path) {
                let text = Ingest.readTextFile(URL(fileURLWithPath: path))
                if !text.isEmpty { content = text }
            }
        case .screenshot:
            let path = item.sourcePath ?? item.metadata["stored_path"]
            if let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                imageData = data
                let ocr = OCR.recognizeText(imageData: data)
                if !ocr.isEmpty { content = ocr }
            }
        case .text, .url:
            break
        }

        let intent = IngestIntent(rawValue: item.metadata["intent"] ?? "")
            ?? (item.kind == .folder ? .handoff : .task)
        let organized = try await client.organize(kind: item.kind,
                                                  content: content,
                                                  hint: nil,
                                                  imageData: imageData,
                                                  intent: intent,
                                                  previousHandoff: item.handoff)

        var updated = item
        updated.updatedAt = Date()
        if let title = organized.title, !title.isEmpty { updated.title = title }
        if let summary = organized.summary, !summary.isEmpty { updated.summary = summary }
        if !organized.tags.isEmpty { updated.tags = organized.tags }
        if let category = organized.category, !category.isEmpty { updated.category = category }
        if let handoff = organized.handoff { Self.applyHandoff(handoff, to: &updated.metadata) }
        if !content.isEmpty { updated.rawContent = content }
        try db.updateItem(updated)

        let existingTitles = Set(try db.tasks(limit: 1000).filter { $0.itemID == item.id }.map { $0.title })
        for extracted in organized.tasks where !extracted.title.isEmpty {
            guard !existingTitles.contains(extracted.title) else { continue }
            let priority = TaskPriority(rawValue: (extracted.priority ?? "normal").lowercased()) ?? .normal
            _ = try await createTask(title: extracted.title,
                                     detail: extracted.detail,
                                     priority: priority,
                                     dueAt: DateParser.parse(extracted.dueAtRaw),
                                     itemID: item.id,
                                     tags: organized.tags)
        }
        return updated
    }

    /// Incrementally refresh a hand-off (continuous tracking). Re-reads the source
    /// folder/file when available and feeds the previous hand-off back to the model.
    @discardableResult
    public func refreshHandoff(for item: Item, extraContext: String? = nil) async throws -> Item {
        var content = item.rawContent ?? ""
        if item.kind == .folder, let root = item.metadata["root"],
           FileManager.default.fileExists(atPath: root),
           let fresh = try? Ingest.folder(root) {
            content = fresh.rawContent
        } else if let path = item.sourcePath, item.kind == .file,
                  FileManager.default.fileExists(atPath: path) {
            let text = Ingest.readTextFile(URL(fileURLWithPath: path))
            if !text.isEmpty { content = text }
        }

        let organized = try await client.organize(kind: item.kind,
                                                  content: content,
                                                  hint: extraContext,
                                                  imageData: nil,
                                                  intent: .handoff,
                                                  previousHandoff: item.handoff)

        var updated = item
        updated.updatedAt = Date()
        if let handoff = organized.handoff {
            Self.applyHandoff(handoff, to: &updated.metadata)
        }
        if let summary = organized.summary, !summary.isEmpty { updated.summary = summary }
        if let title = organized.title, !title.isEmpty { updated.title = title }
        if !content.isEmpty { updated.rawContent = content }
        try db.updateItem(updated)
        return updated
    }

    // MARK: TaskItem CRUD + scheduling

    @discardableResult
    public func createTask(title: String,
                           detail: String? = nil,
                           status: TaskStatus = .pending,
                           priority: TaskPriority = .normal,
                           dueAt: Date? = nil,
                           reminderAt: Date? = nil,
                           itemID: String? = nil,
                           tags: [String] = [],
                           recurrence: Recurrence = .none,
                           writeToCalendar: Bool? = nil) async throws -> TaskItem {
        var task = TaskItem(title: title, detail: detail, status: status, priority: priority,
                        dueAt: dueAt, reminderAt: reminderAt, itemID: itemID,
                        tags: tags, recurrence: recurrence)
        try db.insertTask(task)
        task = await applySideEffects(task, writeToCalendar: writeToCalendar)
        return task
    }

    @discardableResult
    public func updateTask(_ task: TaskItem, writeToCalendar: Bool? = nil) async throws -> TaskItem {
        var updated = task
        if updated.status == .done && updated.completedAt == nil { updated.completedAt = Date() }
        _ = try db.updateTask(updated)
        updated = await applySideEffects(updated, writeToCalendar: writeToCalendar)
        return updated
    }

    @discardableResult
    public func completeTask(_ task: TaskItem) async throws -> TaskItem {
        var updated = task
        updated.status = .done
        updated.completedAt = Date()
        scheduler.cancel(task: task)
        if Prefs.writeToCalendar || task.calendarEventID != nil {
            calendar.deleteEvent(identifier: task.calendarEventID)
            updated.calendarEventID = nil
        }
        updated.notificationID = nil
        _ = try db.updateTask(updated)
        return updated
    }

    public func deleteTask(_ task: TaskItem) throws {
        scheduler.cancel(task: task)
        calendar.deleteEvent(identifier: task.calendarEventID)
        try db.deleteTask(id: task.id)
    }

    @discardableResult
    public func deleteItem(_ item: Item) throws -> [TaskItem] {
        let linked = try db.tasks(limit: 1000).filter { $0.itemID == item.id }
        for task in linked { try deleteTask(task) }
        try db.deleteItem(id: item.id)
        return linked
    }

    private func applySideEffects(_ task: TaskItem, writeToCalendar: Bool?) async -> TaskItem {
        var updated = task
        if updated.isOpen, updated.dueAt != nil {
            if let nid = await scheduler.schedule(task: updated, leadMinutes: Prefs.reminderLeadMinutes) {
                updated.notificationID = nid
            }
        } else {
            scheduler.cancel(task: updated)
            updated.notificationID = nil
        }

        let shouldWriteCalendar = writeToCalendar ?? Prefs.writeToCalendar
        if updated.isOpen, shouldWriteCalendar, updated.dueAt != nil {
            if let eid = calendar.upsertEvent(for: updated, leadMinutes: Prefs.reminderLeadMinutes) {
                updated.calendarEventID = eid
            }
        } else if !shouldWriteCalendar || !updated.isOpen {
            if updated.calendarEventID != nil {
                calendar.deleteEvent(identifier: updated.calendarEventID)
                updated.calendarEventID = nil
            }
        }
        _ = try? db.updateTask(updated)
        return updated
    }

    // MARK: Handoff & sessions

    public func generateHandoff(extraContext: String? = nil) async throws -> HandoffResult {
        let items = try db.items(limit: 30)
        let tasks = try db.tasks(limit: 40)
        let sessions = try db.sessions(limit: 10)
        return try await client.generateHandoff(items: items, tasks: tasks,
                                                sessions: sessions, extraContext: extraContext)
    }

    @discardableResult
    public func startSession(topic: String?, extraContext: String? = nil) async throws -> Session {
        if let active = try db.activeSession() {
            let handoff = try? await generateHandoff(extraContext: extraContext)
            var closed = active
            closed.endedAt = Date()
            closed.summary = handoff?.progressSummary ?? "auto-handoff"
            closed.nextSteps = handoff?.nextSteps ?? []
            closed.status = .handed_off
            try db.updateSession(closed)
        }
        let session = Session(topic: topic)
        try db.insertSession(session)
        return session
    }

    @discardableResult
    public func endSession(_ session: Session, extraContext: String? = nil) async throws -> (Session, HandoffResult) {
        let handoff = (try? await generateHandoff(extraContext: extraContext))
            ?? HandoffResult(progressSummary: L.t("交接生成失败"))
        var closed = session
        closed.endedAt = Date()
        closed.summary = handoff.progressSummary
        closed.nextSteps = handoff.nextSteps
        closed.status = .handed_off
        try db.updateSession(closed)
        return (closed, handoff)
    }

    // MARK: Dashboard stats

    public struct Stats: Sendable {
        public var open: Int = 0
        public var overdue: Int = 0
        public var dueToday: Int = 0
        public var dueWeek: Int = 0
        public var items: Int = 0
        public init() {}
    }

    public func stats() throws -> Stats {
        try Self.stats(db: db)
    }

    /// Nonisolated so it can run off the main thread.
    public nonisolated static func stats(db: Database) throws -> Stats {
        let dueDates = try db.openTaskDueDates()
        let cal = Calendar.current
        var s = Stats()
        s.open = dueDates.count
        s.items = try db.countItems()
        let now = Date()
        let todayStart = now.startOfDay
        for due in dueDates {
            guard let due else { continue }
            if due < todayStart { s.overdue += 1 }
            if cal.isDateInToday(due) { s.dueToday += 1 }
            if let week = cal.date(byAdding: .day, value: 7, to: now), due <= week, due >= todayStart {
                s.dueWeek += 1
            }
        }
        return s
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}
