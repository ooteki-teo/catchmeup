import Foundation

// MARK: - Provider kind

public enum AIProviderKind: String, CaseIterable, Identifiable, Sendable {
    case deepseek, openai, openrouter, moonshot, ollama, custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .moonshot: return "Moonshot (Kimi)"
        case .ollama: return "Ollama (local)"
        case .custom: return L.t("自定义")
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .openai: return "https://api.openai.com"
        case .openrouter: return "https://openrouter.ai/api"
        case .moonshot: return "https://api.moonshot.cn"
        case .ollama: return "http://127.0.0.1:11434"
        case .custom: return "https://api.example.com"
        }
    }

    public var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-flash"
        case .openai: return "gpt-4o-mini"
        case .openrouter: return "openai/gpt-4o-mini"
        case .moonshot: return "moonshot-v1-8k"
        case .ollama: return "llama3.1"
        case .custom: return "default"
        }
    }

    /// Ollama runs locally and needs no key.
    public var requiresAPIKey: Bool { self != .ollama }
}

// MARK: - Provider protocol

public protocol AIProvider: Sendable {
    var displayName: String { get }
    func chat(_ messages: [ChatMessage],
              temperature: Double,
              maxTokens: Int,
              jsonMode: Bool,
              attempts: Int) async throws -> String
}

// MARK: - OpenAI-compatible provider

/// Works with any OpenAI-compatible `/v1/chat/completions` endpoint
/// (DeepSeek, OpenAI, OpenRouter, Moonshot, Ollama, ...).
public struct OpenAICompatibleProvider: AIProvider {
    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var requiresAPIKey: Bool

    public init(apiKey: String, baseURL: URL, model: String, requiresAPIKey: Bool = true) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.requiresAPIKey = requiresAPIKey
    }

    public var displayName: String { model }

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

    public func chat(_ messages: [ChatMessage],
                     temperature: Double = 0.3,
                     maxTokens: Int = 8000,
                     jsonMode: Bool = true,
                     attempts: Int = 3) async throws -> String {
        if requiresAPIKey && apiKey.isEmpty { throw CatchMeUpError.missingAPIKey }

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
                if !apiKey.isEmpty {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }
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
                // Reasoning models may spend the whole budget on reasoning first.
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
}

// MARK: - Provider settings (per-provider key / model / base URL)

public enum AIProviderSettings {
    public static var kind: AIProviderKind {
        get { AIProviderKind(rawValue: Prefs.providerRaw) ?? .deepseek }
        set { Prefs.providerRaw = newValue.rawValue }
    }

    public static func apiKey(for kind: AIProviderKind) -> String? {
        if let value = SecretStore.string("apikey_\(kind.rawValue)"), !value.isEmpty { return value }
        // Backward compatibility with the previous single-provider storage.
        if kind == .deepseek { return SecretStore.string("deepseek_api_key") }
        return nil
    }

    public static func setAPIKey(_ value: String?, for kind: AIProviderKind) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        SecretStore.set((trimmed?.isEmpty ?? true) ? nil : trimmed, for: "apikey_\(kind.rawValue)")
    }

    public static func model(for kind: AIProviderKind) -> String {
        let stored = UserDefaults.standard.string(forKey: "model_\(kind.rawValue)")
        return (stored?.isEmpty == false) ? stored! : kind.defaultModel
    }
    public static func setModel(_ value: String, for kind: AIProviderKind) {
        UserDefaults.standard.set(value, forKey: "model_\(kind.rawValue)")
    }

    public static func baseURL(for kind: AIProviderKind) -> String {
        let stored = UserDefaults.standard.string(forKey: "baseURL_\(kind.rawValue)")
        return (stored?.isEmpty == false) ? stored! : kind.defaultBaseURL
    }
    public static func setBaseURL(_ value: String, for kind: AIProviderKind) {
        UserDefaults.standard.set(value, forKey: "baseURL_\(kind.rawValue)")
    }

    public static func makeClient(organizerPrompt: String?, handoffPrompt: String?) -> AIClient {
        let kind = self.kind
        let url = URL(string: baseURL(for: kind)) ?? URL(string: kind.defaultBaseURL)!
        return AIClient(apiKey: apiKey(for: kind) ?? "",
                        baseURL: url,
                        model: model(for: kind),
                        requiresAPIKey: kind.requiresAPIKey,
                        organizerPrompt: organizerPrompt,
                        handoffPrompt: handoffPrompt)
    }
}
