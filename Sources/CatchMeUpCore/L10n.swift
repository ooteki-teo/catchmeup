import Foundation

// MARK: - Language

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case zh, en, es, ja, ko

    public var id: String { rawValue }

    public var nativeName: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        case .es: return "Español"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }

    public var localeIdentifier: String {
        switch self {
        case .zh: return "zh-Hans"
        case .en: return "en"
        case .es: return "es"
        case .ja: return "ja"
        case .ko: return "ko"
        }
    }

    public static func systemDefault() -> AppLanguage {
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
                ?? String(identifier.prefix(2))
            if let language = AppLanguage(rawValue: String(code.prefix(2))) { return language }
        }
        return .en
    }
}

// MARK: - Localization

/// Central, in-app localization. Keys are the Chinese source strings, so any
/// missing translation gracefully falls back to Chinese.
public enum L {
    public static var current: AppLanguage { Prefs.language }

    public static func t(_ zh: String) -> String {
        let lang = current
        if lang == .zh { return zh }
        return table(for: lang)[zh] ?? en[zh] ?? zh
    }

    /// Format helper: the key contains `%@` / `%d` placeholders.
    public static func f(_ zh: String, _ args: CVarArg...) -> String {
        String(format: t(zh), arguments: args)
    }

    public static var locale: Locale { Locale(identifier: current.localeIdentifier) }

    public static var languageName: String { current.nativeName }

    // MARK: Prompts

    private static let organizerSystemZH = """
    你是一个中文个人助理，帮用户把碎片化输入（文本、截图、文件、文件夹、网址）整理成结构化条目。
    你需要同时准备两种产出：
    A. 任务（tasks）：只提取真正有明确时间点或截止时间的待办，due_at 用 ISO 8601。
    B. 交接（handoff）：做一次「项目梳理」，让用户（或明天的自己）能连续接手。必须包含：
       1) goals：这个项目的目标（1-3 条）。
       2) logic：整体是怎么做的、大致逻辑或结构（1-3 句）。
       3) progress_summary：详细过程——做过什么、当前进行到哪一步。
       4) next_steps：结合现有内容（尤其是目录里的文件）推断接下来可能要做什么，3-6 条、可执行。
       5) risks：卡点或未决问题（没有就空数组）。

    只输出严格 JSON，不要包含任何额外解释：
    {
      "title": "一行标题",
      "summary": "不超过 80 字的摘要",
      "tags": ["3-5 个中文标签"],
      "category": "工作/学习/生活/项目/灵感/参考/其他",
      "tasks": [
        {"title": "...", "due_at": "2026-01-01T15:00:00", "description": "...", "priority": "normal"}
      ],
      "handoff": {
        "goals": ["..."],
        "logic": "...",
        "progress_summary": "...",
        "next_steps": ["..."],
        "risks": ["..."]
      }
    }

    规则：
    - due_at 只在有明确时间时填写，否则留空字符串；
    - 没有待办时 tasks 输出空数组；
    - 没有可交接内容时 handoff 输出 null；
    - 项目/代码目录会以「README（若有）+ 目录树（含每个文件的一句话说明）」的形式给出，请据此推断目标、整体逻辑与下一步，不要臆造未出现的内容；
    - 输入是一个项目/代码目录或工作小结时，必须认真填写 handoff 的五项；
    - 若用户提供了「上次交接」，请在其基础上做增量更新：保留仍然有效的目标与进展，补上新增/变化的部分，不要整段重写或丢失已有信息。
    - priority 可选: low | normal | high | urgent。
    """

    private static let handoffSystemZH = """
    你是用户的私人助理，负责写一份「给明天的自己看」的项目交接，用于连续追踪。
    基于最近捕获的 items、未完成 tasks 和最近的 session，输出严格 JSON，不要客套，不要多余解释：
    {
      "goals": ["这个项目的目标（1-3 条）"],
      "logic": "整体是怎么做的、大致逻辑或结构（1-3 句）",
      "progress_summary": "详细过程：已做过什么、当前进行到哪一步",
      "next_steps": ["结合现有内容推断接下来可能要做什么，3-6 条，按优先级排序"],
      "risks": ["卡点或未决问题（没有就空数组）"]
    }

    如果信息不足，基于现有数据尽力推断，并在 progress_summary 末尾注明"信息有限，建议补充：…"。
    如果用户提供了「上次交接」，在其基础上增量更新：保留仍然有效的目标与进展，补充新增/变化，不要丢失已有信息。
    """

    private static let organizerSystemEN = """
    You are a personal assistant. Organize fragmented input (text, screenshot, file, folder, URL) into a structured entry.
    Produce two things:
    A. tasks: only to-dos with an explicit time/deadline; due_at in ISO 8601.
    B. handoff: a project recap so the user (or tomorrow's self) can continue. Must include:
       1) goals: 1-3 project goals.
       2) logic: how it works at a high level (1-3 sentences).
       3) progress_summary: detailed process — what was done, where it stands.
       4) next_steps: 3-6 concrete next actions inferred from the content (especially files in a folder).
       5) risks: blockers/open questions (empty array if none).

    Output STRICT JSON only, no extra text:
    {
      "title": "one-line title",
      "summary": "summary under 80 chars",
      "tags": ["3-5 tags"],
      "category": "work/study/life/project/idea/reference/other",
      "tasks": [
        {"title": "...", "due_at": "2026-01-01T15:00:00", "description": "...", "priority": "normal"}
      ],
      "handoff": {
        "goals": ["..."],
        "logic": "...",
        "progress_summary": "...",
        "next_steps": ["..."],
        "risks": ["..."]
      }
    }

    Rules:
    - due_at only when a time is explicit, otherwise "".
    - tasks may be an empty array.
    - handoff may be null when there is nothing to hand off.
    - A project/code folder is given as "README (if any) + directory tree (one-line note per file)"; infer goals/logic/next steps from it, do not invent content.
    - If a previous handoff is provided, update it incrementally.
    - priority: low | normal | high | urgent.
    """

    private static let handoffSystemEN = """
    You are the user's assistant. Write a short "for tomorrow's me" project handoff for continuous tracking.
    Based on recent items, open tasks, and recent sessions, output STRICT JSON only:
    {
      "goals": ["project goals (1-3)"],
      "logic": "how it works at a high level (1-3 sentences)",
      "progress_summary": "detailed process: what was done, where it stands",
      "next_steps": ["3-6 concrete next actions, priority-ordered"],
      "risks": ["blockers/open questions (empty array if none)"]
    }

    If information is insufficient, infer as best you can and append "Limited info; suggest adding: ..." to progress_summary.
    If a previous handoff is provided, update it incrementally: keep valid goals and progress, add changes, don't lose existing info.
    """

    public static var organizerSystem: String {
        current == .zh ? organizerSystemZH
            : organizerSystemEN + "\n\nWrite all human-readable text (title, summary, tags, category, goals, logic, progress_summary, next_steps, risks) in \(languageName)."
    }

    public static var handoffSystem: String {
        current == .zh ? handoffSystemZH
            : handoffSystemEN + "\n\nWrite all human-readable text in \(languageName)."
    }

    public static var pNow: String { current == .zh ? "当前时间" : "Current time" }
    public static var pKind: String { current == .zh ? "类型" : "Type" }
    public static var pIntentAuto: String {
        current == .zh ? "用户意图: 自动判断——需要跟进的截止事项写 tasks；项目/工作进展写 handoff。"
            : "User intent: decide automatically — deadlines go to tasks; project/work progress goes to handoff."
    }
    public static var pIntentTask: String {
        current == .zh ? "用户意图: 重点抽取带明确时间的待办到 tasks；handoff 可为 null。"
            : "User intent: extract to-dos with explicit times into tasks; handoff may be null."
    }
    public static var pIntentHandoff: String {
        current == .zh ? "用户意图: 这是项目/工作进展，重点生成项目梳理型 handoff（goals / logic / 详细过程 / 接下来要做什么）；tasks 仅在确有截止时间时填写。"
            : "User intent: this is project/work progress — focus on a structured handoff (goals / logic / detailed progress / next steps); only add tasks with real deadlines."
    }
    public static var pHint: String { current == .zh ? "用户补充说明" : "User note" }
    public static var pPrevious: String {
        current == .zh ? "上次交接（请在此基础上做增量更新，保留有效信息，只补充新增/变化）"
            : "Previous handoff (update incrementally; keep valid info, only add changes)"
    }
    public static var pContent: String { current == .zh ? "内容" : "Content" }
    public static var pImageAttached: String { current == .zh ? "(见随附图片)" : "(see attached image)" }
    public static var pUserExtra: String { current == .zh ? "用户补充" : "User context" }

    // MARK: Todo suggestions

    private static let todoSystemZH = """
    你是用户的每日待办助理。基于用户的未完成任务和最近的项目交接，为今天推荐 3-6 条具体、可执行的待办。
    只输出严格 JSON，不要额外解释：
    {"todos":[{"title":"...","detail":"...可选","task_index":0}]}
    规则：
    - title 要短、可执行（动词开头）；
    - 不要和「已有待办」重复；
    - 若某条对应某个未完成任务，task_index 填该任务在列表中的序号（从 0 开始），否则省略 task_index。
    """

    private static let todoSystemEN = """
    You are the user's daily to-do assistant. Based on the user's open tasks and recent project handoffs, suggest 3-6 concrete, actionable todos for today.
    Output STRICT JSON only, no extra text:
    {"todos":[{"title":"...","detail":"...optional","task_index":0}]}
    Rules:
    - keep titles short and action-oriented (start with a verb);
    - do not duplicate items already in "Existing todos";
    - if a todo corresponds to an open task, set task_index to its 0-based index in the list; otherwise omit task_index.
    """

    public static var todoSystem: String {
        current == .zh ? todoSystemZH
            : todoSystemEN + "\n\nWrite every todo title and detail in \(languageName)."
    }
    public static var todoTasksLabel: String { current == .zh ? "未完成任务" : "Open tasks" }
    public static var todoHandoffsLabel: String { current == .zh ? "项目交接（下一步）" : "Project handoffs (next steps)" }
    public static var todoExistingLabel: String { current == .zh ? "已有待办（不要重复）" : "Existing todos (do not duplicate)" }

    private static func table(for language: AppLanguage) -> [String: String] {
        switch language {
        case .zh: return [:]
        case .en: return en
        case .es: return es
        case .ja: return ja
        case .ko: return ko
        }
    }

    // MARK: Table

    static let en: [String: String] = [
        "工作台": "Workspace", "任务": "Tasks", "任务交接": "Handoff",
        "日历": "Calendar", "定时任务": "Scheduled", "设置": "Settings",
        "素材": "Items", "保存": "Save", "取消": "Cancel",
        "删除": "Delete", "关闭": "Close", "编辑": "Edit",
        "创建": "Create", "添加": "Add", "修改": "Change",
        "默认": "Default", "刷新": "Refresh", "重置": "Reset",
        "清空": "Clear", "填入默认": "Use default", "全部": "All",
        "新建": "New", "更新": "Update", "恢复": "Reopen",
        "退出": "Quit", "打开主窗口": "Open Main Window", "打开日历": "Open Calendar",
        "在访达中显示": "Reveal in Finder", "打开系统设置": "Open System Settings", "请求授权": "Request",
        "重新检查状态": "Re-check status", "复制为 Markdown": "Copy as Markdown", "查看来源素材": "View source item",
        "同步到系统日历": "Sync to Calendar", "设置 / 修改截止时间": "Set / change due date", "标签": "Tags",
        "输入文字 / 网址 / 文件路径，或把文件、截图直接拖进来（⌘V 可粘贴截图）": "Type text / URL / file path, or drop files & screenshots here (⌘V to paste a screenshot)", "添加文件 / 文件夹 / 图片": "Add file / folder / image", "框选截图": "Capture screen region",
        "可选：补充说明（帮助 AI 理解上下文）": "Optional note (helps the AI understand context)", "整理": "Organize", "自动": "Auto",
        "交接": "Handoff", "搜索素材": "Search items", "搜索": "Search",
        "切换卡片 / 列表": "Switch card / list", "未完成": "Open", "今日到期": "Due today",
        "近 7 天": "Next 7 days", "已逾期": "Overdue", "在上面输入、粘贴或拖入内容开始": "Type, paste, or drop something above to start",
        "在上面输入一句话，回车即创建": "Type a line above, press Return to create", "还没有素材": "No items yet", "没有匹配的素材": "No matching items",
        "换个关键词试试": "Try another keyword", "自动：文本/截图→任务，目录→交接 · 任务：抽取截止时间 · 交接：项目梳理": "Auto: text/screenshot → task, folder → handoff · Task: extract deadlines · Handoff: project summary", "今天": "Today",
        "明天": "Tomorrow", "本周内": "This week", "以后": "Later",
        "无日期": "No date", "已完成": "Completed", "添加任务，回车即可": "Add a task, press Return",
        "标记完成": "Mark done", "取消任务": "Cancel task", "今天 18:00": "Today 18:00",
        "明天 09:00": "Tomorrow 09:00", "下周一 09:00": "Next Monday 09:00", "本周六 10:00": "This Saturday 10:00",
        "清除日期": "Clear date", "自定义…": "Custom…", "显示已完成": "Show completed",
        "新建一条带细节的任务": "Create a task with details", "还没有任务": "No tasks yet", "没有匹配的任务": "No matching tasks",
        "相关素材": "Related items", "关联任务": "Linked tasks", "没有带任务的素材": "No items with tasks",
        "捕获含截止时间的内容，任务会挂到对应素材下": "Capture content with deadlines; tasks attach to their item", "新建任务": "New task", "编辑任务": "Edit task",
        "任务标题": "Task title", "描述（可选）": "Description (optional)", "截止时间": "Due date",
        "重复": "Repeat", "优先级": "Priority", "不重复": "None",
        "每天": "Daily", "每周": "Weekly", "每月": "Monthly",
        "低": "Low", "普通": "Normal", "高": "High",
        "紧急": "Urgent", "待处理": "Pending", "进行中": "In progress",
        "已取消": "Cancelled", "优先级：%@": "Priority: %@", "操作": "Actions",
        "生成交接摘要": "Generate handoff", "开启新 Session": "Start session", "结束当前 Session": "End session",
        "Session 主题（可选）": "Session topic (optional)", "补充上下文（最近重点 / 卡点 / 背景，可选）": "Extra context (focus / blockers / background, optional)", "交接素材": "Handoff items",
        "最新交接摘要": "Latest handoff", "还没有交接素材": "No handoff items yet", "把项目、目录或工作小结用「交接」模式整理，就会出现在这里": "Organize a project, folder, or work summary in Handoff mode and it shows up here",
        "目标": "Goals", "整体逻辑": "Approach", "进展": "Progress",
        "下一步": "Next steps", "风险": "Risks", "风险 / 未决问题": "Risks / open questions",
        "历史 Session（%d）": "Past sessions (%d)", "未命名": "Untitled", "增量更新这份交接": "Incrementally update this handoff",
        "未来 30 天的日历日程": "Calendar events in the next 30 days", "带截止时间的任务会自动写入日历": "Tasks with due dates are written to Calendar automatically", "请先授权日历访问": "Please grant Calendar access first",
        "授权日历访问": "Grant Calendar access", "暂无日程": "No events", "待触发的提醒": "Scheduled reminders",
        "暂无调度中的提醒": "No scheduled reminders", "测试": "Test", "发送一条测试通知（3 秒后）": "Send a test notification (after 3s)",
        "发送测试通知": "Send test notification", "提醒规则": "Rules", "已调度的本地通知。即使关闭 App，系统仍会按时提醒。": "Scheduled local notifications. They still fire when the app is closed.",
        "任务设置截止时间后，默认在截止前 %d 分钟提醒": "With a due date, remind %d minutes before it", "重复任务（每天/每周/每月）会按周期重复提醒": "Repeating tasks (daily/weekly/monthly) repeat the reminder", "可在设置中调整提前量和是否写入日历": "Adjust lead time and calendar sync in Settings",
        "模型、权限与提醒设置": "Model, permissions, and reminders", "API Key": "API Key", "模型": "Model",
        "测试连接": "Test connection", "保存在本机应用目录的 secrets.json（仅当前用户可读），不使用系统钥匙串，因此不会弹授权。": "Stored in secrets.json in the app's local folder (current user only). No Keychain, no prompts.", "deepseek-flash（支持图片，推荐）": "deepseek-flash (images, recommended)",
        "deepseek-v4-pro（纯文本）": "deepseek-v4-pro (text only)", "提醒": "Reminders", "默认提前 %d 分钟提醒": "Remind %d minutes before by default",
        "把带截止时间的任务写入系统日历": "Write tasks with due dates to Calendar", "权限": "Permissions", "权限只在下面主动点击时申请，App 启动时不会自动弹窗。": "Permissions are requested only when you click below; nothing pops up at launch.",
        "通知": "Notifications", "屏幕录制（截图）": "Screen Recording (screenshots)", "已授权": "Granted",
        "未授权": "Not granted", "已拒绝": "Denied", "受限": "Restricted",
        "仅写入": "Write-only", "未知": "Unknown", "通用": "General",
        "开机自动启动": "Launch at login", "截图快捷键": "Screenshot shortcut", "请按下组合键（Esc 取消）": "Press a shortcut (Esc to cancel)",
        "数据目录": "Data folder", "提示词（高级）": "Prompts (advanced)", "留空表示使用内置默认提示词；修改后点「保存」生效。": "Leave empty to use the built-in prompts; click Save to apply.",
        "整理提示词（任务 / 交接）": "Organizer prompt (task / handoff)", "交接摘要提示词": "Handoff summary prompt", "（留空 = 使用内置默认提示词）": "(empty = built-in default prompt)",
        "Token 用量": "Token usage", "调用次数": "Requests", "输入": "Input",
        "输出": "Output", "合计": "Total", "暂无用量记录": "No usage recorded",
        "最近更新：%@": "Updated: %@", "语言": "Language", "跟随系统": "System default",
        "需要重新启动 App 以应用语言。": "Restart the app to apply the language.", "关于": "About", "CatchMeUp · 原生 macOS 任务助理": "CatchMeUp · native macOS task assistant",
        "截图 / 文字 / 文件 / 文件夹 / 网址 → 自动整理为素材与待办，支持提醒、日历与任务交接。": "Screenshot / text / file / folder / URL → items and tasks, with reminders, calendar and handoff.", "数据全部保存在本机，仅整理时调用 DeepSeek。": "All data stays on this Mac; DeepSeek is called only when organizing.", "素材详情": "Item details",
        "摘要": "Summary", "原始内容": "Raw content", "本地文件": "Local file",
        "根据来源内容重新分析这条素材": "Re-analyze this item from its source", "(无标题)": "(Untitled)", "正在整理文本…": "Organizing text…",
        "正在抓取网页…": "Fetching web page…", "正在读取…": "Reading…", "正在识别图片…": "Recognizing image…",
        "请框选截图区域…": "Select a screen region…", "正在生成交接摘要…": "Generating handoff…", "正在增量更新交接…": "Updating handoff…",
        "正在刷新…": "Refreshing…", "保存任务…": "Saving task…", "创建任务…": "Creating task…",
        "开启新 Session…": "Starting session…", "结束 Session 并生成交接…": "Ending session…", "测试 DeepSeek 连接…": "Testing DeepSeek connection…",
        "已整理「%@」": "Organized \"%@\"", "已整理「%@」，生成 %d 条待办": "Organized \"%@\", %d task(s)", "已整理「%@」，含交接；%d 条待办": "Organized \"%@\" with handoff; %d task(s)",
        "已抓取「%@」": "Fetched \"%@\"", "任务已保存": "Task saved", "任务已创建": "Task created",
        "已完成「%@」": "Completed \"%@\"", "已恢复「%@」": "Reopened \"%@\"", "已添加「%@」": "Added \"%@\"",
        "已取消「%@」": "Cancelled \"%@\"", "已删除任务": "Task deleted", "已删除素材及其关联任务": "Item and its tasks deleted",
        "已改期到 %@": "Rescheduled to %@", "已清除截止时间": "Due date cleared", "交接摘要已生成": "Handoff generated",
        "Session 已结束": "Session ended", "已开启新 Session": "New session started", "已更新「%@」的交接": "Updated handoff for \"%@\"",
        "已刷新「%@」": "Refreshed \"%@\"", "设置已保存": "Settings saved", "已重置 Token 统计": "Token usage reset",
        "交接摘要已复制到剪贴板": "Handoff copied to clipboard", "测试通知将在 3 秒后弹出": "Test notification in 3 seconds", "DeepSeek 连接正常（%@）": "DeepSeek OK (%@)",
        "截图已取消": "Screenshot cancelled", "剪贴板里没有可识别的内容": "Nothing recognizable on the clipboard", "截图快捷键已更新为 %@": "Screenshot shortcut set to %@",
        "截图快捷键已恢复默认（%@）": "Screenshot shortcut reset (%@)", "该快捷键可能已被其它 App 占用，已保留原设置": "Shortcut may be taken by another app; kept the previous setting", "设置开机启动失败：%@（需以 .app 形式运行）": "Failed to enable launch at login: %@ (run as .app)",
        "无截止时间": "No due date", "已过期": "Overdue", "即将": "Soon",
        "%d 分钟前": "%dm ago", "%d 分钟后": "in %dm", "%d 小时前": "%dh ago",
        "%d 小时后": "in %dh", "%d 天前": "%dd ago", "%d 天后": "in %dd",
        "今天 %@": "Today %@", "明天 %@": "Tomorrow %@", "昨天 %@": "Yesterday %@",
        "截止 %@": "Due %@", "未配置 DeepSeek API Key，请在设置中填写。": "DeepSeek API key not set. Add it in Settings.", "DeepSeek 接口错误：%@": "DeepSeek error: %@",
        "返回内容无法解析：%@": "Unparsable response: %@", "读取失败：%@": "Read failed: %@", "未找到：%@": "Not found: %@",
        "无法初始化数据库：%@": "Failed to open database: %@", "无法打开数据库：%@": "Cannot open database: %@", "文件不存在：%@": "File not found: %@",
        "文件夹不存在：%@": "Folder not found: %@", "无法读取图片：%@": "Cannot read image: %@", "无效网址：%@": "Invalid URL: %@",
        "抓取失败，状态码 %d": "Fetch failed, status %d", "无 HTTP 响应": "No HTTP response", "空响应（finish_reason=%@）": "Empty response (finish_reason=%@)",
        "响应被截断，自动扩容重试": "Response truncated; retrying with a larger budget", "路径不存在：%@": "Path not found: %@", "文本": "Text",
        "截图": "Screenshot", "文件": "File", "文件夹": "Folder",
        "网址": "URL",
        "任务提醒 · %@": "Task reminder · %@", "(整理失败：%@)": "(Organize failed: %@)", "%d 条已逾期": "%d overdue", "框选截图（全局快捷键 %@）": "Capture screen region (⌘⇧M → %@)", "%d 条": "%d items", "… 还有 %d 条": "…and %d more", "%d 次 · %@ tokens": "%d calls · %@ tokens",
        "连接正常（%@）": "Connected (%@)",
        "AI 提供商": "AI Provider", "提供商": "Provider",
        "待办": "Todo", "今日待办": "Today's todos", "生成今日待办": "Suggest today's todos", "正在生成今日待办…": "Generating today's todos…", "AI 推荐": "AI suggestions", "推荐待办": "Suggested todos", "全部添加": "Add all", "新建待办，回车即可": "Add a todo, press Return", "暂无待办": "No todos", "已删除待办": "Todo deleted", "未完成（往日）": "Unfinished (earlier)", "今日已完成": "Done today", "绑定任务": "Link a task", "解除绑定": "Unlink", "已绑定到「%@」": "Linked to \"%@\"", "已解除绑定": "Unlinked", "已生成 %d 条推荐": "%d suggestion(s)", "暂无推荐": "No suggestions", "关联任务：%@": "Task: %@", "来源：AI": "From AI",
    ]

    static let es: [String: String] = [
        "工作台": "Espacio", "任务": "Tareas", "任务交接": "Handoff",
        "日历": "Calendario", "定时任务": "Programadas", "设置": "Ajustes",
        "素材": "Elementos", "保存": "Guardar", "取消": "Cancelar",
        "删除": "Eliminar", "关闭": "Cerrar", "编辑": "Editar",
        "创建": "Crear", "添加": "Añadir", "修改": "Cambiar",
        "默认": "Predet.", "刷新": "Actualizar", "重置": "Restablecer",
        "清空": "Vaciar", "填入默认": "Usar predet.", "全部": "Todos",
        "新建": "Nuevo", "更新": "Actualizar", "恢复": "Reabrir",
        "退出": "Salir", "打开主窗口": "Abrir ventana principal", "打开日历": "Abrir Calendario",
        "在访达中显示": "Mostrar en Finder", "打开系统设置": "Abrir Ajustes del sistema", "请求授权": "Solicitar",
        "重新检查状态": "Revisar estado", "复制为 Markdown": "Copiar como Markdown", "查看来源素材": "Ver elemento origen",
        "同步到系统日历": "Sincronizar con Calendario", "设置 / 修改截止时间": "Definir / cambiar vencimiento", "输入文字 / 网址 / 文件路径，或把文件、截图直接拖进来（⌘V 可粘贴截图）": "Escribe texto / URL / ruta, o arrastra archivos y capturas (⌘V para pegar una captura)",
        "添加文件 / 文件夹 / 图片": "Añadir archivo / carpeta / imagen", "框选截图": "Capturar región", "可选：补充说明（帮助 AI 理解上下文）": "Nota opcional (ayuda a la IA)",
        "整理": "Organizar", "自动": "Auto", "交接": "Handoff",
        "搜索素材": "Buscar elementos", "搜索": "Buscar", "切换卡片 / 列表": "Cambiar tarjeta / lista",
        "未完成": "Abiertas", "今日到期": "Vencen hoy", "近 7 天": "Próx. 7 días",
        "已逾期": "Vencidas", "在上面输入、粘贴或拖入内容开始": "Escribe, pega o arrastra algo arriba para empezar", "在上面输入一句话，回车即创建": "Escribe una línea arriba y pulsa Intro",
        "还没有素材": "Sin elementos", "没有匹配的素材": "Sin coincidencias", "换个关键词试试": "Prueba otra palabra",
        "自动：文本/截图→任务，目录→交接 · 任务：抽取截止时间 · 交接：项目梳理": "Auto: texto/captura → tarea, carpeta → handoff · Tarea: plazos · Handoff: resumen", "今天": "Hoy", "明天": "Mañana",
        "本周内": "Esta semana", "以后": "Después", "无日期": "Sin fecha",
        "已完成": "Completadas", "添加任务，回车即可": "Añade una tarea y pulsa Intro", "标记完成": "Marcar hecha",
        "取消任务": "Cancelar tarea", "今天 18:00": "Hoy 18:00", "明天 09:00": "Mañana 09:00",
        "下周一 09:00": "Lunes próximo 09:00", "本周六 10:00": "Sábado 10:00", "清除日期": "Quitar fecha",
        "自定义…": "Personalizado…", "显示已完成": "Mostrar completadas", "新建一条带细节的任务": "Crear tarea con detalles",
        "还没有任务": "Sin tareas", "没有匹配的任务": "Sin coincidencias", "相关素材": "Elementos relacionados",
        "关联任务": "Tareas vinculadas", "没有带任务的素材": "Sin elementos con tareas", "捕获含截止时间的内容，任务会挂到对应素材下": "Captura contenido con plazos; las tareas se vinculan",
        "新建任务": "Nueva tarea", "编辑任务": "Editar tarea", "任务标题": "Título",
        "描述（可选）": "Descripción (opcional)", "截止时间": "Vencimiento", "重复": "Repetir",
        "优先级": "Prioridad", "不重复": "Nunca", "每天": "Diaria",
        "每周": "Semanal", "每月": "Mensual", "低": "Baja",
        "普通": "Normal", "高": "Alta", "紧急": "Urgente",
        "待处理": "Pendiente", "进行中": "En curso", "已取消": "Cancelada",
        "优先级：%@": "Prioridad: %@", "操作": "Acciones", "生成交接摘要": "Generar handoff",
        "开启新 Session": "Iniciar sesión", "结束当前 Session": "Terminar sesión", "Session 主题（可选）": "Tema de sesión (opcional)",
        "补充上下文（最近重点 / 卡点 / 背景，可选）": "Contexto (foco / bloqueos / fondo, opcional)", "交接素材": "Elementos de handoff", "最新交接摘要": "Último handoff",
        "还没有交接素材": "Sin elementos de handoff", "把项目、目录或工作小结用「交接」模式整理，就会出现在这里": "Organiza un proyecto, carpeta o resumen en modo Handoff y aparecerá aquí", "目标": "Objetivos",
        "整体逻辑": "Enfoque", "进展": "Progreso", "下一步": "Próximos pasos",
        "风险": "Riesgos", "风险 / 未决问题": "Riesgos / pendientes", "历史 Session（%d）": "Sesiones anteriores (%d)",
        "未命名": "Sin título", "增量更新这份交接": "Actualizar el handoff de forma incremental", "未来 30 天的日历日程": "Eventos de los próximos 30 días",
        "带截止时间的任务会自动写入日历": "Las tareas con vencimiento se añaden al Calendario", "请先授权日历访问": "Concede acceso al Calendario", "授权日历访问": "Permitir Calendario",
        "暂无日程": "Sin eventos", "待触发的提醒": "Recordatorios programados", "暂无调度中的提醒": "Sin recordatorios",
        "测试": "Prueba", "发送一条测试通知（3 秒后）": "Enviar notificación de prueba (3 s)", "发送测试通知": "Enviar prueba",
        "提醒规则": "Reglas", "已调度的本地通知。即使关闭 App，系统仍会按时提醒。": "Notificaciones locales programadas. Se muestran aunque la app esté cerrada.", "任务设置截止时间后，默认在截止前 %d 分钟提醒": "Con vencimiento, avisa %d minutos antes",
        "重复任务（每天/每周/每月）会按周期重复提醒": "Las tareas repetitivas repiten el aviso", "可在设置中调整提前量和是否写入日历": "Ajusta el aviso y el calendario en Ajustes", "模型、权限与提醒设置": "Modelo, permisos y recordatorios",
        "测试连接": "Probar conexión", "保存在本机应用目录的 secrets.json（仅当前用户可读），不使用系统钥匙串，因此不会弹授权。": "Se guarda en secrets.json (solo tu usuario). Sin Llavero, sin avisos.", "deepseek-flash（支持图片，推荐）": "deepseek-flash (imágenes, recomendado)",
        "deepseek-v4-pro（纯文本）": "deepseek-v4-pro (solo texto)", "提醒": "Recordatorios", "默认提前 %d 分钟提醒": "Avisar %d minutos antes",
        "把带截止时间的任务写入系统日历": "Escribir tareas con vencimiento en el Calendario", "权限": "Permisos", "权限只在下面主动点击时申请，App 启动时不会自动弹窗。": "Los permisos se solicitan solo al pulsar abajo; nada aparece al iniciar.",
        "通知": "Notificaciones", "屏幕录制（截图）": "Grabación de pantalla (capturas)", "已授权": "Concedido",
        "未授权": "No concedido", "已拒绝": "Denegado", "受限": "Restringido",
        "仅写入": "Solo escritura", "未知": "Desconocido", "通用": "General",
        "开机自动启动": "Abrir al iniciar sesión", "截图快捷键": "Atajo de captura", "请按下组合键（Esc 取消）": "Pulsa un atajo (Esc para cancelar)",
        "数据目录": "Carpeta de datos", "提示词（高级）": "Prompts (avanzado)", "留空表示使用内置默认提示词；修改后点「保存」生效。": "Vacío usa los prompts integrados; pulsa Guardar para aplicar.",
        "整理提示词（任务 / 交接）": "Prompt de organización (tarea / handoff)", "交接摘要提示词": "Prompt de resumen de handoff", "（留空 = 使用内置默认提示词）": "(vacío = prompt integrado)",
        "Token 用量": "Uso de tokens", "调用次数": "Llamadas", "输入": "Entrada",
        "输出": "Salida", "合计": "Total", "暂无用量记录": "Sin uso",
        "最近更新：%@": "Actualizado: %@", "语言": "Idioma", "跟随系统": "Sistema",
        "需要重新启动 App 以应用语言。": "Reinicia la app para aplicar el idioma.", "关于": "Acerca de", "CatchMeUp · 原生 macOS 任务助理": "CatchMeUp · asistente de tareas para macOS",
        "截图 / 文字 / 文件 / 文件夹 / 网址 → 自动整理为素材与待办，支持提醒、日历与任务交接。": "Captura / texto / archivo / carpeta / URL → elementos y tareas, con recordatorios, calendario y handoff.", "数据全部保存在本机，仅整理时调用 DeepSeek。": "Todo se guarda localmente; DeepSeek solo se usa al organizar.", "素材详情": "Detalle",
        "摘要": "Resumen", "原始内容": "Contenido original", "本地文件": "Archivo local",
        "根据来源内容重新分析这条素材": "Reanalizar desde el origen", "(无标题)": "(Sin título)", "正在整理文本…": "Organizando texto…",
        "正在抓取网页…": "Descargando página…", "正在读取…": "Leyendo…", "正在识别图片…": "Reconociendo imagen…",
        "请框选截图区域…": "Selecciona una región…", "正在生成交接摘要…": "Generando handoff…", "正在增量更新交接…": "Actualizando handoff…",
        "正在刷新…": "Actualizando…", "保存任务…": "Guardando…", "创建任务…": "Creando…",
        "开启新 Session…": "Iniciando sesión…", "结束 Session 并生成交接…": "Terminando sesión…", "测试 DeepSeek 连接…": "Probando DeepSeek…",
        "已整理「%@」": "Organizado «%@»", "已整理「%@」，生成 %d 条待办": "Organizado «%@», %d tarea(s)", "已整理「%@」，含交接；%d 条待办": "Organizado «%@» con handoff; %d tarea(s)",
        "已抓取「%@」": "Descargado «%@»", "任务已保存": "Tarea guardada", "任务已创建": "Tarea creada",
        "已完成「%@」": "Completada «%@»", "已恢复「%@」": "Reabierta «%@»", "已添加「%@」": "Añadida «%@»",
        "已取消「%@」": "Cancelada «%@»", "已删除任务": "Tarea eliminada", "已删除素材及其关联任务": "Elemento y tareas eliminados",
        "已改期到 %@": "Reprogramada a %@", "已清除截止时间": "Fecha borrada", "交接摘要已生成": "Handoff generado",
        "Session 已结束": "Sesión finalizada", "已开启新 Session": "Sesión iniciada", "已更新「%@」的交接": "Handoff de «%@» actualizado",
        "已刷新「%@」": "«%@» actualizado", "设置已保存": "Ajustes guardados", "已重置 Token 统计": "Uso de tokens reiniciado",
        "交接摘要已复制到剪贴板": "Handoff copiado", "测试通知将在 3 秒后弹出": "Notificación de prueba en 3 s", "DeepSeek 连接正常（%@）": "DeepSeek OK (%@)",
        "截图已取消": "Captura cancelada", "剪贴板里没有可识别的内容": "Nada reconocible en el portapapeles", "截图快捷键已更新为 %@": "Atajo de captura: %@",
        "截图快捷键已恢复默认（%@）": "Atajo de captura restablecido (%@)", "该快捷键可能已被其它 App 占用，已保留原设置": "Atajo ocupado por otra app; se mantiene el anterior", "设置开机启动失败：%@（需以 .app 形式运行）": "No se pudo activar al inicio: %@ (ejecuta como .app)",
        "无截止时间": "Sin vencimiento", "已过期": "Vencida", "即将": "Pronto",
        "%d 分钟前": "hace %dm", "%d 分钟后": "en %dm", "%d 小时前": "hace %dh",
        "%d 小时后": "en %dh", "%d 天前": "hace %dd", "%d 天后": "en %dd",
        "今天 %@": "Hoy %@", "明天 %@": "Mañana %@", "昨天 %@": "Ayer %@",
        "截止 %@": "Vence %@", "未配置 DeepSeek API Key，请在设置中填写。": "Falta la clave API de DeepSeek. Añádela en Ajustes.", "DeepSeek 接口错误：%@": "Error de DeepSeek: %@",
        "返回内容无法解析：%@": "Respuesta ilegible: %@", "读取失败：%@": "Error de lectura: %@", "未找到：%@": "No encontrado: %@",
        "无法初始化数据库：%@": "No se pudo abrir la base de datos: %@", "无法打开数据库：%@": "No se puede abrir la base de datos: %@", "文件不存在：%@": "Archivo no encontrado: %@",
        "文件夹不存在：%@": "Carpeta no encontrada: %@", "无法读取图片：%@": "No se puede leer la imagen: %@", "无效网址：%@": "URL no válida: %@",
        "抓取失败，状态码 %d": "Fallo al descargar, estado %d", "无 HTTP 响应": "Sin respuesta HTTP", "空响应（finish_reason=%@）": "Respuesta vacía (finish_reason=%@)",
        "响应被截断，自动扩容重试": "Respuesta truncada; reintentando con más margen", "路径不存在：%@": "Ruta no encontrada: %@", "文本": "Texto",
        "截图": "Captura", "文件": "Archivo", "文件夹": "Carpeta",
        "网址": "URL",
        "任务提醒 · %@": "Recordatorio · %@", "(整理失败：%@)": "(Error al organizar: %@)", "%d 条已逾期": "%d vencidas", "框选截图（全局快捷键 %@）": "Capturar región (%@)", "%d 条": "%d elementos", "… 还有 %d 条": "…y %d más", "%d 次 · %@ tokens": "%d llamadas · %@ tokens",
        "连接正常（%@）": "Conectado (%@)",
        "AI 提供商": "Proveedor de IA", "提供商": "Proveedor",
        "待办": "Pendientes", "今日待办": "Tareas de hoy", "生成今日待办": "Sugerir tareas de hoy", "正在生成今日待办…": "Generando tareas de hoy…", "AI 推荐": "Sugerencias de IA", "推荐待办": "Tareas sugeridas", "全部添加": "Añadir todo", "新建待办，回车即可": "Añade una tarea y pulsa Intro", "暂无待办": "Sin tareas", "已删除待办": "Tarea eliminada", "未完成（往日）": "Pendientes (anteriores)", "今日已完成": "Hechas hoy", "绑定任务": "Vincular tarea", "解除绑定": "Desvincular", "已绑定到「%@」": "Vinculada a «%@»", "已解除绑定": "Desvinculada", "已生成 %d 条推荐": "%d sugerencia(s)", "暂无推荐": "Sin sugerencias", "关联任务：%@": "Tarea: %@", "来源：AI": "De la IA",
    ]

    static let ja: [String: String] = [
        "工作台": "ワークスペース", "任务": "タスク", "任务交接": "引き継ぎ",
        "日历": "カレンダー", "定时任务": "スケジュール", "设置": "設定",
        "素材": "アイテム", "保存": "保存", "取消": "キャンセル",
        "删除": "削除", "关闭": "閉じる", "编辑": "編集",
        "创建": "作成", "添加": "追加", "修改": "変更",
        "默认": "デフォルト", "刷新": "更新", "重置": "リセット",
        "清空": "クリア", "填入默认": "既定を使用", "全部": "すべて",
        "新建": "新規", "更新": "更新", "恢复": "再開",
        "退出": "終了", "打开主窗口": "メインウィンドウを開く", "打开日历": "カレンダーを開く",
        "在访达中显示": "Finder に表示", "打开系统设置": "システム設定を開く", "请求授权": "許可を要求",
        "重新检查状态": "状態を再確認", "复制为 Markdown": "Markdown としてコピー", "查看来源素材": "元アイテムを表示",
        "同步到系统日历": "カレンダーに同期", "设置 / 修改截止时间": "締切を設定 / 変更", "输入文字 / 网址 / 文件路径，或把文件、截图直接拖进来（⌘V 可粘贴截图）": "テキスト / URL / パスを入力、ファイルやスクショをドロップ（⌘V で貼り付け）",
        "添加文件 / 文件夹 / 图片": "ファイル / フォルダ / 画像を追加", "框选截图": "範囲をキャプチャ", "可选：补充说明（帮助 AI 理解上下文）": "補足（任意・AI の理解を助ける）",
        "整理": "整理", "自动": "自動", "交接": "引き継ぎ",
        "搜索素材": "アイテムを検索", "搜索": "検索", "切换卡片 / 列表": "カード / リスト切替",
        "未完成": "未完了", "今日到期": "今日締切", "近 7 天": "7 日以内",
        "已逾期": "期限切れ", "在上面输入、粘贴或拖入内容开始": "上に入力・貼り付け・ドロップで開始", "在上面输入一句话，回车即创建": "上に一行入力し Return で作成",
        "还没有素材": "アイテムがありません", "没有匹配的素材": "一致なし", "换个关键词试试": "別の語で検索",
        "自动：文本/截图→任务，目录→交接 · 任务：抽取截止时间 · 交接：项目梳理": "自動：テキスト/スクショ→タスク、フォルダ→引き継ぎ · タスク：締切抽出 · 引き継ぎ：整理", "今天": "今日", "明天": "明日",
        "本周内": "今週", "以后": "以降", "无日期": "日付なし",
        "已完成": "完了", "添加任务，回车即可": "タスクを入力し Return", "标记完成": "完了にする",
        "取消任务": "タスクを取消", "今天 18:00": "今日 18:00", "明天 09:00": "明日 09:00",
        "下周一 09:00": "来週月曜 09:00", "本周六 10:00": "今週土曜 10:00", "清除日期": "日付を削除",
        "自定义…": "カスタム…", "显示已完成": "完了を表示", "新建一条带细节的任务": "詳細付きのタスクを作成",
        "还没有任务": "タスクがありません", "没有匹配的任务": "一致なし", "相关素材": "関連アイテム",
        "关联任务": "関連タスク", "没有带任务的素材": "タスク付きのアイテムなし", "捕获含截止时间的内容，任务会挂到对应素材下": "締切を含む内容を取り込むとタスクが紐づきます",
        "新建任务": "新規タスク", "编辑任务": "タスクを編集", "任务标题": "タイトル",
        "描述（可选）": "説明（任意）", "截止时间": "締切", "重复": "繰り返し",
        "优先级": "優先度", "不重复": "なし", "每天": "毎日",
        "每周": "毎週", "每月": "毎月", "低": "低",
        "普通": "普通", "高": "高", "紧急": "緊急",
        "待处理": "未着手", "进行中": "進行中", "已取消": "取消済",
        "优先级：%@": "優先度：%@", "操作": "操作", "生成交接摘要": "引き継ぎを生成",
        "开启新 Session": "セッション開始", "结束当前 Session": "セッション終了", "Session 主题（可选）": "セッション名（任意）",
        "补充上下文（最近重点 / 卡点 / 背景，可选）": "追加コンテキスト（任意）", "交接素材": "引き継ぎアイテム", "最新交接摘要": "最新の引き継ぎ",
        "还没有交接素材": "引き継ぎアイテムがありません", "把项目、目录或工作小结用「交接」模式整理，就会出现在这里": "プロジェクトやフォルダ、作業メモを「引き継ぎ」モードで整理するとここに表示されます", "目标": "目標",
        "整体逻辑": "全体像", "进展": "進捗", "下一步": "次の一手",
        "风险": "リスク", "风险 / 未决问题": "リスク / 未解決", "历史 Session（%d）": "過去のセッション（%d）",
        "未命名": "無題", "增量更新这份交接": "この引き継ぎを差分更新", "未来 30 天的日历日程": "今後 30 日の予定",
        "带截止时间的任务会自动写入日历": "締切付きタスクは自動でカレンダーに書き込みます", "请先授权日历访问": "先にカレンダーへのアクセスを許可してください", "授权日历访问": "カレンダーを許可",
        "暂无日程": "予定なし", "待触发的提醒": "予約されたリマインダー", "暂无调度中的提醒": "予約はありません",
        "测试": "テスト", "发送一条测试通知（3 秒后）": "テスト通知を送信（3 秒後）", "发送测试通知": "テスト通知を送信",
        "提醒规则": "ルール", "已调度的本地通知。即使关闭 App，系统仍会按时提醒。": "予約されたローカル通知。アプリを閉じても通知されます。", "任务设置截止时间后，默认在截止前 %d 分钟提醒": "締切の %d 分前に通知します",
        "重复任务（每天/每周/每月）会按周期重复提醒": "繰り返しタスクは周期ごとに通知", "可在设置中调整提前量和是否写入日历": "設定で通知タイミングとカレンダー連携を変更できます", "模型、权限与提醒设置": "モデル・権限・リマインダー",
        "测试连接": "接続テスト", "保存在本机应用目录的 secrets.json（仅当前用户可读），不使用系统钥匙串，因此不会弹授权。": "アプリのローカル secrets.json に保存（自分のみ閲覧可）。キーチェーンは使わず、許可ダイアログも出ません。", "deepseek-flash（支持图片，推荐）": "deepseek-flash（画像対応・推奨）",
        "deepseek-v4-pro（纯文本）": "deepseek-v4-pro（テキストのみ）", "提醒": "リマインダー", "默认提前 %d 分钟提醒": "既定で %d 分前に通知",
        "把带截止时间的任务写入系统日历": "締切付きタスクをカレンダーに書き込む", "权限": "権限", "权限只在下面主动点击时申请，App 启动时不会自动弹窗。": "権限は下のボタンを押したときだけ要求されます。起動時には何も出ません。",
        "通知": "通知", "屏幕录制（截图）": "画面収録（スクショ）", "已授权": "許可済み",
        "未授权": "未許可", "已拒绝": "拒否", "受限": "制限",
        "仅写入": "書き込みのみ", "未知": "不明", "通用": "一般",
        "开机自动启动": "ログイン時に起動", "截图快捷键": "スクショのショートカット", "请按下组合键（Esc 取消）": "キーを押してください（Esc で取消）",
        "数据目录": "データフォルダ", "提示词（高级）": "プロンプト（詳細）", "留空表示使用内置默认提示词；修改后点「保存」生效。": "空欄なら内蔵プロンプトを使用。変更後は「保存」で反映。",
        "整理提示词（任务 / 交接）": "整理プロンプト（タスク / 引き継ぎ）", "交接摘要提示词": "引き継ぎプロンプト", "（留空 = 使用内置默认提示词）": "（空欄 = 内蔵プロンプト）",
        "Token 用量": "トークン使用量", "调用次数": "呼び出し", "输入": "入力",
        "输出": "出力", "合计": "合計", "暂无用量记录": "記録なし",
        "最近更新：%@": "更新：%@", "语言": "言語", "跟随系统": "システムに従う",
        "需要重新启动 App 以应用语言。": "言語を反映するにはアプリを再起動してください。", "关于": "このアプリ", "CatchMeUp · 原生 macOS 任务助理": "CatchMeUp · macOS ネイティブのタスクアシスタント",
        "截图 / 文字 / 文件 / 文件夹 / 网址 → 自动整理为素材与待办，支持提醒、日历与任务交接。": "スクショ / テキスト / ファイル / フォルダ / URL → アイテムとタスクに整理。通知・カレンダー・引き継ぎ対応。", "数据全部保存在本机，仅整理时调用 DeepSeek。": "データはすべてローカル。DeepSeek は整理時のみ呼び出します。", "素材详情": "アイテム詳細",
        "摘要": "要約", "原始内容": "元の内容", "本地文件": "ローカルファイル",
        "根据来源内容重新分析这条素材": "元データから再解析", "(无标题)": "（無題）", "正在整理文本…": "テキストを整理中…",
        "正在抓取网页…": "ページを取得中…", "正在读取…": "読み込み中…", "正在识别图片…": "画像を認識中…",
        "请框选截图区域…": "範囲を選択してください…", "正在生成交接摘要…": "引き継ぎを生成中…", "正在增量更新交接…": "引き継ぎを更新中…",
        "正在刷新…": "更新中…", "保存任务…": "保存中…", "创建任务…": "作成中…",
        "开启新 Session…": "セッション開始中…", "结束 Session 并生成交接…": "セッション終了中…", "测试 DeepSeek 连接…": "DeepSeek 接続テスト中…",
        "已整理「%@」": "「%@」を整理しました", "已整理「%@」，生成 %d 条待办": "「%@」を整理、%d 件のタスク", "已整理「%@」，含交接；%d 条待办": "「%@」を整理（引き継ぎ付き）、%d 件",
        "已抓取「%@」": "「%@」を取得しました", "任务已保存": "タスクを保存しました", "任务已创建": "タスクを作成しました",
        "已完成「%@」": "「%@」を完了", "已恢复「%@」": "「%@」を再開", "已添加「%@」": "「%@」を追加",
        "已取消「%@」": "「%@」を取消", "已删除任务": "タスクを削除", "已删除素材及其关联任务": "アイテムと関連タスクを削除",
        "已改期到 %@": "%@ に変更", "已清除截止时间": "締切を削除", "交接摘要已生成": "引き継ぎを生成しました",
        "Session 已结束": "セッション終了", "已开启新 Session": "セッションを開始しました", "已更新「%@」的交接": "「%@」の引き継ぎを更新",
        "已刷新「%@」": "「%@」を更新", "设置已保存": "設定を保存しました", "已重置 Token 统计": "トークン統計をリセット",
        "交接摘要已复制到剪贴板": "クリップボードにコピー", "测试通知将在 3 秒后弹出": "テスト通知は 3 秒後", "DeepSeek 连接正常（%@）": "DeepSeek 正常（%@）",
        "截图已取消": "キャプチャを取消", "剪贴板里没有可识别的内容": "クリップボードに認識可能な内容なし", "截图快捷键已更新为 %@": "ショートカットを %@ に更新",
        "截图快捷键已恢复默认（%@）": "ショートカットを既定に戻しました（%@）", "该快捷键可能已被其它 App 占用，已保留原设置": "他のアプリが使用中。以前の設定を保持します", "设置开机启动失败：%@（需以 .app 形式运行）": "自動起動の設定に失敗：%@（.app で実行してください）",
        "无截止时间": "締切なし", "已过期": "期限切れ", "即将": "まもなく",
        "%d 分钟前": "%d 分前", "%d 分钟后": "%d 分後", "%d 小时前": "%d 時間前",
        "%d 小时后": "%d 時間後", "%d 天前": "%d 日前", "%d 天后": "%d 日後",
        "今天 %@": "今日 %@", "明天 %@": "明日 %@", "昨天 %@": "昨日 %@",
        "截止 %@": "締切 %@", "未配置 DeepSeek API Key，请在设置中填写。": "DeepSeek API キーが未設定です。設定で入力してください。", "DeepSeek 接口错误：%@": "DeepSeek エラー：%@",
        "返回内容无法解析：%@": "解析できません：%@", "读取失败：%@": "読み込み失敗：%@", "未找到：%@": "見つかりません：%@",
        "无法初始化数据库：%@": "データベースを初期化できません：%@", "无法打开数据库：%@": "データベースを開けません：%@", "文件不存在：%@": "ファイルがありません：%@",
        "文件夹不存在：%@": "フォルダがありません：%@", "无法读取图片：%@": "画像を読み込めません：%@", "无效网址：%@": "無効な URL：%@",
        "抓取失败，状态码 %d": "取得失敗、ステータス %d", "无 HTTP 响应": "HTTP 応答なし", "空响应（finish_reason=%@）": "空の応答（finish_reason=%@）",
        "响应被截断，自动扩容重试": "応答が切れたため拡張して再試行", "路径不存在：%@": "パスがありません：%@", "文本": "テキスト",
        "截图": "スクショ", "文件": "ファイル", "文件夹": "フォルダ",
        "网址": "URL",
        "任务提醒 · %@": "タスク通知 · %@", "(整理失败：%@)": "（整理に失敗：%@）", "%d 条已逾期": "期限切れ %d 件", "框选截图（全局快捷键 %@）": "範囲をキャプチャ（%@）", "%d 条": "%d 件", "… 还有 %d 条": "…他 %d 件", "%d 次 · %@ tokens": "%d 回 · %@ トークン",
        "连接正常（%@）": "接続OK（%@）",
        "AI 提供商": "AI プロバイダー", "提供商": "プロバイダー",
        "待办": "やること", "今日待办": "今日のやること", "生成今日待办": "今日のやることを提案", "正在生成今日待办…": "今日のやることを生成中…", "AI 推荐": "AI 提案", "推荐待办": "提案されたやること", "全部添加": "すべて追加", "新建待办，回车即可": "やることを入力して Return", "暂无待办": "やることなし", "已删除待办": "やることを削除", "未完成（往日）": "未完了（過去）", "今日已完成": "今日の完了", "绑定任务": "タスクを紐付け", "解除绑定": "紐付け解除", "已绑定到「%@」": "「%@」に紐付け", "已解除绑定": "紐付けを解除", "已生成 %d 条推荐": "%d 件の提案", "暂无推荐": "提案なし", "关联任务：%@": "タスク：%@", "来源：AI": "AI 由来",
    ]

    static let ko: [String: String] = [
        "工作台": "워크스페이스", "任务": "작업", "任务交接": "인수인계",
        "日历": "캘린더", "定时任务": "예약", "设置": "설정",
        "素材": "항목", "保存": "저장", "取消": "취소",
        "删除": "삭제", "关闭": "닫기", "编辑": "편집",
        "创建": "생성", "添加": "추가", "修改": "변경",
        "默认": "기본값", "刷新": "새로고침", "重置": "초기화",
        "清空": "비우기", "填入默认": "기본값 사용", "全部": "전체",
        "新建": "새로 만들기", "更新": "업데이트", "恢复": "다시 열기",
        "退出": "종료", "打开主窗口": "메인 창 열기", "打开日历": "캘린더 열기",
        "在访达中显示": "Finder에서 보기", "打开系统设置": "시스템 설정 열기", "请求授权": "권한 요청",
        "重新检查状态": "상태 다시 확인", "复制为 Markdown": "Markdown으로 복사", "查看来源素材": "원본 항목 보기",
        "同步到系统日历": "캘린더에 동기화", "设置 / 修改截止时间": "마감 설정 / 변경", "输入文字 / 网址 / 文件路径，或把文件、截图直接拖进来（⌘V 可粘贴截图）": "텍스트 / URL / 경로를 입력하거나 파일·스크린샷을 끌어다 놓으세요 (⌘V 붙여넣기)",
        "添加文件 / 文件夹 / 图片": "파일 / 폴더 / 이미지 추가", "框选截图": "영역 캡처", "可选：补充说明（帮助 AI 理解上下文）": "선택: 보충 설명",
        "整理": "정리", "自动": "자동", "交接": "인수인계",
        "搜索素材": "항목 검색", "搜索": "검색", "切换卡片 / 列表": "카드 / 목록 전환",
        "未完成": "미완료", "今日到期": "오늘 마감", "近 7 天": "7일 이내",
        "已逾期": "지남", "在上面输入、粘贴或拖入内容开始": "위에 입력·붙여넣기·드롭하여 시작", "在上面输入一句话，回车即创建": "위에 한 줄 입력 후 Return으로 생성",
        "还没有素材": "항목 없음", "没有匹配的素材": "일치 항목 없음", "换个关键词试试": "다른 검색어 시도",
        "自动：文本/截图→任务，目录→交接 · 任务：抽取截止时间 · 交接：项目梳理": "자동: 텍스트/스크린샷 → 작업, 폴더 → 인수인계 · 작업: 마감 추출 · 인수인계: 정리", "今天": "오늘", "明天": "내일",
        "本周内": "이번 주", "以后": "나중에", "无日期": "날짜 없음",
        "已完成": "완료", "添加任务，回车即可": "작업을 입력하고 Return", "标记完成": "완료 표시",
        "取消任务": "작업 취소", "今天 18:00": "오늘 18:00", "明天 09:00": "내일 09:00",
        "下周一 09:00": "다음 주 월요일 09:00", "本周六 10:00": "이번 주 토요일 10:00", "清除日期": "날짜 지우기",
        "自定义…": "사용자 지정…", "显示已完成": "완료 표시", "新建一条带细节的任务": "상세 작업 만들기",
        "还没有任务": "작업 없음", "没有匹配的任务": "일치 작업 없음", "相关素材": "관련 항목",
        "关联任务": "연결된 작업", "没有带任务的素材": "작업이 있는 항목 없음", "捕获含截止时间的内容，任务会挂到对应素材下": "마감이 있는 내용을 담으면 항목에 작업이 연결됩니다",
        "新建任务": "새 작업", "编辑任务": "작업 편집", "任务标题": "제목",
        "描述（可选）": "설명 (선택)", "截止时间": "마감", "重复": "반복",
        "优先级": "우선순위", "不重复": "없음", "每天": "매일",
        "每周": "매주", "每月": "매월", "低": "낮음",
        "普通": "보통", "高": "높음", "紧急": "긴급",
        "待处理": "대기", "进行中": "진행 중", "已取消": "취소됨",
        "优先级：%@": "우선순위: %@", "操作": "작업", "生成交接摘要": "인수인계 생성",
        "开启新 Session": "세션 시작", "结束当前 Session": "세션 종료", "Session 主题（可选）": "세션 주제 (선택)",
        "补充上下文（最近重点 / 卡点 / 背景，可选）": "추가 맥락 (선택)", "交接素材": "인수인계 항목", "最新交接摘要": "최신 인수인계",
        "还没有交接素材": "인수인계 항목 없음", "把项目、目录或工作小结用「交接」模式整理，就会出现在这里": "프로젝트·폴더·작업 요약을 '인수인계' 모드로 정리하면 여기에 표시됩니다", "目标": "목표",
        "整体逻辑": "접근", "进展": "진행", "下一步": "다음 단계",
        "风险": "위험", "风险 / 未决问题": "위험 / 미결", "历史 Session（%d）": "지난 세션 (%d)",
        "未命名": "제목 없음", "增量更新这份交接": "이 인수인계를 증분 업데이트", "未来 30 天的日历日程": "향후 30일 일정",
        "带截止时间的任务会自动写入日历": "마감이 있는 작업은 캘린더에 자동 기록됩니다", "请先授权日历访问": "먼저 캘린더 접근을 허용하세요", "授权日历访问": "캘린더 허용",
        "暂无日程": "일정 없음", "待触发的提醒": "예약된 알림", "暂无调度中的提醒": "예약된 알림 없음",
        "测试": "테스트", "发送一条测试通知（3 秒后）": "테스트 알림 보내기 (3초 후)", "发送测试通知": "테스트 알림 보내기",
        "提醒规则": "규칙", "已调度的本地通知。即使关闭 App，系统仍会按时提醒。": "예약된 로컬 알림. 앱을 종료해도 알림이 표시됩니다.", "任务设置截止时间后，默认在截止前 %d 分钟提醒": "마감 %d분 전에 알림",
        "重复任务（每天/每周/每月）会按周期重复提醒": "반복 작업은 주기에 따라 알림", "可在设置中调整提前量和是否写入日历": "설정에서 알림 시점과 캘린더 연동을 변경하세요", "模型、权限与提醒设置": "모델·권한·알림 설정",
        "测试连接": "연결 테스트", "保存在本机应用目录的 secrets.json（仅当前用户可读），不使用系统钥匙串，因此不会弹授权。": "앱 로컬 secrets.json에 저장 (본인만 읽기). 키체인 미사용, 권한 창 없음.", "deepseek-flash（支持图片，推荐）": "deepseek-flash (이미지 지원, 권장)",
        "deepseek-v4-pro（纯文本）": "deepseek-v4-pro (텍스트 전용)", "提醒": "알림", "默认提前 %d 分钟提醒": "기본 %d분 전 알림",
        "把带截止时间的任务写入系统日历": "마감이 있는 작업을 캘린더에 기록", "权限": "권한", "权限只在下面主动点击时申请，App 启动时不会自动弹窗。": "권한은 아래 버튼을 눌렀을 때만 요청됩니다. 실행 시에는 아무 창도 뜨지 않습니다.",
        "通知": "알림", "屏幕录制（截图）": "화면 기록 (스크린샷)", "已授权": "허용됨",
        "未授权": "미허용", "已拒绝": "거부됨", "受限": "제한됨",
        "仅写入": "쓰기만", "未知": "알 수 없음", "通用": "일반",
        "开机自动启动": "로그인 시 실행", "截图快捷键": "스크린샷 단축키", "请按下组合键（Esc 取消）": "키를 누르세요 (Esc 취소)",
        "数据目录": "데이터 폴더", "提示词（高级）": "프롬프트 (고급)", "留空表示使用内置默认提示词；修改后点「保存」生效。": "비우면 내장 프롬프트 사용, 저장을 눌러 적용하세요.",
        "整理提示词（任务 / 交接）": "정리 프롬프트 (작업 / 인수인계)", "交接摘要提示词": "인수인계 프롬프트", "（留空 = 使用内置默认提示词）": "(비움 = 내장 프롬프트)",
        "Token 用量": "토큰 사용량", "调用次数": "호출", "输入": "입력",
        "输出": "출력", "合计": "합계", "暂无用量记录": "기록 없음",
        "最近更新：%@": "업데이트: %@", "语言": "언어", "跟随系统": "시스템 따르기",
        "需要重新启动 App 以应用语言。": "언어를 적용하려면 앱을 다시 시작하세요.", "关于": "정보", "CatchMeUp · 原生 macOS 任务助理": "CatchMeUp · macOS 네이티브 작업 도우미",
        "截图 / 文字 / 文件 / 文件夹 / 网址 → 自动整理为素材与待办，支持提醒、日历与任务交接。": "스크린샷 / 텍스트 / 파일 / 폴더 / URL → 항목과 작업으로 정리. 알림·캘린더·인수인계 지원.", "数据全部保存在本机，仅整理时调用 DeepSeek。": "모든 데이터는 로컬에 저장되며 정리 시에만 DeepSeek을 호출합니다.", "素材详情": "항목 상세",
        "摘要": "요약", "原始内容": "원본", "本地文件": "로컬 파일",
        "根据来源内容重新分析这条素材": "원본에서 다시 분석", "(无标题)": "(제목 없음)", "正在整理文本…": "텍스트 정리 중…",
        "正在抓取网页…": "웹 페이지 가져오는 중…", "正在读取…": "읽는 중…", "正在识别图片…": "이미지 인식 중…",
        "请框选截图区域…": "화면 영역을 선택하세요…", "正在生成交接摘要…": "인수인계 생성 중…", "正在增量更新交接…": "인수인계 업데이트 중…",
        "正在刷新…": "새로고침 중…", "保存任务…": "저장 중…", "创建任务…": "생성 중…",
        "开启新 Session…": "세션 시작 중…", "结束 Session 并生成交接…": "세션 종료 중…", "测试 DeepSeek 连接…": "DeepSeek 연결 테스트 중…",
        "已整理「%@」": "「%@」 정리됨", "已整理「%@」，生成 %d 条待办": "「%@」 정리, %d개 작업", "已整理「%@」，含交接；%d 条待办": "「%@」 정리(인수인계 포함), %d개 작업",
        "已抓取「%@」": "「%@」 가져옴", "任务已保存": "작업 저장됨", "任务已创建": "작업 생성됨",
        "已完成「%@」": "「%@」 완료", "已恢复「%@」": "「%@」 다시 열기", "已添加「%@」": "「%@」 추가",
        "已取消「%@」": "「%@」 취소", "已删除任务": "작업 삭제됨", "已删除素材及其关联任务": "항목과 연결 작업 삭제됨",
        "已改期到 %@": "%@(으)로 변경", "已清除截止时间": "마감 삭제됨", "交接摘要已生成": "인수인계 생성됨",
        "Session 已结束": "세션 종료됨", "已开启新 Session": "새 세션 시작됨", "已更新「%@」的交接": "「%@」 인수인계 업데이트됨",
        "已刷新「%@」": "「%@」 새로고침됨", "设置已保存": "설정 저장됨", "已重置 Token 统计": "토큰 통계 초기화됨",
        "交接摘要已复制到剪贴板": "클립보드에 복사됨", "测试通知将在 3 秒后弹出": "테스트 알림 3초 후", "DeepSeek 连接正常（%@）": "DeepSeek 정상 (%@)",
        "截图已取消": "캡처 취소됨", "剪贴板里没有可识别的内容": "클립보드에 인식할 내용 없음", "截图快捷键已更新为 %@": "스크린샷 단축키: %@",
        "截图快捷键已恢复默认（%@）": "스크린샷 단축키 기본값 복원 (%@)", "该快捷键可能已被其它 App 占用，已保留原设置": "다른 앱이 사용 중일 수 있어 이전 설정 유지", "设置开机启动失败：%@（需以 .app 形式运行）": "자동 실행 설정 실패: %@ (.app으로 실행 필요)",
        "无截止时间": "마감 없음", "已过期": "지남", "即将": "곧",
        "%d 分钟前": "%d분 전", "%d 分钟后": "%d분 후", "%d 小时前": "%d시간 전",
        "%d 小时后": "%d시간 후", "%d 天前": "%d일 전", "%d 天后": "%d일 후",
        "今天 %@": "오늘 %@", "明天 %@": "내일 %@", "昨天 %@": "어제 %@",
        "截止 %@": "마감 %@", "未配置 DeepSeek API Key，请在设置中填写。": "DeepSeek API 키가 없습니다. 설정에서 입력하세요.", "DeepSeek 接口错误：%@": "DeepSeek 오류: %@",
        "返回内容无法解析：%@": "응답을 해석할 수 없음: %@", "读取失败：%@": "읽기 실패: %@", "未找到：%@": "찾을 수 없음: %@",
        "无法初始化数据库：%@": "데이터베이스 초기화 실패: %@", "无法打开数据库：%@": "데이터베이스를 열 수 없음: %@", "文件不存在：%@": "파일 없음: %@",
        "文件夹不存在：%@": "폴더 없음: %@", "无法读取图片：%@": "이미지를 읽을 수 없음: %@", "无效网址：%@": "잘못된 URL: %@",
        "抓取失败，状态码 %d": "가져오기 실패, 상태 %d", "无 HTTP 响应": "HTTP 응답 없음", "空响应（finish_reason=%@）": "빈 응답 (finish_reason=%@)",
        "响应被截断，自动扩容重试": "응답이 잘려 재시도 중", "路径不存在：%@": "경로 없음: %@", "文本": "텍스트",
        "截图": "스크린샷", "文件": "파일", "文件夹": "폴더",
        "网址": "URL",
        "任务提醒 · %@": "작업 알림 · %@", "(整理失败：%@)": "(정리 실패: %@)", "%d 条已逾期": "지남 %d개", "框选截图（全局快捷键 %@）": "영역 캡처 (%@)", "%d 条": "%d개", "… 还有 %d 条": "…외 %d개", "%d 次 · %@ tokens": "%d회 · %@ 토큰",
        "连接正常（%@）": "연결 정상 (%@)",
        "AI 提供商": "AI 제공자", "提供商": "제공자",
        "待办": "할 일", "今日待办": "오늘 할 일", "生成今日待办": "오늘 할 일 추천", "正在生成今日待办…": "오늘 할 일 생성 중…", "AI 推荐": "AI 추천", "推荐待办": "추천 할 일", "全部添加": "모두 추가", "新建待办，回车即可": "할 일 입력 후 Return", "暂无待办": "할 일 없음", "已删除待办": "할 일 삭제됨", "未完成（往日）": "미완료(이전)", "今日已完成": "오늘 완료", "绑定任务": "작업 연결", "解除绑定": "연결 해제", "已绑定到「%@」": "「%@」에 연결됨", "已解除绑定": "연결 해제됨", "已生成 %d 条推荐": "%d개 추천", "暂无推荐": "추천 없음", "关联任务：%@": "작업: %@", "来源：AI": "AI 생성",
    ]
}
