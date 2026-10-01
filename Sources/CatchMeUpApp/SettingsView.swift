import SwiftUI
import ServiceManagement
import CatchMeUpCore

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var recordingHotKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("模型、权限与提醒设置").foregroundStyle(.secondary)

                Card(title: "DeepSeek") {
                    HStack {
                        Text("API Key").frame(width: 90, alignment: .leading)
                        SecureField("sk-...", text: $store.apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("保存在本机应用目录的 secrets.json（仅当前用户可读），不使用系统钥匙串，因此不会弹授权。")
                        .font(.caption2).foregroundStyle(.secondary)

                    HStack {
                        Text("模型").frame(width: 90, alignment: .leading)
                        Picker("", selection: $store.modelInput) {
                            Text("deepseek-flash（支持图片，推荐）").tag("deepseek-flash")
                            Text("deepseek-v4-pro（纯文本）").tag("deepseek-v4-pro")
                        }
                        .labelsHidden()
                    }
                    HStack {
                        Text("Base URL").frame(width: 90, alignment: .leading)
                        TextField("https://api.deepseek.com", text: $store.baseURLInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Button {
                            store.saveSettings()
                        } label: { Label("保存", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        Button {
                            Task { await store.testConnection() }
                        } label: { Label("测试连接", systemImage: "bolt") }
                    }

                    Divider()
                    usageView
                }

                Card(title: "提醒") {
                    Stepper(value: $store.reminderLeadInput, in: 0...120, step: 5) {
                        Text("默认提前 \(store.reminderLeadInput) 分钟提醒")
                    }
                    Toggle("把带截止时间的任务写入系统日历", isOn: $store.writeToCalendarInput)
                }

                Card(title: "权限") {
                    Text("权限只在下面主动点击时申请，App 启动时不会自动弹窗。")
                        .font(.caption).foregroundStyle(.secondary)

                    permissionRow(
                        label: "通知",
                        status: notificationStatusText,
                        granted: store.notificationsAuthorized,
                        requestTitle: "请求授权",
                        onRequest: { Task { await store.requestNotificationAccess() } },
                        openSettings: { store.openNotificationSettings() }
                    )
                    Divider()
                    permissionRow(
                        label: "日历",
                        status: calendarStatusText,
                        granted: store.calendarAuthorized,
                        requestTitle: "请求授权",
                        onRequest: { Task { await store.requestCalendarAccess() } },
                        openSettings: { store.openPrivacySettings("Privacy_Calendars") }
                    )
                    Divider()
                    permissionRow(
                        label: "屏幕录制（截图）",
                        status: store.screenRecordingGranted ? "已授权" : "未授权",
                        granted: store.screenRecordingGranted,
                        requestTitle: "请求授权",
                        onRequest: { store.requestScreenRecording() },
                        openSettings: { store.openPrivacySettings("Privacy_ScreenCapture") }
                    )
                    Button {
                        Task { await store.refreshAuthorization() }
                    } label: { Label("重新检查状态", systemImage: "arrow.clockwise") }
                    .controlSize(.small)
                }

                Card(title: "通用") {
                    Toggle("开机自动启动", isOn: Binding(
                        get: { Prefs.launchAtLogin },
                        set: { setLaunchAtLogin($0) }
                    ))
                    HStack {
                        Text("截图快捷键").foregroundStyle(.secondary)
                        Spacer()
                        HotKeyField(display: store.screenshotHotKeyDisplay,
                                    recording: $recordingHotKey,
                                    onCapture: { keyCode, modifiers in
                                        store.updateScreenshotHotKey(keyCode: keyCode, modifiers: modifiers)
                                    },
                                    onReset: { store.resetScreenshotHotKey() })
                    }
                    HStack {
                        Text("数据目录").foregroundStyle(.secondary)
                        Spacer()
                        Button(AppPaths.supportDirectory.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
                        }
                        .font(.caption)
                    }
                }

                Card(title: "提示词（高级）") {
                    Text("留空表示使用内置默认提示词；修改后点「保存」生效。")
                        .font(.caption2).foregroundStyle(.secondary)
                    promptEditor("整理提示词（任务 / 交接）",
                                 text: $store.organizerPromptInput,
                                 defaultText: DeepSeekClient.organizerSystem)
                    promptEditor("交接摘要提示词",
                                 text: $store.handoffPromptInput,
                                 defaultText: DeepSeekClient.handoffSystem)
                }

                Card(title: "关于") {
                    Text("CatchMeUp · 原生 macOS 任务助理").font(.body.weight(.medium))
                    Text("截图 / 文字 / 文件 / 文件夹 / 网址 → 自动整理为素材与待办，支持提醒、日历与任务交接。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("数据全部保存在本机，仅整理时调用 DeepSeek。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .onChange(of: store.writeToCalendarInput) { _, _ in store.saveSettings() }
        .onChange(of: store.reminderLeadInput) { _, _ in store.saveSettings() }
        .onChange(of: store.modelInput) { _, _ in store.saveSettings() }
        .onChange(of: store.baseURLInput) { _, _ in store.saveSettings() }
    }

    private var notificationStatusText: String {
        switch store.notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "未授权"
        @unknown default: return "未知"
        }
    }

    private var calendarStatusText: String {
        switch store.calendarStatus {
        case .fullAccess: return "已授权"
        case .writeOnly: return "仅写入"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .notDetermined: return "未授权"
        @unknown default: return "未知"
        }
    }

    private func permissionRow(label: String,
                               status: String,
                               granted: Bool,
                               requestTitle: String,
                               onRequest: @escaping () -> Void,
                               openSettings: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Circle().fill(granted ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(label)
            Text(status).font(.caption).foregroundStyle(granted ? Color.secondary : Color.orange)
            Spacer()
            if !granted {
                Button(requestTitle, action: onRequest)
                Button("打开系统设置", action: openSettings)
            }
        }
    }

    @ViewBuilder
    private var usageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token 用量").font(.subheadline.weight(.semibold))
                Spacer()
                Button("重置") { store.resetUsage() }
                    .controlSize(.small)
            }

            let total = store.usage.total
            HStack(spacing: 20) {
                usageMetric("调用次数", "\(total.requests)")
                usageMetric("输入", tokens(total.promptTokens))
                usageMetric("输出", tokens(total.completionTokens))
                usageMetric("合计", tokens(total.totalTokens))
            }

            if store.usage.byModel.count > 1 {
                ForEach(store.usage.byModel.sorted { $0.key < $1.key }, id: \.key) { model, usage in
                    HStack {
                        Text(model).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(usage.requests) 次 · \(tokens(usage.promptTokens + usage.completionTokens)) tokens")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let updated = store.usage.updatedAt {
                Text("最近更新：\(Fmt.full.string(from: Date(timeIntervalSince1970: updated)))")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("暂无用量记录").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func usageMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium)).monospacedDigit()
        }
    }

    private func tokens(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName))
    }

    private func promptEditor(_ label: String, text: Binding<String>, defaultText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Button("填入默认") { text.wrappedValue = defaultText }
                Button("清空") { text.wrappedValue = "" }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                if text.wrappedValue.isEmpty {
                    Text("（留空 = 使用内置默认提示词）")
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(8).allowsHitTesting(false)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        Prefs.launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            store.errorMessage = "设置开机启动失败：\(error.localizedDescription)（需以 .app 形式运行）"
        }
    }
}
