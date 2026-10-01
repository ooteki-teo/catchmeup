import SwiftUI
import CatchMeUpCore

/// Card vs. detailed list.
enum CollectionLayout: String, CaseIterable, Identifiable {
    case cards, list
    var id: String { rawValue }
    var icon: String { self == .cards ? "square.grid.2x2" : "list.bullet" }
}

struct ViewModeToggle: View {
    @Binding var mode: CollectionLayout

    var body: some View {
        Picker("", selection: $mode) {
            Image(systemName: "list.bullet").tag(CollectionLayout.list)
            Image(systemName: "square.grid.2x2").tag(CollectionLayout.cards)
        }
        .pickerStyle(.segmented)
        .frame(width: 84)
        .help(L.t("切换卡片 / 列表"))
    }
}

enum ItemIcon {
    static func name(for kind: ItemKind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .screenshot: return "camera.viewfinder"
        case .file: return "doc"
        case .folder: return "folder"
        case .url: return "link"
        }
    }
}

/// One rich representation of a captured item, used both as a grid card and a list row.
struct ItemBlockView: View {
    let item: Item
    var tasks: [TaskItem] = []
    var handoff: HandoffResult?
    var style: CollectionLayout = .list
    var onOpen: () -> Void = {}
    /// Toggling a linked task (complete / reopen) directly from the card.
    var onToggleTask: (TaskItem) -> Void = { _ in }

    // Incremental hand-off refresh (only shown when enabled).
    var canRefreshHandoff: Bool = false
    var isRefreshArmed: Bool = false
    var onRefreshTap: () -> Void = {}
    var onRefreshConfirm: () -> Void = {}
    var onRefreshCancel: () -> Void = {}

    var body: some View {
        Group {
            if style == .cards { cardBody } else { rowBody }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    // MARK: Card

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let summary = item.summary, !summary.isEmpty {
                Text(summary).font(.body).foregroundStyle(.secondary).lineLimit(3)
            }
            if !tasks.isEmpty { taskList(limit: 3) }
            else if let handoff { handoffSnippet(handoff, lines: 3) }
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
    }

    // MARK: Row

    private var rowBody: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary).font(.body).foregroundStyle(.secondary).lineLimit(3)
                }
                if !item.tags.isEmpty { TagChips(tags: item.tags) }
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !tasks.isEmpty || handoff != nil {
                Divider().frame(height: 76)
                VStack(alignment: .leading, spacing: 6) {
                    if !tasks.isEmpty {
                        Text(L.t("关联任务")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        taskList(limit: 5)
                    } else if let handoff {
                        Text(L.t("交接")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        handoffSnippet(handoff, lines: 5)
                    }
                }
                .frame(width: 320, alignment: .leading)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: ItemIcon.name(for: item.kind)).foregroundStyle(.secondary)
            Text(item.title ?? L.t("(无标题)")).font(.body.weight(.medium)).lineLimit(1)
            if item.handoff != nil {
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.purple)
            }
            Spacer()
            if canRefreshHandoff { refreshControls }
            Text(Fmt.relative(item.createdAt)).font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var refreshControls: some View {
        if isRefreshArmed {
            Button(L.t("取消")) { onRefreshCancel() }
                .controlSize(.small)
            Button(L.t("更新")) { onRefreshConfirm() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else {
            Button {
                onRefreshTap()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L.t("增量更新这份交接"))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(item.kind.label).font(.caption).foregroundStyle(.tertiary)
            if let category = item.category, !category.isEmpty {
                Text(category).font(.caption).foregroundStyle(.tertiary)
            }
            if !tasks.isEmpty {
                Label("\(tasks.count)", systemImage: "checklist").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func taskList(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tasks.prefix(limit)) { task in
                HStack(spacing: 6) {
                    Button {
                        onToggleTask(task)
                    } label: {
                        Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(task.status == .done ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    Text(task.title).font(.body).lineLimit(1)
                        .strikethrough(task.status == .done)
                    Spacer()
                    if let due = task.dueAt {
                        Text(Fmt.due(due)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if tasks.count > limit {
                Text(L.f("… 还有 %d 条", tasks.count - limit)).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func handoffSnippet(_ handoff: HandoffResult, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !handoff.logic.isEmpty {
                Text(handoff.logic).font(.body).foregroundStyle(.secondary).lineLimit(2)
            }
            if !handoff.progressSummary.isEmpty {
                Text(handoff.progressSummary).font(.body).foregroundStyle(.secondary).lineLimit(lines)
            }
            ForEach(handoff.nextSteps.prefix(2), id: \.self) { step in
                HStack(alignment: .top, spacing: 4) {
                    Text(L.t("·")).foregroundStyle(.tertiary)
                    Text(step).font(.body).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

/// Adaptive grid of item cards (no refresh controls).
struct ItemCardGrid: View {
    let items: [Item]
    var tasksProvider: (Item) -> [TaskItem] = { _ in [] }
    var onOpen: (Item) -> Void = { _ in }
    var onToggleTask: (TaskItem) -> Void = { _ in }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
            ForEach(items) { item in
                ItemBlockView(item: item, tasks: tasksProvider(item), style: .cards,
                              onOpen: { onOpen(item) }, onToggleTask: onToggleTask)
            }
        }
    }
}
