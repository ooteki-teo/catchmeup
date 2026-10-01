import Foundation
import AppKit
import PDFKit

public struct Ingested: Sendable {
    public var kind: ItemKind
    public var rawContent: String
    public var titleHint: String?
    public var metadata: [String: String]
    public var sourcePath: String?
    public var imageData: Data?

    public init(kind: ItemKind, rawContent: String, titleHint: String? = nil,
                metadata: [String: String] = [:], sourcePath: String? = nil, imageData: Data? = nil) {
        self.kind = kind
        self.rawContent = rawContent
        self.titleHint = titleHint
        self.metadata = metadata
        self.sourcePath = sourcePath
        self.imageData = imageData
    }
}

public enum Ingest {

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "webp", "tiff", "heic"]
    public static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rst", "log", "py", "js", "ts", "tsx", "jsx", "json", "yaml", "yml",
        "toml", "ini", "cfg", "sh", "zsh", "bash", "html", "htm", "css", "scss", "less", "csv", "tsv",
        "xml", "sql", "swift", "kt", "java", "c", "h", "cpp", "hpp", "rs", "go", "rb", "php", "lua", "r"
    ]

    // MARK: Text

    public static func text(_ text: String) -> Ingested {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Ingested(kind: .text, rawContent: trimmed, titleHint: firstLine(trimmed),
                        metadata: ["length": String(trimmed.count)])
    }

    private static func firstLine(_ text: String, maxLen: Int = 80) -> String? {
        guard let line = text.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces),
              !line.isEmpty else { return nil }
        return String(line.prefix(maxLen))
    }

    // MARK: URL

    public static func url(_ urlString: String) async throws -> Ingested {
        guard let url = URL(string: urlString), url.scheme != nil, url.host != nil else {
            throw CatchMeUpError.ingest(L.f("无效网址：%@", urlString))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("CatchMeUp/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CatchMeUpError.ingest(L.f("抓取失败，状态码 %d", (response as? HTTPURLResponse)?.statusCode ?? -1))
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        let title = extractTitle(html) ?? url.host ?? urlString
        let plain = htmlToText(data) ?? stripTags(html)
        return Ingested(kind: .url,
                        rawContent: String(plain.prefix(30_000)),
                        titleHint: String(title.prefix(120)),
                        metadata: ["url": urlString, "host": url.host ?? ""])
    }

    private static func htmlToText(_ data: Data) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let attr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else { return nil }
        let text = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func extractTitle(_ html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        var title = String(html[range])
        title = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func stripTags(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: File

    public static func file(_ path: String) throws -> Ingested {
        let src = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw CatchMeUpError.ingest(L.f("文件不存在：%@", path))
        }
        let suffix = src.pathExtension.lowercased()
        let saved = try saveToStorage(src, subdir: "files")
        let content = readTextFile(src)
        return Ingested(kind: .file,
                        rawContent: content,
                        titleHint: src.deletingPathExtension().lastPathComponent,
                        metadata: ["original_name": src.lastPathComponent,
                                   "stored_path": saved.path,
                                   "suffix": suffix,
                                   "size_bytes": fileSize(src)],
                        sourcePath: saved.path)
    }

    public static func readTextFile(_ url: URL, maxBytes: Int = 200_000) -> String {
        let suffix = url.pathExtension.lowercased()
        if textExtensions.contains(suffix) {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                return String(decoding: data.prefix(maxBytes), as: UTF8.self)
            }
            return ""
        }
        if suffix == "pdf", let doc = PDFDocument(url: url) {
            var parts: [String] = []
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let text = page.string { parts.append(text) }
            }
            return parts.joined(separator: "\n")
        }
        if suffix == "docx" || suffix == "doc" || suffix == "rtf" {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
            if let attr = try? NSAttributedString(url: url, options: options, documentAttributes: nil) {
                return attr.string
            }
        }
        // Fallback: try UTF-8
        if let data = try? Data(contentsOf: url), let text = String(data: data.prefix(maxBytes), encoding: .utf8) {
            return text
        }
        return ""
    }

    private static func fileSize(_ url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return String(size)
    }

    // MARK: Folder

    private static let skippedDirs: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", ".build-xcode", "dist", "Pods",
        "__pycache__", ".venv", "venv", "env", "DerivedData", ".idea", ".vscode", "target"
    ]

    /// Build a compact project overview: optional README section + a directory tree
    /// with a one-line description per file. Does not dump full file contents.
    public static func folder(_ path: String,
                              maxFiles: Int = 400,
                              maxLines: Int = 220,
                              maxDepth: Int = 5) throws -> Ingested {
        let src = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue else {
            throw CatchMeUpError.ingest(L.f("文件夹不存在：%@", path))
        }

        var state = TreeState(maxFiles: maxFiles, maxLines: maxLines)
        renderTree(dir: src, indent: "", depth: 0, maxDepth: maxDepth, state: &state)

        let readme = findReadme(in: src)
        var metadata: [String: String] = [
            "root": src.path,
            "files_total": String(state.files),
            "files_listed": String(state.listed),
            "has_readme": readme != nil ? "true" : "false"
        ]

        var sections: [String] = ["Folder: \(src.path)", "Files: \(state.files)"]

        if let readme {
            let content = readTextFile(readme, maxBytes: 6_000).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                metadata["readme_path"] = readme.path
                sections.append("\n# README（\(readme.lastPathComponent)）\n\(String(content.prefix(4_000)))")
            }
        }

        sections.append("\n# 目录结构\n" + (state.lines.isEmpty ? L.t("(空)") : state.lines.joined(separator: "\n")))
        return Ingested(kind: .folder, rawContent: sections.joined(separator: "\n"),
                        titleHint: src.lastPathComponent, metadata: metadata)
    }

    private struct TreeState {
        var lines: [String] = []
        var files = 0
        var listed = 0
        let maxFiles: Int
        let maxLines: Int
    }

    private static func renderTree(dir: URL, indent: String, depth: Int, maxDepth: Int, state: inout TreeState) {
        if state.lines.count >= state.maxLines { return }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: dir,
                                                   includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                   options: [.skipsHiddenFiles]))?
            .filter { !skippedDirs.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []

        for (index, entry) in entries.enumerated() {
            if state.lines.count >= state.maxLines {
                state.lines.append(indent + L.t("└── …（更多省略）"))
                return
            }
            let isLast = index == entries.count - 1
            let branch = isLast ? "└── " : "├── "
            let childIndent = indent + (isLast ? "    " : "│   ")
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                state.lines.append(indent + branch + entry.lastPathComponent + "/")
                if depth + 1 <= maxDepth {
                    renderTree(dir: entry, indent: childIndent, depth: depth + 1, maxDepth: maxDepth, state: &state)
                } else {
                    state.lines.append(childIndent + "└── …")
                }
            } else {
                state.files += 1
                guard state.files <= state.maxFiles else { continue }
                state.listed += 1
                let hint = fileHint(entry)
                state.lines.append(indent + branch + entry.lastPathComponent + (hint.isEmpty ? "" : " — \(hint)"))
            }
        }
    }

    /// A short, cheap description for a file (first line for text, size/type for binary).
    private static func fileHint(_ url: URL) -> String {
        let suffix = url.pathExtension.lowercased()
        if textExtensions.contains(suffix) {
            if let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                let data = (try? handle.read(upToCount: 512)) ?? Data()
                let text = String(decoding: data, as: UTF8.self)
                for line in text.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    return String(trimmed.prefix(90))
                }
            }
            return ""
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private static func findReadme(in dir: URL) -> URL? {
        let allowed: Set<String> = ["md", "markdown", "txt", "rst", ""]
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.first { entry in
            let name = entry.lastPathComponent.lowercased()
            return name.hasPrefix("readme") && allowed.contains(entry.pathExtension.lowercased())
        }
    }


    // MARK: Screenshot / image

    public static func screenshot(imageData: Data, originalName: String = "screenshot.png") throws -> Ingested {
        let saved = try saveToStorage(data: imageData, name: originalName, subdir: "screenshots")
        let text = OCR.recognizeText(imageData: imageData)
        return Ingested(kind: .screenshot,
                        rawContent: text,
                        titleHint: firstLine(text) ?? saved.deletingPathExtension().lastPathComponent,
                        metadata: ["original_name": originalName, "stored_path": saved.path,
                                   "ocr_engine": text.isEmpty ? "none" : "vision"],
                        sourcePath: saved.path,
                        imageData: imageData)
    }

    public static func screenshot(path: String) throws -> Ingested {
        let src = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: src) else {
            throw CatchMeUpError.ingest(L.f("无法读取图片：%@", path))
        }
        return try screenshot(imageData: data, originalName: src.lastPathComponent)
    }

    // MARK: Storage

    public static func saveToStorage(_ src: URL, subdir: String) throws -> URL {
        let dir = AppPaths.storageDirectory.appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter.catchMeUp.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = dir.appendingPathComponent("\(stamp)_\(src.lastPathComponent)")
        if FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: src, to: target)
        return target
    }

    public static func saveToStorage(data: Data, name: String, subdir: String) throws -> URL {
        let dir = AppPaths.storageDirectory.appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter.catchMeUp.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = dir.appendingPathComponent("\(stamp)_\(name)")
        try data.write(to: target)
        return target
    }
}
