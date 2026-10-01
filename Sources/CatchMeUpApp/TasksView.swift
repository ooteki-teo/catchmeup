import SwiftUI
import CatchMeUpCore

struct TasksView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow

    private enum Tab: String, CaseIterable, Identifiable {
        case tasks, items
        var id: String { rawValue }
        var title: String { self == .tasks ? "任务" : "按素材" }
    }

    @State private var tab: Tab = .tasks
    @State private var layout: CollectionLayout = .list
    @State private var editing: TaskItem?
    @State private var showingNew = false

    private var query: String { store.taskSearch.trimmingCharacters(in: .whitespaces).lowercased() }

    private var itemsWithTasks: [Item] {
        guard !query.isEmpty else { return store.itemsWithTasks }
        return store.itemsWithTasks.filter { item in
            (item.title ?? "").lowercased().contains(query)
                || (item.summary ?? "").lowercased().contains(query)
                || store.tasks(for: item.id).contains { $0.title.lowercased().contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            switch tab {
            case .tasks:
                TaskListView(onEdit: { editing = $0 })
            case .items:
                itemsContent
            }
        }
        .sheet(isPresented: $showingNew) {
            TaskEditor(task: nil).environmentObject(store)
        }
        .sheet(item: $editing) { task in
            TaskEditor(task: task).environmentObject(store)
        }
        .onChange(of: store.taskShowCompleted) { _, _ in Task { await store.refresh() } }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            TextField("搜索", text: $store.taskSearch)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            if store.stats.overdue > 0 {
                Label("\(store.stats.overdue) 条已逾期", systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.12)))
            }

            Toggle("显示已完成", isOn: $store.taskShowCompleted)
                .toggleStyle(.checkbox)

            Spacer()

            if tab == .items { ViewModeToggle(mode: $layout) }

            Button { showingNew = true } label: {
                Label("新建", systemImage: "plus")
            }
            .help("新建一条带细节的任务")
        }
        .padding(12)
    }

    @ViewBuilder
    private var itemsContent: some View {
        if itemsWithTasks.isEmpty {
            EmptyState(icon: "checklist", title: "没有带任务的素材",
                       subtitle: "捕获含截止时间的内容，任务会挂到对应素材下")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text("相关素材").font(.headline)
                        Text("\(itemsWithTasks.count)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    if layout == .cards {
                        ItemCardGrid(items: itemsWithTasks,
                                     tasksProvider: { store.tasks(for: $0.id) },
                                     onOpen: { openWindow(id: "item-detail", value: $0.id) })
                    } else {
                        VStack(spacing: 10) {
                            ForEach(itemsWithTasks) { item in
                                ItemBlockView(item: item,
                                              tasks: store.tasks(for: item.id),
                                              style: .list,
                                              onOpen: { openWindow(id: "item-detail", value: item.id) },
                                              onToggleTask: { toggle($0) })
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func toggle(_ task: TaskItem) {
        Task { task.status == .done ? await store.reopen(task) : await store.complete(task) }
    }
}

// MARK: - Flat, date-grouped task list

enum TaskBucket: Int, CaseIterable, Identifiable {
    case overdue, today, tomorrow, thisWeek, later, noDate, done
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overdue: return "已逾期"
        case .today: return "今天"
        case .tomorrow: return "明天"
        case .thisWeek: return "本周内"
        case .later: return "以后"
        case .noDate: return "无日期"
        case .done: return "已完成"
        }
    }

    var tint: Color {
        switch self {
        case .overdue: return .red
        case .today: return .blue
        case .tomorrow: return .indigo
        case .thisWeek: return .teal
        case .later: return .secondary
        case .noDate: return .secondary
        case .done: return .secondary
        }
    }
}

enum QuickDue {
    static func today() -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 18; comps.minute = 0
        let candidate = cal.date(from: comps) ?? now
        return candidate > now ? candidate : now.addingTimeInterval(2 * 3600)
    }
    static func tomorrow() -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
    }
    static func nextWeek() -> Date {
        let cal = Calendar.current
        return cal.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0, weekday: 2),
                            matchingPolicy: .nextTimePreservingSmallerComponents) ?? Date().addingTimeInterval(7 * 86400)
    }
    static func weekend() -> Date {
        let cal = Calendar.current
        return cal.nextDate(after: Date(), matching: DateComponents(hour: 10, minute: 0, weekday: 7),
                            matchingPolicy: .nextTimePreservingSmallerComponents) ?? Date().addingTimeInterval(3 * 86400)
    }
}

struct TaskListView: View {
    @EnvironmentObject var store: AppStore
    @State private var newTitle = ""
    var onEdit: (TaskItem) -> Void

    private var query: String { store.taskSearch.trimmingCharacters(in: .whitespaces).lowercased() }

    private var visibleTasks: [TaskItem] {
        let base = store.tasks.filter { $0.status != .cancelled }
        guard !query.isEmpty else { return base }
        return base.filter { $0.title.lowercased().contains(query) || ($0.detail ?? "").lowercased().contains(query) }
    }

    private var grouped: [(TaskBucket, [TaskItem])] {
        var dict: [TaskBucket: [TaskItem]] = [:]
        for task in visibleTasks { dict[bucket(task), default: []].append(task) }
        return TaskBucket.allCases.compactMap { bucket in
            guard let list = dict[bucket], !list.isEmpty else { return nil }
            let sorted = list.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            return (bucket, sorted)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            quickAdd
            Divider()
            if grouped.isEmpty {
                EmptyState(icon: "checklist",
                           title: store.tasks.isEmpty ? "还没有任务" : "没有匹配的任务",
                           subtitle: "在上面输入一句话，回车即创建")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(grouped, id: \.0) { bucket, list in
                            VStack(alignment: .leading, spacing: 6) {
                                bucketHeader(bucket, list.count)
                                VStack(spacing: 0) {
                                    ForEach(list) { task in
                                        TaskLine(task: task) { onEdit(task) }
                                        if task.id != list.last?.id { Divider() }
                                    }
                                }
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            TextField("添加任务，回车即可", text: $newTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    let value = newTitle
                    newTitle = ""
                    Task { await store.quickAddTask(value) }
                }
            if !newTitle.isEmpty {
                Button("添加") {
                    let value = newTitle
                    newTitle = ""
                    Task { await store.quickAddTask(value) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func bucketHeader(_ bucket: TaskBucket, _ count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(bucket.tint).frame(width: 8, height: 8)
            Text(bucket.title).font(.subheadline.weight(.semibold))
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func bucket(_ task: TaskItem) -> TaskBucket {
        if task.status == .done { return .done }
        guard let due = task.dueAt else { return .noDate }
        let cal = Calendar.current
        let now = Date()
        if due < cal.startOfDay(for: now) { return .overdue }
        if cal.isDateInToday(due) { return .today }
        if cal.isDateInTomorrow(due) { return .tomorrow }
        if let week = cal.date(byAdding: .day, value: 7, to: now), due <= week { return .thisWeek }
        return .later
    }
}

struct TaskLine: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    let task: TaskItem
    var onEdit: () -> Void

    private var isDone: Bool { task.status == .done }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { isDone ? await store.reopen(task) : await store.complete(task) }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .lineLimit(1)
                    if task.recurrence != .none {
                        Image(systemName: "repeat").font(.caption).foregroundStyle(.tertiary)
                    }
                    if task.calendarEventID != nil {
                        Image(systemName: "calendar.badge.checkmark").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if let detail = task.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            dueMenu
            priorityMenu

            if let itemID = task.itemID, store.item(id: itemID) != nil {
                Button {
                    openWindow(id: "item-detail", value: itemID)
                } label: { Image(systemName: "tray.full") }
                .buttonStyle(.borderless)
                .help("查看来源素材")
            }

            Menu {
                Button("编辑", action: onEdit)
                if isDone {
                    Button("恢复") { Task { await store.reopen(task) } }
                } else {
                    Button("标记完成") { Task { await store.complete(task) } }
                    Button("取消任务") { Task { await store.cancel(task) } }
                }
                Divider()
                Button("删除", role: .destructive) { Task { await store.delete(task) } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }

    private var dueMenu: some View {
        Menu {
            Button("今天 18:00") { reschedule(QuickDue.today()) }
            Button("明天 09:00") { reschedule(QuickDue.tomorrow()) }
            Button("下周一 09:00") { reschedule(QuickDue.nextWeek()) }
            Button("本周六 10:00") { reschedule(QuickDue.weekend()) }
            if task.dueAt != nil {
                Divider()
                Button("清除日期") { reschedule(nil) }
            }
            Divider()
            Button("自定义…", action: onEdit)
        } label: {
            if let due = task.dueAt {
                Text(Fmt.due(due))
                    .font(.caption)
                    .foregroundStyle(isOverdue(due) ? .red : .secondary)
            } else {
                Image(systemName: "calendar.badge.plus")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("设置 / 修改截止时间")
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(TaskPriority.allCases) { priority in
                Button {
                    Task { await store.setPriority(task, priority) }
                } label: {
                    Label(priority.label, systemImage: task.priority == priority ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Circle().fill(color(task.priority)).frame(width: 9, height: 9)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("优先级：\(task.priority.label)")
    }

    private func reschedule(_ date: Date?) {
        Task { await store.reschedule(task, to: date) }
    }

    private func isOverdue(_ due: Date) -> Bool {
        !isDone && due < Date()
    }

    private func color(_ priority: TaskPriority) -> Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .normal: return .blue
        case .low: return .gray
        }
    }
}

// MARK: - Editor

struct TaskEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem?

    @State private var title = ""
    @State private var detail = ""
    @State private var hasDue = false
    @State private var due = Date().addingTimeInterval(3600)
    @State private var priority: TaskPriority = .normal
    @State private var recurrence: Recurrence = .none
    @State private var writeToCalendar = Prefs.writeToCalendar

    private var isEditing: Bool { task != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "编辑任务" : "新建任务").font(.headline)

            TextField("任务标题", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("描述（可选）", text: $detail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Toggle("截止时间", isOn: $hasDue)
                if hasDue {
                    DatePicker("", selection: $due, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    Picker("", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            HStack(spacing: 10) {
                Text("优先级").foregroundStyle(.secondary)
                Picker("", selection: $priority) {
                    ForEach(TaskPriority.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
                Spacer()
            }

            Toggle("同步到系统日历", isOn: $writeToCalendar)

            HStack {
                if let task {
                    Button(role: .destructive) {
                        Task { await store.delete(task); dismiss() }
                    } label: { Label("删除", systemImage: "trash") }
                }
                Spacer()
                Button("取消") { dismiss() }
                Button(isEditing ? "保存" : "创建") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear(perform: load)
    }

    private func load() {
        guard let task else { return }
        title = task.title
        detail = task.detail ?? ""
        hasDue = task.dueAt != nil
        if let d = task.dueAt { due = d }
        priority = task.priority
        recurrence = task.recurrence
    }

    private func save() {
        let dueValue = hasDue ? due : nil
        Task {
            if var existing = task {
                existing.title = title
                existing.detail = detail.isEmpty ? nil : detail
                existing.dueAt = dueValue
                existing.priority = priority
                existing.recurrence = hasDue ? recurrence : .none
                await store.saveTaskWithCalendar(existing, writeToCalendar: writeToCalendar)
            } else {
                await store.newTask(title: title, detail: detail.isEmpty ? nil : detail,
                                    due: dueValue, priority: priority,
                                    recurrence: hasDue ? recurrence : .none,
                                    writeToCalendar: writeToCalendar)
            }
            dismiss()
        }
    }
}
