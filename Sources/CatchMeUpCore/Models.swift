import Foundation

// MARK: - Enums

public enum ItemKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case text, screenshot, file, folder, url

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .text: return L.t("文本")
        case .screenshot: return L.t("截图")
        case .file: return L.t("文件")
        case .folder: return L.t("文件夹")
        case .url: return L.t("网址")
        }
    }
}

public enum TaskStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case pending, in_progress, done, cancelled

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pending: return L.t("待处理")
        case .in_progress: return L.t("进行中")
        case .done: return L.t("已完成")
        case .cancelled: return L.t("已取消")
        }
    }
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable, Identifiable {
    case low, normal, high, urgent

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .low: return L.t("低")
        case .normal: return L.t("普通")
        case .high: return L.t("高")
        case .urgent: return L.t("紧急")
        }
    }

    public var rank: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .normal: return 2
        case .low: return 3
        }
    }
}

public enum Recurrence: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, daily, weekly, monthly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return L.t("不重复")
        case .daily: return L.t("每天")
        case .weekly: return L.t("每周")
        case .monthly: return L.t("每月")
        }
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case active, handed_off
}

// MARK: - Models

public struct Item: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var kind: ItemKind
    public var title: String?
    public var rawContent: String?
    public var summary: String?
    public var tags: [String]
    public var category: String?
    public var metadata: [String: String]
    public var sourcePath: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString,
                kind: ItemKind,
                title: String? = nil,
                rawContent: String? = nil,
                summary: String? = nil,
                tags: [String] = [],
                category: String? = nil,
                metadata: [String: String] = [:],
                sourcePath: String? = nil,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rawContent = rawContent
        self.summary = summary
        self.tags = tags
        self.category = category
        self.metadata = metadata
        self.sourcePath = sourcePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TaskItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var detail: String?
    public var status: TaskStatus
    public var priority: TaskPriority
    public var dueAt: Date?
    public var reminderAt: Date?
    public var notificationID: String?
    public var calendarEventID: String?
    public var itemID: String?
    public var tags: [String]
    public var recurrence: Recurrence
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(id: String = UUID().uuidString,
                title: String,
                detail: String? = nil,
                status: TaskStatus = .pending,
                priority: TaskPriority = .normal,
                dueAt: Date? = nil,
                reminderAt: Date? = nil,
                notificationID: String? = nil,
                calendarEventID: String? = nil,
                itemID: String? = nil,
                tags: [String] = [],
                recurrence: Recurrence = .none,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
        self.reminderAt = reminderAt
        self.notificationID = notificationID
        self.calendarEventID = calendarEventID
        self.itemID = itemID
        self.tags = tags
        self.recurrence = recurrence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    public var isOpen: Bool { status != .done && status != .cancelled }
}

public struct Session: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var topic: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var summary: String?
    public var nextSteps: [String]
    public var status: SessionStatus

    public init(id: String = UUID().uuidString,
                topic: String? = nil,
                startedAt: Date = Date(),
                endedAt: Date? = nil,
                summary: String? = nil,
                nextSteps: [String] = [],
                status: SessionStatus = .active) {
        self.id = id
        self.topic = topic
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.nextSteps = nextSteps
        self.status = status
    }
}

public struct ReminderLog: Identifiable, Codable, Sendable, Hashable {
    public var id: Int64
    public var taskID: String?
    public var firedAt: Date
    public var delivered: Bool
    public var error: String?
}

// MARK: - Todo (daily to-do, optionally bound to a task)

public enum TodoSource: String, Codable, Sendable {
    case manual, ai
}

public struct Todo: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var detail: String?
    public var isDone: Bool
    /// The calendar day this todo belongs to (normalized to start of day).
    public var day: Date
    public var source: TodoSource
    /// Optional link to a task.
    public var taskID: String?
    public var createdAt: Date
    public var completedAt: Date?

    public init(id: String = UUID().uuidString,
                title: String,
                detail: String? = nil,
                isDone: Bool = false,
                day: Date = Calendar.current.startOfDay(for: Date()),
                source: TodoSource = .manual,
                taskID: String? = nil,
                createdAt: Date = Date(),
                completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isDone = isDone
        self.day = day
        self.source = source
        self.taskID = taskID
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    public var isToday: Bool { Calendar.current.isDateInToday(day) }
}

// MARK: - AI result types

/// What the user wants from a piece of captured content.
public enum IngestIntent: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Let the model decide based on the content.
    case auto
    /// Extract to-dos that have a deadline.
    case task
    /// Produce a brief hand-off note for "tomorrow's me".
    case handoff

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return L.t("自动")
        case .task: return L.t("任务")
        case .handoff: return L.t("交接")
        }
    }
}

public struct OrganizedInput: Codable, Sendable {
    public var title: String?
    public var summary: String?
    public var tags: [String]
    public var category: String?
    public var tasks: [ExtractedTask]
    public var handoff: HandoffResult?

    public init(title: String? = nil, summary: String? = nil, tags: [String] = [],
                category: String? = nil, tasks: [ExtractedTask] = [],
                handoff: HandoffResult? = nil) {
        self.title = title
        self.summary = summary
        self.tags = tags
        self.category = category
        self.tasks = tasks
        self.handoff = handoff
    }
}

public struct ExtractedTask: Codable, Sendable {
    public var title: String
    public var dueAtRaw: String?
    public var detail: String?
    public var priority: String?

    enum CodingKeys: String, CodingKey {
        case title
        case dueAtRaw = "due_at"
        case detail = "description"
        case priority
    }

    public init(title: String, dueAtRaw: String? = nil, detail: String? = nil, priority: String? = nil) {
        self.title = title
        self.dueAtRaw = dueAtRaw
        self.detail = detail
        self.priority = priority
    }
}

/// A single AI-suggested todo.
public struct SuggestedTodo: Codable, Sendable {
    public var title: String
    public var detail: String?
    public var taskIndex: Int?

    enum CodingKeys: String, CodingKey {
        case title, detail
        case taskIndex = "task_index"
    }

    public init(title: String, detail: String? = nil, taskIndex: Int? = nil) {
        self.title = title
        self.detail = detail
        self.taskIndex = taskIndex
    }
}

public struct TodoSuggestions: Codable, Sendable {
    public var todos: [SuggestedTodo]
    public init(todos: [SuggestedTodo] = []) { self.todos = todos }
}

public struct HandoffResult: Codable, Sendable {    public var goals: [String]
    public var logic: String
    public var progressSummary: String
    public var nextSteps: [String]
    public var risks: [String]

    enum CodingKeys: String, CodingKey {
        case goals
        case logic
        case progressSummary = "progress_summary"
        case nextSteps = "next_steps"
        case risks
    }

    public init(goals: [String] = [], logic: String = "", progressSummary: String = "",
                nextSteps: [String] = [], risks: [String] = []) {
        self.goals = goals
        self.logic = logic
        self.progressSummary = progressSummary
        self.nextSteps = nextSteps
        self.risks = risks
    }

    /// Tolerant decoding: every field is optional in the model output.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goals = try c.decodeIfPresent([String].self, forKey: .goals) ?? []
        logic = try c.decodeIfPresent(String.self, forKey: .logic) ?? ""
        progressSummary = try c.decodeIfPresent(String.self, forKey: .progressSummary) ?? ""
        nextSteps = try c.decodeIfPresent([String].self, forKey: .nextSteps) ?? []
        risks = try c.decodeIfPresent([String].self, forKey: .risks) ?? []
    }
}

// MARK: - Handoff attached to an item

public extension Item {
    /// A hand-off note attached to this item (when the organizer produced one).
    var handoff: HandoffResult? {
        let progress = metadata["handoff_progress"] ?? ""
        let logic = metadata["handoff_logic"] ?? ""
        let goals = Item.decodeStringArray(metadata["handoff_goals"])
        guard !progress.isEmpty || !logic.isEmpty || !goals.isEmpty else { return nil }
        return HandoffResult(goals: goals,
                             logic: logic,
                             progressSummary: progress,
                             nextSteps: Item.decodeStringArray(metadata["handoff_next_steps"]),
                             risks: Item.decodeStringArray(metadata["handoff_risks"]))
    }

    static func decodeStringArray(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }
}

// MARK: - Errors

public enum CatchMeUpError: LocalizedError {
    case missingAPIKey
    case api(String)
    case invalidResponse(String)
    case notFound(String)
    case ingest(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return L.t("未配置 DeepSeek API Key，请在设置中填写。")
        case .api(let msg): return L.f("DeepSeek 接口错误：%@", msg)
        case .invalidResponse(let msg): return L.f("返回内容无法解析：%@", msg)
        case .notFound(let what): return L.f("未找到：%@", what)
        case .ingest(let msg): return L.f("读取失败：%@", msg)
        }
    }
}
