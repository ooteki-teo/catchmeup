import SwiftUI
import ServiceManagement
import CatchMeUpCore

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var recordingHotKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L.t("模型、权限与提醒设置")).foregroundStyle(.secondary)
                deepseekCard
                reminderCard
                permissionsCard
                languageCard
                generalCard
                promptsCard
                aboutCard
            }
            .padding(24)
        }
        .onChange(of: store.writeToCalendarInput) { _, _ in store.saveSettings() }
        .onChange(of: store.reminderLeadInput) { _, _ in store.saveSettings() }
        .onChange(of: store.modelInput) { _, _ in store.saveSettings() }
        .onChange(of: store.baseURLInput) { _, _ in store.saveSettings() }
    }

    // MARK: Cards

    private var deepseekCard: some View {
        Card(title: "DeepSeek") {
            HStack {
                Text("API Key").frame(width: 90, alignment: .leading)
                SecureField("sk-...", text: $store.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
            }
            Text(L.t("保存在本机应用目录的 secrets.json（仅当前用户可读），不使用系统钥匙串，因此不会弹授权。"))
                .font(.caption2).foregroundStyle(.secondary)

            HStack {
                Text(L.t("模型")).frame(width: 90, alignment: .leading)
                Picker("", selection: $store.modelInput) {
                    Text(L.t("deepseek-flash（支持图片，推荐）")).tag("deepseek-flash")
                    Text(L.t("deepseek-v4-pro（纯文本）")).tag("deepseek-v4-pro")
                }
                .labelsHidden()
            }
            HStack {
                Text("Base URL").frame(width: 90, alignment: .leading)
                TextField("https://api.deepseek.com", text: $store.baseURLInput)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button { store.saveSettings() } label: { Label(L.t("保存"), systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                Button { Task { await store.testConnection() } } label: { Label(L.t("测试连接"), systemImage: "bolt") }
            }
            Divider()
            usageView
        }
    }

    private var reminderCard: some View {
        Card(title: L.t("提醒")) {
            Stepper(value: $store.reminderLeadInput, in: 0...120, step: 5) {
                Text(L.f("默认提前 %d 分钟提醒", store.reminderLeadInput))
            }
            Toggle(L.t("把带截止时间的任务写入系统日历"), isOn: $store.writeToCalendarInput)
        }
    }

    private var permissionsCard: some View {
        Card(title: L.t("权限")) {
            Text(L.t("权限只在下面主动点击时申请，App 启动时不会自动弹窗。"))
                .font(.caption).foregroundStyle(.secondary)
            permissionRow(label: L.t("通知"), status: notificationStatusText,
                          granted: store.notificationsAuthorized, requestTitle: L.t("请求授权"),
                          onRequest: { Task { await store.requestNotificationAccess() } },
                          openSettings: { store.openNotificationSettings() })
            Divider()
            permissionRow(label: L.t("日历"), status: calendarStatusText,
                          granted: store.calendarAuthorized, requestTitle: L.t("请求授权"),
                          onRequest: { Task { await store.requestCalendarAccess() } },
                          openSettings: { store.openPrivacySettings("Privacy_Calendars") })
            Divider()
            permissionRow(label: L.t("屏幕录制（截图）"),
                          status: store.screenRecordingGranted ? L.t("已授权") : L.t("未授权"),
                          granted: store.screenRecordingGranted, requestTitle: L.t("请求授权"),
                          onRequest: { store.requestScreenRecording() },
                          openSettings: { store.openPrivacySettings("Privacy_ScreenCapture") })
            Button { Task { await store.refreshAuthorization() } } label: {
                Label(L.t("重新检查状态"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
    }

    private var languageCard: some View {
        Card(title: L.t("语言")) {
            Toggle(L.t("跟随系统"), isOn: Binding(
                get: { store.followSystemLanguage },
                set: { store.setFollowSystemLanguage($0) }
            ))
            if !store.followSystemLanguage {
                Picker("", selection: Binding(
                    get: { store.language },
                    set: { store.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var generalCard: some View {
        Card(title: L.t("通用")) {
            Toggle(L.t("开机自动启动"), isOn: Binding(
                get: { Prefs.launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            HStack {
                Text(L.t("截图快捷键")).foregroundStyle(.secondary)
                Spacer()
                HotKeyField(display: store.screenshotHotKeyDisplay,
                            recording: $recordingHotKey,
                            onCapture: { keyCode, modifiers in
                                store.updateScreenshotHotKey(keyCode: keyCode, modifiers: modifiers)
                            },
                            onReset: { store.resetScreenshotHotKey() })
            }
            HStack {
                Text(L.t("数据目录")).foregroundStyle(.secondary)
                Spacer()
                Button(AppPaths.supportDirectory.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
                }
                .font(.caption)
            }
        }
    }

    private var promptsCard: some View {
        Card(title: L.t("提示词（高级）")) {
            Text(L.t("留空表示使用内置默认提示词；修改后点「保存」生效。"))
                .font(.caption2).foregroundStyle(.secondary)
            promptEditor(L.t("整理提示词（任务 / 交接）"),
                         text: $store.organizerPromptInput,
                         defaultText: L.organizerSystem)
            promptEditor(L.t("交接摘要提示词"),
                         text: $store.handoffPromptInput,
                         defaultText: L.handoffSystem)
        }
    }

    private var aboutCard: some View {
        Card(title: L.t("关于")) {
            Text(L.t("CatchMeUp · 原生 macOS 任务助理")).font(.body.weight(.medium))
            Text(L.t("截图 / 文字 / 文件 / 文件夹 / 网址 → 自动整理为素材与待办，支持提醒、日历与任务交接。"))
                .font(.caption).foregroundStyle(.secondary)
            Text(L.t("数据全部保存在本机，仅整理时调用 DeepSeek。"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private var notificationStatusText: String {
        switch store.notificationStatus {
        case .authorized, .provisional, .ephemeral: return L.t("已授权")
        case .denied: return L.t("已拒绝")
        case .notDetermined: return L.t("未授权")
        @unknown default: return L.t("未知")
        }
    }

    private var calendarStatusText: String {
        switch store.calendarStatus {
        case .fullAccess: return L.t("已授权")
        case .writeOnly: return L.t("仅写入")
        case .denied: return L.t("已拒绝")
        case .restricted: return L.t("受限")
        case .notDetermined: return L.t("未授权")
        @unknown default: return L.t("未知")
        }
    }

    private func permissionRow(label: String, status: String, granted: Bool, requestTitle: String,
                               onRequest: @escaping () -> Void, openSettings: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Circle().fill(granted ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(label)
            Text(status).font(.caption).foregroundStyle(granted ? Color.secondary : Color.orange)
            Spacer()
            if !granted {
                Button(requestTitle, action: onRequest)
                Button(L.t("打开系统设置"), action: openSettings)
            }
        }
    }

    @ViewBuilder
    private var usageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t("Token 用量")).font(.subheadline.weight(.semibold))
                Spacer()
                Button(L.t("重置")) { store.resetUsage() }.controlSize(.small)
            }
            let total = store.usage.total
            HStack(spacing: 20) {
                usageMetric(L.t("调用次数"), "\(total.requests)")
                usageMetric(L.t("输入"), tokens(total.promptTokens))
                usageMetric(L.t("输出"), tokens(total.completionTokens))
                usageMetric(L.t("合计"), tokens(total.totalTokens))
            }
            if store.usage.byModel.count > 1 {
                ForEach(store.usage.byModel.sorted { $0.key < $1.key }, id: \.key) { model, usage in
                    HStack {
                        Text(model).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(L.f("%d 次 · %@ tokens", usage.requests, tokens(usage.promptTokens + usage.completionTokens)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let updated = store.usage.updatedAt {
                Text(L.f("最近更新：%@", Fmt.full.string(from: Date(timeIntervalSince1970: updated))))
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text(L.t("暂无用量记录")).font(.caption2).foregroundStyle(.tertiary)
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
                Button(L.t("填入默认")) { text.wrappedValue = defaultText }
                Button(L.t("清空")) { text.wrappedValue = "" }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                if text.wrappedValue.isEmpty {
                    Text(L.t("（留空 = 使用内置默认提示词）"))
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(8).allowsHitTesting(false)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        Prefs.launchAtLogin = enabled
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            store.errorMessage = L.f("设置开机启动失败：%@（需以 .app 形式运行）", error.localizedDescription)
        }
    }
}
