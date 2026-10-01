import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications
import EventKit
import CatchMeUpCore

@MainActor
final class AppStore: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case workspace, tasks, handoff, calendar, jobs, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .workspace: return L.t("工作台")
            case .tasks: return L.t("任务")
            case .handoff: return L.t("任务交接")
            case .calendar: return L.t("日历")
            case .jobs: return L.t("定时任务")
            case .settings: return L.t("设置")
            }
        }
        var icon: String {
            switch self {
            case .workspace: return "square.and.pencil"
            case .tasks: return "checklist"
            case .handoff: return "arrow.left.arrow.right"
            case .calendar: return "calendar"
            case .jobs: return "clock.badge"
            case .settings: return "gearshape"
            }
        }
    }

    // Published state
    @Published var selection: Section = .workspace
    @Published var items: [Item] = []
    @Published var tasks: [TaskItem] = []
    @Published var sessions: [Session] = []
    @Published var activeSession: Session?
    @Published var stats = Pipeline.Stats()
    @Published var pendingRequests: [UNNotificationRequest] = []
    @Published var calendarEvents: [EKEventSummary] = []
    @Published var usage = UsageStats()
    @Published var handoff: HandoffResult?
    @Published var isBusy = false
    @Published var statusMessage: String?

    @Published var errorMessage: String? {
        didSet {
            guard errorMessage != nil else { errorToken = nil; return }
            let token = UUID()
            errorToken = token
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard let self, self.errorToken == token else { return }
                self.errorMessage = nil
            }
        }
    }
    private var errorToken: UUID?

    // Filter state (client-side, so typing never hits the database)
    @Published var itemSearch = ""
    @Published var itemKindFilter: ItemKind?
    @Published var taskSearch = ""
    @Published var taskShowCompleted = false

    // Settings
    @Published var apiKeyInput = ""
    @Published var modelInput = Prefs.model
    @Published var baseURLInput = Prefs.baseURL
    @Published var reminderLeadInput = Prefs.reminderLeadMinutes
    @Published var writeToCalendarInput = Prefs.writeToCalendar
    @Published var organizerPromptInput = Prefs.organizerPrompt
    @Published var handoffPromptInput = Prefs.handoffPrompt
    @Published var notificationsAuthorized = false
    @Published var calendarAuthorized = false
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var calendarStatus: EKAuthorizationStatus = .notDetermined
    @Published var screenRecordingGranted = false
    @Published var language: AppLanguage = Prefs.language
    @Published var followSystemLanguage: Bool = Prefs.followSystemLanguage

    let db: Database
    private let scheduler = ReminderScheduler.shared
    private let calendar = CalendarService.shared

    init() {
        do {
            db = try Database()
        } catch {
            fatalError(L.f("无法初始化数据库：%@", "\(error)"))
        }
        scheduler.installDelegate()
        apiKeyInput = Prefs.apiKey ?? ""
        Task { await bootstrap() }
    }

    var client: DeepSeekClient {
        DeepSeekClient(apiKey: Prefs.apiKey ?? "",
                       baseURL: URL(string: Prefs.baseURL) ?? URL(string: "https://api.deepseek.com")!,
                       model: Prefs.model,
                       organizerPrompt: Prefs.organizerPrompt,
                       handoffPrompt: Prefs.handoffPrompt)
    }

    private var pipeline: Pipeline {
        Pipeline(db: db, client: client, scheduler: scheduler, calendar: calendar)
    }

    // MARK: Lifecycle

    func bootstrap() async {
        registerGlobalHotKey()
        await refreshAuthorization()
        await refresh()
    }

    @discardableResult
    private func registerGlobalHotKey() -> Bool {
        GlobalHotKey.shared.register(keyCode: UInt32(Prefs.screenshotKeyCode),
                                     modifiers: UInt32(Prefs.screenshotModifiers)) { [weak self] in
            Task { @MainActor in await self?.hotKeyScreenshot() }
        }
    }

    var screenshotHotKeyDisplay: String {
        GlobalHotKey.displayString(keyCode: UInt32(Prefs.screenshotKeyCode),
                                   modifiers: UInt32(Prefs.screenshotModifiers))
    }

    /// Set a new screenshot hotkey; reverts if the combo is already taken.
    func updateScreenshotHotKey(keyCode: UInt32, modifiers: UInt32) {
        let oldCode = Prefs.screenshotKeyCode
        let oldModifiers = Prefs.screenshotModifiers
        Prefs.screenshotKeyCode = Int(keyCode)
        Prefs.screenshotModifiers = Int(modifiers)
        if registerGlobalHotKey() {
            setStatus(L.f("截图快捷键已更新为 %@", screenshotHotKeyDisplay))
        } else {
            Prefs.screenshotKeyCode = oldCode
            Prefs.screenshotModifiers = oldModifiers
            _ = registerGlobalHotKey()
            errorMessage = L.t("该快捷键可能已被其它 App 占用，已保留原设置")
        }
    }

    func resetScreenshotHotKey() {
        Prefs.screenshotKeyCode = Int(GlobalHotKey.defaultSpec.keyCode)
        Prefs.screenshotModifiers = Int(GlobalHotKey.defaultSpec.modifiers)
        _ = registerGlobalHotKey()
        setStatus(L.f("截图快捷键已恢复默认（%@）", screenshotHotKeyDisplay))
    }

    /// ⌘⇧M: interactive screenshot → bring the app to front → insert and analyze.
    func hotKeyScreenshot() async {
        await captureInteractiveScreenshot(intent: .auto, activateApp: true)
    }

    func refreshAuthorization() async {
        // Read-only status checks. Never triggers a system prompt.
        let notif = await scheduler.authorizationStatus()
        notificationStatus = notif
        notificationsAuthorized = notif == .authorized

        let cal = EKEventStore.authorizationStatus(for: .event)
        calendarStatus = cal
        calendarAuthorized = cal == .fullAccess

        screenRecordingGranted = ScreenRecording.granted
    }

    private struct Loaded: Sendable {
        var items: [Item]
        var tasks: [TaskItem]
        var sessions: [Session]
        var active: Session?
        var stats: Pipeline.Stats
    }

    func refresh() async {
        let db = self.db
        let includeCompleted = taskShowCompleted
        let loaded: Loaded? = await Task.detached(priority: .userInitiated) {
            do {
                return Loaded(items: try db.itemSummaries(limit: 500),
                              tasks: try db.tasks(includeCompleted: includeCompleted, limit: 500),
                              sessions: try db.sessions(),
                              active: try db.activeSession(),
                              stats: try Pipeline.stats(db: db))
            } catch {
                return nil
            }
        }.value

        if let loaded {
            items = loaded.items
            tasks = loaded.tasks
            sessions = loaded.sessions
            activeSession = loaded.active
            stats = loaded.stats
        }
        pendingRequests = await scheduler.pendingRequests()
        calendarEvents = calendar.upcomingEvents(days: 30).map { EKEventSummary($0) }
        usage = UsageTracker.shared.snapshot()
    }

    func resetUsage() {
        UsageTracker.shared.reset()
        usage = UsageTracker.shared.snapshot()
        setStatus(L.t("已重置 Token 统计"))
    }

    func fullItem(id: String) async -> Item? {
        let db = self.db
        return await Task.detached { try? db.item(id: id) }.value
    }

    // MARK: Item relationships

    func tasks(for itemID: String) -> [TaskItem] {
        tasks.filter { $0.itemID == itemID }
    }

    func item(id: String) -> Item? {
        items.first { $0.id == id }
    }

    var itemsWithTasks: [Item] {
        let ids = Set(tasks.compactMap { $0.itemID })
        return items.filter { ids.contains($0.id) }
    }

    var handoffItems: [Item] {
        items.filter { $0.handoff != nil }
    }

    var standaloneTasks: [TaskItem] {
        tasks.filter { $0.itemID == nil }
    }

    func setStatus(_ message: String?) {
        statusMessage = message
        if message != nil {
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if statusMessage == message { statusMessage = nil }
            }
        }
    }

    // MARK: Unified capture

    /// Route a single input box: empty → clipboard, URL → web, existing path → file/folder, else text.
    func submit(_ raw: String, intent: IngestIntent, hint: String? = nil) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            await submitClipboard(intent: intent, hint: hint)
            return
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), url.host != nil, !text.contains("\n") {
            await captureURL(text, hint: hint, intent: intent)
            return
        }
        let expanded = (text as NSString).expandingTildeInPath
        if !text.contains("\n"), FileManager.default.fileExists(atPath: expanded) {
            await capturePath(expanded, hint: hint, intent: intent)
            return
        }
        await captureText(text, hint: hint, intent: intent)
    }

    func submitClipboard(intent: IngestIntent, hint: String? = nil) async {
        if let png = Self.clipboardPNG() {
            await captureImage(data: png, name: "clipboard.png", hint: hint, intent: intent)
            return
        }
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            await capturePath(first.path, hint: hint, intent: intent)
            return
        }
        if let string = pb.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await submit(string, intent: intent, hint: hint)
            return
        }
        errorMessage = L.t("剪贴板里没有可识别的内容")
    }

    func captureText(_ text: String, hint: String?, intent: IngestIntent = .task) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await run(L.t("正在整理文本…")) {
            let result = try await self.pipeline.ingest(Ingest.text(trimmed), hint: hint,
                                                        intent: intent, autoExtractTasks: true)
            self.report(result)
        }
    }

    func captureURL(_ urlString: String, hint: String?, intent: IngestIntent = .task) async {
        guard !urlString.isEmpty else { return }
        await run(L.t("正在抓取网页…")) {
            let ingested = try await Ingest.url(urlString)
            let result = try await self.pipeline.ingest(ingested, hint: hint,
                                                        intent: intent, autoExtractTasks: true)
            self.report(result)
        }
    }

    func capturePath(_ path: String, hint: String?, intent: IngestIntent = .auto) async {
        guard !path.isEmpty else { return }
        await run(L.t("正在读取…")) {
            let expanded = (path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) else {
                throw CatchMeUpError.ingest(L.f("路径不存在：%@", path))
            }
            let ingested: Ingested
            if isDir.boolValue {
                ingested = try Ingest.folder(expanded)
            } else if Ingest.imageExtensions.contains((expanded as NSString).pathExtension.lowercased()) {
                ingested = try Ingest.screenshot(path: expanded)
            } else {
                ingested = try Ingest.file(expanded)
            }
            // Pipeline resolves .auto: folders → hand-off, everything else → task.
            let result = try await self.pipeline.ingest(ingested, hint: hint,
                                                        intent: intent, autoExtractTasks: true)
            self.report(result)
        }
    }

    func captureImage(data: Data, name: String, hint: String?, intent: IngestIntent = .auto) async {
        await run(L.t("正在识别图片…")) {
            let ingested = try Ingest.screenshot(imageData: data, originalName: name)
            let result = try await self.pipeline.ingest(ingested, hint: hint,
                                                        intent: intent, autoExtractTasks: true)
            self.report(result)
        }
    }

    func captureInteractiveScreenshot(hint: String? = nil, intent: IngestIntent = .auto, activateApp: Bool = false) async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("catchmeup_\(UUID().uuidString).png")
        await run(L.t("请框选截图区域…")) {
            let ok = await Self.runScreencapture(to: tmp)
            guard ok, let data = try? Data(contentsOf: tmp) else {
                throw CatchMeUpError.ingest(L.t("截图已取消"))
            }
            try? FileManager.default.removeItem(at: tmp)
            let ingested = try Ingest.screenshot(imageData: data, originalName: "screenshot.png")
            let result = try await self.pipeline.ingest(ingested, hint: hint,
                                                        intent: intent, autoExtractTasks: true)
            self.report(result)
            if activateApp {
                NSApp.activate(ignoringOtherApps: true)
                self.selection = .workspace
            }
        }
    }

    private func report(_ result: Pipeline.IngestResult) {
        let tasks = result.tasks.count
        if let handoff = result.item.handoff {
            setStatus("已整理「\(result.item.title ?? L.t("未命名"))」，含交接；\(tasks) 条待办")
            self.handoff = handoff
        } else {
            setStatus("已整理「\(result.item.title ?? L.t("未命名"))」，生成 \(tasks) 条待办")
        }
    }

    static func clipboardPNG() -> Data? {
        guard let image = NSImage(pasteboard: NSPasteboard.general),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func runScreencapture(to url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", url.path]
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path))
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: Task CRUD

    func saveTaskWithCalendar(_ task: TaskItem, writeToCalendar: Bool) async {
        await run(L.t("保存任务…")) {
            _ = try await self.pipeline.updateTask(task, writeToCalendar: writeToCalendar)
            self.setStatus(L.t("任务已保存"))
        }
    }

    func newTask(title: String, detail: String?, due: Date?, priority: TaskPriority,
                 recurrence: Recurrence, writeToCalendar: Bool? = nil) async {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await run(L.t("创建任务…")) {
            _ = try await self.pipeline.createTask(title: title, detail: detail,
                                                   priority: priority, dueAt: due,
                                                   recurrence: recurrence,
                                                   writeToCalendar: writeToCalendar)
            self.setStatus(L.t("任务已创建"))
        }
    }

    func complete(_ task: TaskItem) async {
        await run(nil) {
            _ = try await self.pipeline.completeTask(task)
            self.setStatus(L.f("已完成「%@」", task.title))
        }
    }

    func reopen(_ task: TaskItem) async {
        var updated = task
        updated.status = .pending
        updated.completedAt = nil
        await run(nil) {
            _ = try await self.pipeline.updateTask(updated)
            self.setStatus(L.f("已恢复「%@」", task.title))
        }
    }

    /// One-field quick add (Enter to create). No date; can be set inline afterwards.
    func quickAddTask(_ title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await run(nil) {
            _ = try await self.pipeline.createTask(title: trimmed)
            self.setStatus(L.f("已添加「%@」", trimmed))
        }
    }

    /// Reschedule (or clear, with nil) a task's due date.
    func reschedule(_ task: TaskItem, to date: Date?) async {
        var updated = task
        updated.dueAt = date
        if date == nil { updated.recurrence = .none }
        await run(nil) {
            _ = try await self.pipeline.updateTask(updated)
            self.setStatus(date == nil ? L.t("已清除截止时间") : "已改期到 \(Fmt.due(date))")
        }
    }

    func setPriority(_ task: TaskItem, _ priority: TaskPriority) async {
        var updated = task
        updated.priority = priority
        await run(nil) {
            _ = try await self.pipeline.updateTask(updated)
        }
    }

    func cancel(_ task: TaskItem) async {
        var updated = task
        updated.status = .cancelled
        await run(nil) {
            _ = try await self.pipeline.updateTask(updated)
            self.setStatus(L.f("已取消「%@」", task.title))
        }
    }

    func delete(_ task: TaskItem) async {
        await run(nil) {
            try self.pipeline.deleteTask(task)
            self.setStatus(L.t("已删除任务"))
        }
    }

    func delete(_ item: Item) async {
        await run(nil) {
            _ = try self.pipeline.deleteItem(item)
            self.setStatus(L.t("已删除素材及其关联任务"))
        }
    }

    // MARK: Handoff

    func generateHandoff(extraContext: String?) async {
        await run(L.t("正在生成交接摘要…")) {
            self.handoff = try await self.pipeline.generateHandoff(extraContext: extraContext)
            self.setStatus(L.t("交接摘要已生成"))
        }
    }

    func refreshHandoff(_ item: Item) async {
        await run(L.t("正在增量更新交接…")) {
            let updated = try await self.pipeline.refreshHandoff(for: item)
            self.handoff = updated.handoff
            self.setStatus("已更新「\(updated.title ?? L.t("未命名"))」的交接")
        }
    }

    /// Refresh a single item from its source (used by the detail window). No confirmation.
    func refreshItem(_ item: Item) async {
        await run(L.t("正在刷新…")) {
            let updated = try await self.pipeline.refreshItem(for: item)
            self.handoff = updated.handoff
            self.setStatus("已刷新「\(updated.title ?? L.t("未命名"))」")
        }
    }

    func startSession(topic: String?, extraContext: String?) async {
        await run(L.t("开启新 Session…")) {
            _ = try await self.pipeline.startSession(topic: topic, extraContext: extraContext)
            self.setStatus(L.t("已开启新 Session"))
        }
    }

    func endSession(extraContext: String?) async {
        guard let session = activeSession else { return }
        await run(L.t("结束 Session 并生成交接…")) {
            let (_, handoff) = try await self.pipeline.endSession(session, extraContext: extraContext)
            self.handoff = handoff
            self.setStatus(L.t("Session 已结束"))
        }
    }

    // MARK: Settings

    func saveSettings() {
        Prefs.setAPIKey(apiKeyInput)
        Prefs.model = modelInput
        Prefs.baseURL = baseURLInput
        Prefs.reminderLeadMinutes = reminderLeadInput
        Prefs.writeToCalendar = writeToCalendarInput
        Prefs.organizerPrompt = organizerPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        Prefs.handoffPrompt = handoffPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        setStatus(L.t("设置已保存"))
    }

    // MARK: Permissions (only requested from Settings, never at launch)

    func requestNotificationAccess() async {
        _ = await ReminderScheduler.shared.requestAuthorization()
        await refreshAuthorization()
        await rescheduleAll()
    }

    func requestCalendarAccess() async {
        _ = await calendar.requestAccess()
        await refreshAuthorization()
        await rescheduleAll()
    }

    /// Re-apply reminders/calendar for existing open tasks after permission is granted.
    private func rescheduleAll() async {
        let db = self.db
        let open = (try? db.tasks(includeCompleted: false, limit: 1000)) ?? []
        for task in open where task.dueAt != nil {
            _ = try? await pipeline.updateTask(task)
        }
        await refresh()
    }

    func requestScreenRecording() {
        _ = ScreenRecording.request()
        screenRecordingGranted = ScreenRecording.granted
    }

    func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Language

    func setLanguage(_ language: AppLanguage) {
        Prefs.followSystemLanguage = false
        Prefs.languageOverride = language.rawValue
        followSystemLanguage = false
        self.language = Prefs.language
    }

    func setFollowSystemLanguage(_ follow: Bool) {
        Prefs.followSystemLanguage = follow
        followSystemLanguage = follow
        language = Prefs.language
    }

    func sendTestNotification() async {
        await scheduler.sendTest()
        setStatus(L.t("测试通知将在 3 秒后弹出"))
    }

    func testConnection() async {
        await run(L.t("测试 DeepSeek 连接…")) {
            _ = try await self.client.chat([.user(L.t("只回复两个字：正常"))],
                                           temperature: 0, maxTokens: 512,
                                           jsonMode: false, attempts: 2)
            self.setStatus(L.f("DeepSeek 连接正常（%@）", Prefs.model))
        }
    }

    // MARK: Private

    private func run(_ busyMessage: String?, _ operation: @escaping () async throws -> Void) async {
        isBusy = true
        if let busyMessage { statusMessage = busyMessage }
        do {
            try await operation()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        // Clear a lingering "busy" status if the operation did not replace it.
        if let busyMessage, statusMessage == busyMessage { statusMessage = nil }
        isBusy = false
    }
}

struct EKEventSummary: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarName: String
    let notes: String?

    init(_ event: EKEvent) {
        id = event.eventIdentifier ?? UUID().uuidString
        title = event.title ?? L.t("(无标题)")
        start = event.startDate ?? Date()
        end = event.endDate ?? Date()
        calendarName = event.calendar?.title ?? ""
        notes = event.notes
    }
}
