import XCTest
@testable import CatchMeUpCore

final class CoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Deterministic language for assertions.
        Prefs.followSystemLanguage = false
        Prefs.languageOverride = AppLanguage.zh.rawValue
    }

    // MARK: Localization

    func testLocalizationSwitching() {
        Prefs.followSystemLanguage = false
        Prefs.languageOverride = AppLanguage.en.rawValue
        XCTAssertEqual(L.t("工作台"), "Workspace")
        XCTAssertEqual(L.t("设置"), "Settings")

        Prefs.languageOverride = AppLanguage.ja.rawValue
        XCTAssertEqual(L.t("设置"), "設定")

        Prefs.languageOverride = AppLanguage.ko.rawValue
        XCTAssertEqual(L.t("设置"), "설정")

        Prefs.languageOverride = AppLanguage.es.rawValue
        XCTAssertEqual(L.t("设置"), "Ajustes")

        Prefs.languageOverride = AppLanguage.zh.rawValue
        XCTAssertEqual(L.t("工作台"), "工作台")

        // A missing key falls back to the Chinese source.
        XCTAssertEqual(L.t("不存在的键"), "不存在的键")
    }

    // MARK: JSON parsing

    func testJSONExtractorHandlesFencedJSON() {
        let raw = """
        ```json
        {"title":"周报","summary":"写周报","tags":["工作"],"category":"工作","tasks":[{"title":"提交周报","due_at":"2026-10-03T18:00:00","priority":"high"}]}
        ```
        """
        let parsed = JSONExtractor.decode(OrganizedInput.self, from: raw)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.title, "周报")
        XCTAssertEqual(parsed?.tasks.count, 1)
        XCTAssertEqual(parsed?.tasks.first?.title, "提交周报")
        XCTAssertEqual(parsed?.tasks.first?.priority, "high")
    }

    func testJSONExtractorHandlesProsePreamble() {
        let raw = "好的，这是结果：{\"progress_summary\":\"做完了 A\",\"next_steps\":[\"做 B\"],\"risks\":[]}"
        let parsed = JSONExtractor.decode(HandoffResult.self, from: raw)
        XCTAssertEqual(parsed?.progressSummary, "做完了 A")
        XCTAssertEqual(parsed?.nextSteps, ["做 B"])
    }

    func testJSONExtractorReturnsNilForGarbage() {
        XCTAssertNil(JSONExtractor.decode(OrganizedInput.self, from: "not json at all"))
    }

    // MARK: Date parsing

    func testDateParserParsesNaiveAsLocal() {
        let date = DateParser.parse("2026-10-03T18:00:00")
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 10)
        XCTAssertEqual(comps.day, 3)
        XCTAssertEqual(comps.hour, 18)
    }

    func testDateParserRejectsEmpty() {
        XCTAssertNil(DateParser.parse(""))
        XCTAssertNil(DateParser.parse(nil))
    }

    // MARK: Recurrence scheduling components

    func testReminderComponentsForDaily() {
        let date = DateParser.parse("2026-10-03T09:30:00")!
        let comps = ReminderScheduler.components(from: date, recurrence: .daily)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertNil(comps.year)
    }

    func testReminderComponentsForWeeklyHasWeekday() {
        let date = DateParser.parse("2026-10-03T09:30:00")!
        let comps = ReminderScheduler.components(from: date, recurrence: .weekly)
        XCTAssertNotNil(comps.weekday)
        XCTAssertEqual(comps.hour, 9)
    }

    // MARK: Database CRUD

    func makeDB() throws -> Database {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catchmeup-test-\(UUID().uuidString).db")
        return try Database(url: url)
    }

    func testItemRoundTrip() throws {
        let db = try makeDB()
        let item = Item(kind: .text, title: "标题", rawContent: "内容", summary: "摘要",
                        tags: ["a", "b"], category: "工作", metadata: ["length": "2"])
        try db.insertItem(item)
        let fetched = try db.item(id: item.id)
        XCTAssertEqual(fetched?.title, "标题")
        XCTAssertEqual(fetched?.tags, ["a", "b"])
        XCTAssertEqual(fetched?.metadata["length"], "2")
        XCTAssertEqual(try db.items().count, 1)
    }

    func testTaskRoundTripAndFiltering() throws {
        let db = try makeDB()
        let due = DateParser.parse("2026-10-03T18:00:00")!
        let task = TaskItem(title: "提交周报", detail: "别忘附件", priority: .high, dueAt: due,
                            tags: ["工作"], recurrence: .weekly)
        try db.insertTask(task)

        let fetched = try db.task(id: task.id)
        XCTAssertEqual(fetched?.priority, .high)
        XCTAssertEqual(fetched?.recurrence, .weekly)
        XCTAssertEqual(fetched?.tags, ["工作"])
        XCTAssertEqual(fetched?.dueAt?.timeIntervalSince1970 ?? 0, due.timeIntervalSince1970, accuracy: 0.001)

        var completed = fetched!
        completed.status = .done
        completed.completedAt = Date()
        try db.updateTask(completed)
        XCTAssertEqual(try db.tasks(includeCompleted: false).count, 0)
        XCTAssertEqual(try db.tasks(includeCompleted: true).count, 1)
        XCTAssertNotNil(try db.task(id: task.id)?.completedAt)
    }

    func testDeleteTask() throws {
        let db = try makeDB()
        let task = TaskItem(title: "临时")
        try db.insertTask(task)
        try db.deleteTask(id: task.id)
        XCTAssertNil(try db.task(id: task.id))
    }

    func testSessionLifecycle() throws {
        let db = try makeDB()
        var session = Session(topic: "重构")
        try db.insertSession(session)
        XCTAssertEqual(try db.activeSession()?.topic, "重构")
        session.status = .handed_off
        session.summary = "完成一半"
        session.nextSteps = ["继续"]
        session.endedAt = Date()
        try db.updateSession(session)
        XCTAssertNil(try db.activeSession())
        XCTAssertEqual(try db.sessions().first?.summary, "完成一半")
    }

    func testSettingKV() throws {
        let db = try makeDB()
        try db.setSetting("k", "v1")
        XCTAssertEqual(try db.getSetting("k"), "v1")
        try db.setSetting("k", "v2")
        XCTAssertEqual(try db.getSetting("k"), "v2")
    }

    // MARK: Ingest helpers

    func testIngestTextFirstLine() {
        let ingested = Ingest.text("第一行标题\n第二行内容")
        XCTAssertEqual(ingested.kind, .text)
        XCTAssertEqual(ingested.titleHint, "第一行标题")
    }

    func testFolderIngestBuildsTreeAndReadme() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catchmeup-folder-\(UUID().uuidString)")
        let sub = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "# 项目标题\n这是说明文档".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "print('hello')\n入口文件".write(to: sub.appendingPathComponent("main.py"), atomically: true, encoding: .utf8)
        try Data(repeating: 7, count: 2048).write(to: dir.appendingPathComponent("logo.png"))

        let ingested = try Ingest.folder(dir.path)
        XCTAssertTrue(ingested.rawContent.contains("# README"), "有 README 时应包含 README 栏目")
        XCTAssertTrue(ingested.rawContent.contains("项目标题"))
        XCTAssertTrue(ingested.rawContent.contains("# 目录结构"))
        XCTAssertTrue(ingested.rawContent.contains("main.py"))
        XCTAssertTrue(ingested.rawContent.contains("src/"))
        XCTAssertEqual(ingested.metadata["has_readme"], "true")
        XCTAssertEqual(ingested.kind, .folder)
    }

    func testFolderIngestOmitsReadmeWhenAbsent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catchmeup-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "内容".write(to: dir.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let ingested = try Ingest.folder(dir.path)
        XCTAssertFalse(ingested.rawContent.contains("# README"), "没有 README 时不应出现该栏目")
        XCTAssertEqual(ingested.metadata["has_readme"], "false")
        XCTAssertTrue(ingested.rawContent.contains("note.txt"))
    }

    func testExtractedTaskDecodingKeys() throws {
        let json = #"{"title":"做X","due_at":"2026-10-03T18:00:00","description":"细节","priority":"urgent"}"#
        let task = try JSONDecoder().decode(ExtractedTask.self, from: Data(json.utf8))
        XCTAssertEqual(task.title, "做X")
        XCTAssertEqual(task.dueAtRaw, "2026-10-03T18:00:00")
        XCTAssertEqual(task.detail, "细节")
        XCTAssertEqual(task.priority, "urgent")
    }

    // MARK: Two-mode organizer schema

    func testOrganizedInputDecodesHandoff() {
        let json = """
        {"title":"项目X","summary":"解析层收尾","tags":["项目"],"category":"项目","tasks":[],
         "handoff":{"goals":["按时交付"],"logic":"先解析再渲染","progress_summary":"完成解析层","next_steps":["接前端"],"risks":[]}}
        """
        let parsed = JSONExtractor.decode(OrganizedInput.self, from: json)
        XCTAssertEqual(parsed?.handoff?.goals, ["按时交付"])
        XCTAssertEqual(parsed?.handoff?.logic, "先解析再渲染")
        XCTAssertEqual(parsed?.handoff?.progressSummary, "完成解析层")
        XCTAssertEqual(parsed?.handoff?.nextSteps, ["接前端"])
    }

    func testHandoffTolerantDecoding() {
        // Old-style payload without goals/logic must still decode.
        let json = #"{"progress_summary":"做完了 A","next_steps":["做 B"],"risks":[]}"#
        let parsed = JSONExtractor.decode(HandoffResult.self, from: json)
        XCTAssertEqual(parsed?.progressSummary, "做完了 A")
        XCTAssertEqual(parsed?.goals, [])
        XCTAssertEqual(parsed?.logic, "")
    }

    func testItemHandoffFromMetadata() {
        let item = Item(kind: .folder, title: "项目X", metadata: [
            "handoff_goals": "[\"按时交付\"]",
            "handoff_logic": "先解析再渲染",
            "handoff_progress": "完成解析层",
            "handoff_next_steps": "[\"接前端\"]",
            "handoff_risks": "[]"
        ])
        XCTAssertEqual(item.handoff?.goals, ["按时交付"])
        XCTAssertEqual(item.handoff?.logic, "先解析再渲染")
        XCTAssertEqual(item.handoff?.nextSteps, ["接前端"])
    }

    func testIngestIntentLabels() {
        XCTAssertEqual(IngestIntent.handoff.label, "交接")
        XCTAssertEqual(IngestIntent.task.label, "任务")
        XCTAssertEqual(IngestIntent.allCases.count, 3)
    }

    func testResolveIntentDefaults() {
        // 自动：目录 → 交接；文本/截图等 → 任务
        XCTAssertEqual(Pipeline.resolveIntent(.auto, kind: .folder), .handoff)
        XCTAssertEqual(Pipeline.resolveIntent(.auto, kind: .text), .task)
        XCTAssertEqual(Pipeline.resolveIntent(.auto, kind: .screenshot), .task)
        XCTAssertEqual(Pipeline.resolveIntent(.auto, kind: .url), .task)
        XCTAssertEqual(Pipeline.resolveIntent(.auto, kind: .file), .task)
        // 显式选择不被覆盖
        XCTAssertEqual(Pipeline.resolveIntent(.task, kind: .folder), .task)
        XCTAssertEqual(Pipeline.resolveIntent(.handoff, kind: .text), .handoff)
    }

    func testStatsCountOverdue() throws {
        let db = try makeDB()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        try db.insertTask(TaskItem(title: "过期", dueAt: yesterday))
        try db.insertTask(TaskItem(title: "今天晚些", dueAt: Date().addingTimeInterval(3600)))
        try db.insertTask(TaskItem(title: "无日期"))
        let stats = try Pipeline.stats(db: db)
        XCTAssertEqual(stats.open, 3)
        XCTAssertEqual(stats.overdue, 1)
        XCTAssertEqual(stats.dueToday, 1)
    }

    func testUsageTrackerAccumulatesAndResets() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catchmeup-usage-\(UUID().uuidString)")
        UsageTracker.directoryOverride = dir
        defer {
            try? FileManager.default.removeItem(at: dir)
            UsageTracker.directoryOverride = nil
        }
        let tracker = UsageTracker.shared
        tracker.reset()
        tracker.record(prompt: 10, completion: 5, total: 15, model: "deepseek-flash")
        tracker.record(prompt: 2, completion: 3, total: 5, model: "deepseek-v4-pro")
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.total.requests, 2)
        XCTAssertEqual(snap.total.promptTokens, 12)
        XCTAssertEqual(snap.total.completionTokens, 8)
        XCTAssertEqual(snap.total.totalTokens, 20)
        XCTAssertEqual(snap.byModel["deepseek-flash"]?.totalTokens, 15)
        XCTAssertEqual(snap.byModel["deepseek-v4-pro"]?.totalTokens, 5)
        tracker.reset()
        XCTAssertEqual(tracker.snapshot().total.requests, 0)
    }

    func testSecretStoreRoundTrip() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catchmeup-secrets-\(UUID().uuidString)")
        SecretStore.directoryOverride = dir
        defer {
            try? FileManager.default.removeItem(at: dir)
            SecretStore.directoryOverride = nil
        }
        XCTAssertNil(SecretStore.string("deepseek_api_key"))
        Prefs.setAPIKey("sk-test-123")
        XCTAssertEqual(SecretStore.string("deepseek_api_key"), "sk-test-123")
        Prefs.setAPIKey("")
        XCTAssertNil(SecretStore.string("deepseek_api_key"))
    }

    func testCustomPromptOverrideFallsBackWhenBlank() {
        let custom = DeepSeekClient(apiKey: "x", organizerPrompt: "   ", handoffPrompt: "自定义交接")
        XCTAssertEqual(custom.resolvedOrganizerSystem, L.organizerSystem)
        XCTAssertEqual(custom.resolvedHandoffSystem, "自定义交接")

        let defaults = DeepSeekClient(apiKey: "x")
        XCTAssertEqual(defaults.resolvedOrganizerSystem, L.organizerSystem)
        XCTAssertEqual(defaults.resolvedHandoffSystem, L.handoffSystem)
    }

    // MARK: Live DeepSeek (only when DEEPSEEK_API_KEY is set)

    func testLiveConnection() async throws {
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty else {
            throw XCTSkip("DEEPSEEK_API_KEY not set; skipping live test")
        }
        let client = DeepSeekClient(apiKey: key, model: "deepseek-flash")
        let reply = try await client.chat([.user("只回复两个字：正常")],
                                          temperature: 0, maxTokens: 512,
                                          jsonMode: false, attempts: 2)
        XCTAssertFalse(reply.isEmpty, "DeepSeek 返回了空响应")
    }

    func testLiveOrganize() async throws {
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty else {
            throw XCTSkip("DEEPSEEK_API_KEY not set; skipping live test")
        }
        let client = DeepSeekClient(apiKey: key, model: "deepseek-flash")
        let result = try await client.organize(kind: .text,
                                               content: "明天下午三点跟 Alice 开会前，把 Q3 报告写完",
                                               hint: nil, imageData: nil)
        XCTAssertNotNil(result.title)
        XCTAssertFalse(result.tasks.isEmpty)
    }
}
