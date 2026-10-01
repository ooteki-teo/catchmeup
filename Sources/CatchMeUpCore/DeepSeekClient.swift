import Foundation

/// Async delay that does not collide with the project's `TaskItem` model type.
func asyncDelay(_ seconds: Double) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            continuation.resume()
        }
    }
}

// MARK: - Chat message encoding (supports text + image parts)

public struct ChatMessage: Sendable {
    public enum Content: Sendable {
        case text(String)
        case parts([Part])
    }

    public struct Part: Sendable {
        public let type: String
        public let text: String?
        public let imageBase64: String?
        public init(text: String) {
            self.type = "text"
            self.text = text
            self.imageBase64 = nil
        }
        public init(imageBase64: String) {
            self.type = "image_url"
            self.text = nil
            self.imageBase64 = imageBase64
        }
    }

    public let role: String
    public let content: Content

    public init(role: String, content: Content) {
        self.role = role
        self.content = content
    }

    public static func system(_ text: String) -> ChatMessage { .init(role: "system", content: .text(text)) }
    public static func user(_ text: String) -> ChatMessage { .init(role: "user", content: .text(text)) }
}

extension ChatMessage: Encodable {
    private struct ImageURL: Encodable { let url: String }
    private struct WirePart: Encodable {
        let type: String
        let text: String?
        let image_url: ImageURL?
        enum CodingKeys: String, CodingKey { case type, text, image_url }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            if let text { try c.encode(text, forKey: .text) }
            if let image_url { try c.encode(image_url, forKey: .image_url) }
        }
    }
    private enum CodingKeys: String, CodingKey { case role, content }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        switch content {
        case .text(let t):
            try c.encode(t, forKey: .content)
        case .parts(let parts):
            let wire = parts.map { p -> WirePart in
                if p.type == "image_url", let b64 = p.imageBase64 {
                    return WirePart(type: "image_url", text: nil,
                                    image_url: ImageURL(url: "data:image/png;base64,\(b64)"))
                }
                return WirePart(type: "text", text: p.text ?? "", image_url: nil)
            }
            try c.encode(wire, forKey: .content)
        }
    }
}

// MARK: - Client

public struct DeepSeekClient: Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String
    /// Custom organizer system prompt. Empty/nil falls back to the built-in default.
    public var organizerPrompt: String?
    /// Custom hand-off system prompt. Empty/nil falls back to the built-in default.
    public var handoffPrompt: String?

    public init(apiKey: String,
                baseURL: URL = URL(string: "https://api.deepseek.com")!,
                model: String = "deepseek-flash",
                organizerPrompt: String? = nil,
                handoffPrompt: String? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.organizerPrompt = organizerPrompt
        self.handoffPrompt = handoffPrompt
    }

    private struct RequestBody: Encodable {
        struct ResponseFormat: Encodable { let type: String }
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_tokens: Int
        let stream: Bool
        let response_format: ResponseFormat?
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable { let content: String? }
            let message: Msg
            let finish_reason: String?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let total_tokens: Int?
        }
        let choices: [Choice]
        let usage: Usage?
    }

    /// Low-level chat completion with a small retry loop.
    public func chat(_ messages: [ChatMessage],
                     temperature: Double = 0.3,
                     maxTokens: Int = 8000,
                     jsonMode: Bool = true,
                     attempts: Int = 3) async throws -> String {
        guard !apiKey.isEmpty else { throw CatchMeUpError.missingAPIKey }

        let url = baseURL.appendingPathComponent("v1/chat/completions")

        var lastError: Error = CatchMeUpError.api("unknown")
        var effectiveMaxTokens = maxTokens
        for attempt in 0..<max(1, attempts) {
            do {
                let body = RequestBody(
                    model: model,
                    messages: messages,
                    temperature: temperature,
                    max_tokens: effectiveMaxTokens,
                    stream: false,
                    response_format: jsonMode ? .init(type: "json_object") : nil
                )
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 120
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw CatchMeUpError.api(L.t("无 HTTP 响应"))
                }
                guard (200..<300).contains(http.statusCode) else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    throw CatchMeUpError.api("\(http.statusCode): \(text.prefix(300))")
                }
                let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
                if let usage = decoded.usage {
                    UsageTracker.shared.record(prompt: usage.prompt_tokens ?? 0,
                                               completion: usage.completion_tokens ?? 0,
                                               total: usage.total_tokens ?? 0,
                                               model: model)
                }
                let choice = decoded.choices.first
                if let content = choice?.message.content, !content.isEmpty {
                    return content
                }
                // Reasoning models (deepseek-flash) spend tokens on reasoning_content first;
                // an exhausted budget yields empty content with finish_reason "length".
                if choice?.finish_reason == "length", effectiveMaxTokens < 32_000 {
                    effectiveMaxTokens = min(effectiveMaxTokens * 2, 32_000)
                    lastError = CatchMeUpError.invalidResponse(L.t("响应被截断，自动扩容重试"))
                    continue
                }
                throw CatchMeUpError.invalidResponse(L.f("空响应（finish_reason=%@）", choice?.finish_reason ?? "unknown"))
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    await asyncDelay(pow(2.0, Double(attempt)) * 0.5)
                }
            }
        }
        throw lastError
    }

    // MARK: High-level helpers

    /// Organizer prompt actually used (custom override or built-in default).
    public var resolvedOrganizerSystem: String {
        if let value = organizerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        return L.organizerSystem
    }

    /// Hand-off prompt actually used (custom override or built-in default).
    public var resolvedHandoffSystem: String {
        if let value = handoffPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        return L.handoffSystem
    }

    public func organize(kind: ItemKind,
                         content: String,
                         hint: String?,
                         imageData: Data?,
                         intent: IngestIntent = .auto,
                         previousHandoff: HandoffResult? = nil,
                         now: Date = Date()) async throws -> OrganizedInput {
        let nowISO = ISO8601DateFormatter.catchMeUp.string(from: now)
        var block = "# \(L.pNow): \(nowISO)\n\n# \(L.pKind): \(kind.rawValue)\n\n"
        switch intent {
        case .auto: block += "# \(L.pIntentAuto)\n\n"
        case .task: block += "# \(L.pIntentTask)\n\n"
        case .handoff: block += "# \(L.pIntentHandoff)\n\n"
        }
        if let hint, !hint.isEmpty { block += "# \(L.pHint): \(hint)\n\n" }
        if let previousHandoff, let data = try? JSONEncoder().encode(previousHandoff),
           let json = String(data: data, encoding: .utf8) {
            block += "# \(L.pPrevious):\n\(json)\n\n"
        }
        block += "# \(L.pContent):\n\(content.isEmpty ? L.pImageAttached : content)"

        let userMessage: ChatMessage
        if let imageData, !imageData.isEmpty {
            let parts = [ChatMessage.Part(imageBase64: imageData.base64EncodedString()),
                         ChatMessage.Part(text: block)]
            userMessage = ChatMessage(role: "user", content: .parts(parts))
        } else {
            userMessage = .user(block)
        }

        let raw = try await chat([.system(resolvedOrganizerSystem), userMessage],
                                 temperature: 0.2, maxTokens: 8000)
        if let parsed = JSONExtractor.decode(OrganizedInput.self, from: raw) {
            var cleaned = parsed
            cleaned.tasks = parsed.tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            return cleaned
        }
        return OrganizedInput(summary: String(raw.prefix(280)))
    }

    public func generateHandoff(items: [Item],
                                tasks: [TaskItem],
                                sessions: [Session],
                                extraContext: String?) async throws -> HandoffResult {
        func iso(_ d: Date?) -> String? { d.map { ISO8601DateFormatter.catchMeUp.string(from: $0) } }

        let recentItems: [[String: Any]] = items.prefix(30).map { i in
            ["kind": i.kind.rawValue, "title": i.title ?? "", "summary": i.summary ?? "",
             "category": i.category ?? "", "tags": i.tags, "created_at": iso(i.createdAt) ?? ""]
        }
        let openTasks: [[String: Any]] = tasks.filter { $0.isOpen }.prefix(40).map { t in
            ["title": t.title, "status": t.status.rawValue, "priority": t.priority.rawValue,
             "due_at": iso(t.dueAt) ?? "", "description": t.detail ?? ""]
        }
        let recentSessions: [[String: Any]] = sessions.prefix(10).map { s in
            ["topic": s.topic ?? "", "summary": s.summary ?? "", "next_steps": s.nextSteps,
             "started_at": iso(s.startedAt) ?? "", "ended_at": iso(s.endedAt) ?? ""]
        }
        let payload: [String: Any] = [
            "recent_items": recentItems,
            "open_tasks": openTasks,
            "recent_sessions": recentSessions
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        var userBlock = String(data: data, encoding: .utf8) ?? "{}"
        if let extraContext, !extraContext.isEmpty {
            userBlock = "# \(L.pUserExtra)\n\(extraContext)\n\n" + userBlock
        }
        let raw = try await chat([.system(resolvedHandoffSystem), .user(userBlock)],
                                 temperature: 0.4, maxTokens: 8000)
        if let parsed = JSONExtractor.decode(HandoffResult.self, from: raw) {
            return parsed
        }
        return HandoffResult(progressSummary: String(raw.prefix(1500)))
    }
}

// MARK: - JSON helpers

public enum JSONExtractor {
    /// Robustly decode T from a model response that may include markdown fences or prose.
    public static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        let decoder = JSONDecoder()
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = clean.data(using: .utf8), let value = try? decoder.decode(type, from: data) {
            return value
        }
        // strip fences
        var stripped = clean
        if stripped.hasPrefix("```") {
            stripped = stripped.replacingOccurrences(of: "```json", with: "")
            stripped = stripped.replacingOccurrences(of: "```", with: "")
            stripped = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = stripped.data(using: .utf8), let value = try? decoder.decode(type, from: data) {
                return value
            }
        }
        // find first balanced JSON object
        for start in clean.indices where clean[start] == "{" {
            var depth = 0
            var inString = false
            var escaped = false
            for index in clean[start...].indices {
                let c = clean[index]
                if inString {
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == "\"" { inString = false }
                } else {
                    if c == "\"" { inString = true }
                    else if c == "{" { depth += 1 }
                    else if c == "}" { depth -= 1 }
                }
                if depth == 0 {
                    if let data = String(clean[start...index]).data(using: .utf8),
                       let value = try? decoder.decode(type, from: data) {
                        return value
                    }
                    break
                }
            }
        }
        return nil
    }
}

// MARK: - Date helpers

public extension ISO8601DateFormatter {
    static let catchMeUp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return f
    }()

    static let catchMeUpLocal: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()
}

public enum DateParser {
    /// Parse a model-provided ISO string. Naive strings are treated as local time.
    public static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            df.dateFormat = fmt
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }
}
