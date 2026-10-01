import Foundation

/// Token counters for one bucket (a model, or the grand total).
public struct TokenUsage: Codable, Sendable, Hashable {
    public var promptTokens: Int = 0
    public var completionTokens: Int = 0
    public var totalTokens: Int = 0
    public var requests: Int = 0

    public init() {}

    public mutating func add(prompt: Int, completion: Int, total: Int) {
        promptTokens += prompt
        completionTokens += completion
        totalTokens += total
        requests += 1
    }

    public mutating func merge(_ other: TokenUsage) {
        promptTokens += other.promptTokens
        completionTokens += other.completionTokens
        totalTokens += other.totalTokens
        requests += other.requests
    }
}

public struct UsageStats: Codable, Sendable {
    public var total = TokenUsage()
    public var byModel: [String: TokenUsage] = [:]
    public var firstRecordedAt: Double?
    public var updatedAt: Double?

    public init() {}

    public static let empty = UsageStats()
}

/// Process-wide, file-backed token accumulation (no network, no prompts).
public final class UsageTracker: @unchecked Sendable {
    public static let shared = UsageTracker()

    /// Overridable for tests.
    static var directoryOverride: URL?

    private let lock = NSLock()
    private var stats: UsageStats

    private static var directory: URL { directoryOverride ?? AppPaths.supportDirectory }
    private static var fileURL: URL { directory.appendingPathComponent("usage.json") }

    init() {
        stats = Self.load()
    }

    private static func load() -> UsageStats {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(UsageStats.self, from: data) else {
            return UsageStats()
        }
        return decoded
    }

    private func persistLocked() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic])
    }

    public func record(prompt: Int, completion: Int, total: Int, model: String) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        if stats.firstRecordedAt == nil { stats.firstRecordedAt = now }
        stats.updatedAt = now
        stats.total.add(prompt: prompt, completion: completion, total: total)
        var bucket = stats.byModel[model] ?? TokenUsage()
        bucket.add(prompt: prompt, completion: completion, total: total)
        stats.byModel[model] = bucket
        persistLocked()
    }

    public func snapshot() -> UsageStats {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        stats = UsageStats()
        persistLocked()
    }
}
