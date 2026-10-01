import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CatchMeUpCore

/// One input for everything: type, paste, drag, or screenshot. No mode buttons to hunt for.
struct ComposerView: View {
    @EnvironmentObject var store: AppStore
    @State private var text = ""
    @State private var hint = ""
    @State private var intent: IngestIntent = .auto
    @State private var isTargeted = false

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hintOrNil: String? {
        hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : hint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                ComposerTextView(text: $text, onSubmit: send, onPasteImage: { data in
                    Task { await store.captureImage(data: data, name: "clipboard.png", hint: hintOrNil, intent: intent) }
                }, onPasteFiles: { urls in
                    Task { await handleFiles(urls) }
                })
                .frame(minHeight: 66, maxHeight: 170)

                if text.isEmpty {
                    Text(L.t("输入文字 / 网址 / 文件路径，或把文件、截图直接拖进来（⌘V 可粘贴截图）"))
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isTargeted ? 2 : 1)
            )
            .onDrop(of: [.fileURL, .url, .image, .plainText], isTargeted: $isTargeted, perform: handleDrop)

            HStack(spacing: 10) {
                Picker("", selection: $intent) {
                    ForEach(IngestIntent.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .help(L.t("自动：文本/截图→任务，目录→交接 · 任务：抽取截止时间 · 交接：项目梳理"))

                Menu {
                    Button(L.t("文件…")) { chooseFile() }
                    Button(L.t("文件夹…")) { chooseFolder() }
                    Button(L.t("图片…")) { chooseImage() }
                } label: {
                    Image(systemName: "paperclip")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help(L.t("添加文件 / 文件夹 / 图片"))

                Button {
                    Task { await store.captureInteractiveScreenshot(hint: hintOrNil, intent: intent) }
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .buttonStyle(.borderless)
                .help(L.f("框选截图（全局快捷键 %@）", store.screenshotHotKeyDisplay))

                Spacer()

                Button(action: send) {
                    Label(L.t("整理"), systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isBusy)
            }

            if !canSend {
                TextField(L.t("可选：补充说明（帮助 AI 理解上下文）"), text: $hint)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func send() {
        let value = text
        text = ""
        let h = hintOrNil
        Task { await store.submit(value, intent: intent, hint: h) }
    }

    private func handleFiles(_ urls: [URL]) async {
        for url in urls.prefix(5) {
            if url.hasDirectoryPath {
                await store.capturePath(url.path, hint: hintOrNil, intent: intent)
            } else if Ingest.imageExtensions.contains(url.pathExtension.lowercased()),
                      let data = try? Data(contentsOf: url) {
                await store.captureImage(data: data, name: url.lastPathComponent, hint: hintOrNil, intent: intent)
            } else {
                await store.capturePath(url.path, hint: hintOrNil, intent: intent)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await handleFiles([url]) }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            _ = provider.loadObject(ofClass: String.self) { value, _ in
                guard let value, !value.isEmpty else { return }
                Task { @MainActor in await store.submit(value, intent: intent, hint: hintOrNil) }
            }
            return true
        }
        return false
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { Task { await handleFiles(panel.urls) } }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { Task { await handleFiles(panel.urls) } }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { Task { await handleFiles(panel.urls) } }
    }
}
