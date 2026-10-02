import SwiftUI
import CatchMeUpCore

struct TodoView: View {
    @EnvironmentObject var store: AppStore
    @State private var newTitle = ""

    private var carriedOver: [Todo] {
        store.todos.filter { !$0.isDone && !$0.isToday }
    }
    private var todayOpen: [Todo] {
        store.todos.filter { $0.isToday && !$0.isDone }
    }
    private var todayDone: [Todo] {
        store.todos.filter { $0.isToday && $0.isDone }
    }
    private var isEmpty: Bool {
        store.todos.isEmpty && store.todoSuggestions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            quickAdd
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !store.todoSuggestions.isEmpty { suggestionsCard }
                    section(L.t("未完成（往日）"), carriedOver)
                    section(L.t("今日待办"), todayOpen)
                    section(L.t("今日已完成"), todayDone)
                    if isEmpty {
                        EmptyState(icon: "checkmark.square", title: L.t("暂无待办"),
                                   subtitle: L.t("在上面输入一句话，回车即创建"))
                            .frame(height: 200)
                    }
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L.t("今日待办")).font(.headline)
            Text(todayString).font(.body).foregroundStyle(.secondary)
            Spacer()
            if store.isBusy { ProgressView().controlSize(.small) }
            Button {
                Task { await store.generateTodos() }
            } label: {
                Label(L.t("生成今日待办"), systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isBusy)
        }
        .padding(16)
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            TextField(L.t("新建待办，回车即可"), text: $newTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    let value = newTitle
                    newTitle = ""
                    Task { await store.quickAddTodo(value) }
                }
            if !newTitle.isEmpty {
                Button(L.t("添加")) {
                    let value = newTitle
                    newTitle = ""
                    Task { await store.quickAddTodo(value) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var suggestionsCard: some View {
        Card(title: L.t("AI 推荐")) {
            ForEach(store.todoSuggestions, id: \.title) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(.purple).font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).font(.body)
                        if let detail = suggestion.detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if let index = suggestion.taskIndex, index < store.todoSuggestionTasks.count {
                            Label(store.todoSuggestionTasks[index].title, systemImage: "checklist")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(L.t("添加")) { Task { await store.acceptTodoSuggestion(suggestion) } }
                        .controlSize(.small)
                }
                if suggestion.title != store.todoSuggestions.last?.title { Divider() }
            }
            HStack {
                Button(L.t("全部添加")) { Task { await store.acceptAllTodoSuggestions() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(L.t("清空")) { store.dismissTodoSuggestions() }
                    .controlSize(.small)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ todos: [Todo]) -> some View {
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text("\(todos.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                VStack(spacing: 0) {
                    ForEach(todos) { todo in
                        TodoRow(todo: todo)
                        if todo.id != todos.last?.id { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
            }
        }
    }

    private var todayString: String {
        let f = DateFormatter()
        f.locale = L.locale
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: Date())
    }
}

struct TodoRow: View {
    @EnvironmentObject var store: AppStore
    let todo: Todo

    private var linkedTask: TaskItem? {
        todo.taskID.flatMap { id in store.tasks.first { $0.id == id } }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.toggleTodo(todo) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(todo.title)
                        .font(.body)
                        .strikethrough(todo.isDone)
                        .foregroundStyle(todo.isDone ? .secondary : .primary)
                    if todo.source == .ai {
                        Text(L.t("AI 推荐"))
                            .font(.caption2).foregroundStyle(.purple)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.12)))
                    }
                }
                if let detail = todo.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            Spacer()

            linkControl

            Menu {
                if todo.taskID != nil {
                    Button(L.t("解除绑定")) { Task { await store.bindTodo(todo, to: nil) } }
                }
                Button(L.t("删除"), role: .destructive) { Task { await store.deleteTodo(todo) } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var linkControl: some View {
        if let task = linkedTask {
            Menu {
                Button(L.t("解除绑定")) { Task { await store.bindTodo(todo, to: nil) } }
            } label: {
                Label(task.title, systemImage: "link")
                    .font(.caption)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L.f("关联任务：%@", task.title))
        } else {
            Menu {
                let candidates = store.tasks.filter { $0.isOpen }.prefix(30)
                if candidates.isEmpty {
                    Text(L.t("还没有任务"))
                } else {
                    ForEach(Array(candidates)) { task in
                        Button(task.title) { Task { await store.bindTodo(todo, to: task) } }
                    }
                }
            } label: {
                Image(systemName: "link.badge.plus")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L.t("绑定任务"))
        }
    }
}
