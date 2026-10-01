import SwiftUI
import CatchMeUpCore

struct WorkspaceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var layout: CollectionLayout = .cards

    private var filteredItems: [Item] {
        var result = store.items
        if let kind = store.itemKindFilter { result = result.filter { $0.kind == kind } }
        let query = store.itemSearch.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                ($0.title ?? "").lowercased().contains(query)
                    || ($0.summary ?? "").lowercased().contains(query)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                statsStrip
                ComposerView()
            }
            .padding(20)

            Divider()

            itemsToolbar

            if filteredItems.isEmpty {
                EmptyState(icon: "square.stack", title: store.items.isEmpty ? L.t("还没有素材") : L.t("没有匹配的素材"),
                           subtitle: store.items.isEmpty ? L.t("在上面输入、粘贴或拖入内容开始") : L.t("换个关键词试试"))
            } else {
                ScrollView {
                    if layout == .cards {
                        ItemCardGrid(items: filteredItems,
                                     tasksProvider: { store.tasks(for: $0.id) },
                                     onOpen: { openWindow(id: "item-detail", value: $0.id) },
                                     onToggleTask: { toggle($0) })
                            .padding(16)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(filteredItems) { item in
                                ItemBlockView(item: item,
                                              tasks: store.tasks(for: item.id),
                                              style: .list,
                                              onOpen: { openWindow(id: "item-detail", value: item.id) },
                                              onToggleTask: { toggle($0) })
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }

    private func toggle(_ task: TaskItem) {
        Task { task.status == .done ? await store.reopen(task) : await store.complete(task) }
    }

    private var statsStrip: some View {
        HStack(spacing: 8) {
            if store.stats.overdue > 0 {
                statPill(L.t("已逾期"), store.stats.overdue, .red)
            }
            statPill(L.t("未完成"), store.stats.open, .blue)
            statPill(L.t("今日到期"), store.stats.dueToday, .orange)
            statPill(L.t("近 7 天"), store.stats.dueWeek, .purple)
            statPill(L.t("素材"), store.stats.items, .green)
            Spacer()
        }
    }

    private func statPill(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.caption.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var itemsToolbar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $store.itemKindFilter) {
                Text(L.t("全部")).tag(ItemKind?.none)
                ForEach(ItemKind.allCases) { Text($0.label).tag(ItemKind?.some($0)) }
            }
            .frame(width: 110)

            TextField(L.t("搜索素材"), text: $store.itemSearch)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Spacer()
            Text(L.f("%d 条", filteredItems.count)).font(.caption).foregroundStyle(.secondary)
            ViewModeToggle(mode: $layout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct ItemDetailView: View {
    @EnvironmentObject var store: AppStore
    let itemID: String

    @State private var item: Item?

    private var linkedTasks: [TaskItem] { store.tasks.filter { $0.itemID == itemID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let item {
                    header(item)
                    TagChips(tags: item.tags)
                    if let summary = item.summary, !summary.isEmpty {
                        Card(title: L.t("摘要")) { Text(summary).font(.body) }
                    }
                    if let handoff = item.handoff { handoffCard(handoff) }
                    if !linkedTasks.isEmpty {
                        Card(title: L.t("关联任务")) {
                            ForEach(linkedTasks) { task in
                                TaskRowCompact(task: task)
                            }
                        }
                    }
                    if let content = item.rawContent, !content.isEmpty {
                        Card(title: L.t("原始内容")) {
                            Text(content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let path = item.sourcePath {
                        Card(title: L.t("本地文件")) {
                            HStack {
                                Text(path).font(.caption).textSelection(.enabled)
                                Spacer()
                                Button(L.t("在访达中显示")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                }
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 520)
        .task(id: itemID) {
            item = await store.fullItem(id: itemID)
        }
    }

    private func header(_ item: Item) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title ?? L.t("(无标题)")).font(.title2.bold())
                HStack(spacing: 8) {
                    Label(item.kind.label, systemImage: "tag")
                    if let category = item.category, !category.isEmpty { Text(category) }
                    Text(Fmt.full.string(from: item.createdAt))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    Task {
                        await store.refreshItem(item)
                        await reload()
                    }
                } label: {
                    Label(L.t("刷新"), systemImage: "arrow.clockwise")
                }
                .disabled(store.isBusy)
                .help(L.t("根据来源内容重新分析这条素材"))

                Button(role: .destructive) {
                    Task {
                        await store.delete(item)
                        NSApp.keyWindow?.close()
                    }
                } label: { Label(L.t("删除"), systemImage: "trash") }

                Button {
                    NSApp.keyWindow?.close()
                } label: { Label(L.t("关闭"), systemImage: "xmark.circle") }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func reload() async {
        item = await store.fullItem(id: itemID)
    }

    private func handoffCard(_ handoff: HandoffResult) -> some View {
        Card(title: L.t("交接")) {
            if !handoff.goals.isEmpty {
                Text(L.t("目标")).font(.subheadline.weight(.semibold))
                ForEach(Array(handoff.goals.enumerated()), id: \.offset) { idx, goal in
                    Text("\(idx + 1). \(goal)").font(.body)
                }
                Divider()
            }
            if !handoff.logic.isEmpty {
                Text(L.t("整体逻辑")).font(.subheadline.weight(.semibold))
                Text(handoff.logic).font(.body).textSelection(.enabled)
                Divider()
            }
            if !handoff.progressSummary.isEmpty {
                Text(L.t("进展")).font(.subheadline.weight(.semibold))
                Text(handoff.progressSummary).font(.body).textSelection(.enabled)
            }
            if !handoff.nextSteps.isEmpty {
                Divider()
                Text(L.t("下一步")).font(.subheadline.weight(.semibold))
                ForEach(Array(handoff.nextSteps.enumerated()), id: \.offset) { idx, step in
                    Text("\(idx + 1). \(step)").font(.body)
                }
            }
            if !handoff.risks.isEmpty {
                Divider()
                Text(L.t("风险")).font(.subheadline.weight(.semibold))
                ForEach(handoff.risks, id: \.self) { risk in
                    Label(risk, systemImage: "exclamationmark.triangle").font(.body).foregroundStyle(.orange)
                }
            }
        }
    }
}
