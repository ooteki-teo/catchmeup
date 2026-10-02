import SwiftUI
import CatchMeUpCore

struct RootView: View {
    @EnvironmentObject var store: AppStore

    private var selectionBinding: Binding<AppStore.Section?> {
        Binding(get: { store.selection }, set: { store.selection = $0 ?? store.selection })
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: selectionBinding) {
                    ForEach([AppStore.Section.workspace, .todos, .tasks, .handoff, .calendar, .jobs]) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                    Section {
                        Label(AppStore.Section.settings.title, systemImage: AppStore.Section.settings.icon)
                            .tag(AppStore.Section.settings)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                healthFooter
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 195)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if store.isBusy { ProgressView().controlSize(.small) }
            }
        }
        .overlay(alignment: .bottom) { banner }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection {
        case .workspace: WorkspaceView()
        case .todos: TodoView()
        case .tasks: TasksView()
        case .handoff: HandoffView()
        case .calendar: CalendarView()
        case .jobs: JobsView()
        case .settings: SettingsView()
        }
    }

    private var healthFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HealthRow(label: AIProviderSettings.kind.displayName,
                      ok: store.aiConfigured,
                      okText: AIProviderSettings.model(for: AIProviderSettings.kind),
                      badText: L.t("未配置 Key"))
            HealthRow(label: L.t("通知"), ok: store.notificationsAuthorized, okText: L.t("已授权"), badText: L.t("未授权"))
            HealthRow(label: L.t("日历"), ok: store.calendarAuthorized, okText: L.t("已授权"), badText: L.t("未授权"))
        }
        .padding(12)
    }

    @ViewBuilder
    private var banner: some View {
        if let error = store.errorMessage {
            ToastBanner(text: error, isError: true)
                .onTapGesture { store.errorMessage = nil }
        } else if let status = store.statusMessage {
            ToastBanner(text: status)
        }
    }
}

struct HealthRow: View {
    let label: String
    let ok: Bool
    let okText: String
    let badText: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(ok ? okText : badText).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject var store: AppStore
    @State private var quickText = ""

    private var upcoming: [TaskItem] {
        store.tasks.filter { $0.isOpen && $0.dueAt != nil }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                Text("CatchMeUp").font(.headline)
                Spacer()
                if store.isBusy { ProgressView().controlSize(.small) }
            }

            HStack {
                TextField(L.t("记点什么…"), text: $quickText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button(L.t("整理"), action: submit).disabled(quickText.isEmpty)
            }

            HStack {
                Button {
                    Task { await store.captureInteractiveScreenshot(intent: .auto) }
                } label: { Label(L.t("截图"), systemImage: "camera.viewfinder") }
                Button {
                    Task { await store.submitClipboard(intent: .auto) }
                } label: { Label(L.t("剪贴板"), systemImage: "doc.on.clipboard") }
            }
            .buttonStyle(.bordered)

            Divider()

            Text(L.t("即将到期")).font(.caption).foregroundStyle(.secondary)
            if upcoming.isEmpty {
                Text(L.t("暂无带截止时间的任务")).font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(upcoming) { task in
                    HStack {
                        Circle().fill(task.priority == .urgent ? Color.red : Color.accentColor).frame(width: 6, height: 6)
                        Text(task.title).font(.body).lineLimit(1)
                        Spacer()
                        Text(Fmt.due(task.dueAt)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            Button {
                NSApp.activate(ignoringOtherApps: true)
            } label: { Label(L.t("打开主窗口"), systemImage: "macwindow") }
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: { Label(L.t("退出"), systemImage: "power") }
        }
        .padding(14)
        .frame(width: 320)
        .task { await store.refresh() }
    }

    private func submit() {
        let text = quickText
        quickText = ""
        Task { await store.submit(text, intent: .task) }
    }
}
