import Foundation

/// Local, file-based secret storage (no Keychain → no access prompts).
/// Lives at `~/Library/Application Support/CatchMeUp/secrets.json` with 0600 permissions.
public enum SecretStore {
    /// Overridable for tests; defaults to the app support directory.
    static var directoryOverride: URL?

    private static var directory: URL { directoryOverride ?? AppPaths.supportDirectory }
    private static var url: URL { directory.appendingPathComponent("secrets.json") }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private static func save(_ dict: [String: String]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func string(_ key: String) -> String? {
        let value = load()[key]
        return (value?.isEmpty ?? true) ? nil : value
    }

    public static func set(_ value: String?, for key: String) {
        var dict = load()
        if let value, !value.isEmpty {
            dict[key] = value
        } else {
            dict.removeValue(forKey: key)
        }
        save(dict)
    }
}

/// Non-secret preferences (UserDefaults-backed).
public enum Prefs {
    private static let defaults = UserDefaults.standard
    private static let apiKeyKey = "deepseek_api_key"

    public static var model: String {
        get { defaults.string(forKey: "model") ?? "deepseek-flash" }
        set { defaults.set(newValue, forKey: "model") }
    }

    public static var baseURL: String {
        get { defaults.string(forKey: "baseURL") ?? "https://api.deepseek.com" }
        set { defaults.set(newValue, forKey: "baseURL") }
    }

    public static var reminderLeadMinutes: Int {
        get { defaults.object(forKey: "reminderLeadMinutes") as? Int ?? 5 }
        set { defaults.set(newValue, forKey: "reminderLeadMinutes") }
    }

    public static var writeToCalendar: Bool {
        get { defaults.object(forKey: "writeToCalendar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "writeToCalendar") }
    }

    public static var launchAtLogin: Bool {
        get { defaults.object(forKey: "launchAtLogin") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    /// Screenshot global hot key (Carbon key code). Default: M (46).
    public static var screenshotKeyCode: Int {
        get { defaults.object(forKey: "screenshotKeyCode") as? Int ?? 46 }
        set { defaults.set(newValue, forKey: "screenshotKeyCode") }
    }

    /// Screenshot global hot key modifiers (Carbon flags). Default: ⌘⇧ (0x0100 | 0x0200).
    public static var screenshotModifiers: Int {
        get { defaults.object(forKey: "screenshotModifiers") as? Int ?? (0x0100 | 0x0200) }
        set { defaults.set(newValue, forKey: "screenshotModifiers") }
    }

    // MARK: Language

    public static var followSystemLanguage: Bool {
        get { defaults.object(forKey: "followSystemLanguage") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "followSystemLanguage") }
    }

    public static var languageOverride: String {
        get { defaults.string(forKey: "languageOverride") ?? AppLanguage.en.rawValue }
        set { defaults.set(newValue, forKey: "languageOverride") }
    }

    /// The language currently in effect.
    public static var language: AppLanguage {
        if followSystemLanguage { return AppLanguage.systemDefault() }
        return AppLanguage(rawValue: languageOverride) ?? .en
    }

    /// Custom organizer prompt; empty means "use built-in default".
    public static var organizerPrompt: String {
        get { defaults.string(forKey: "organizerPrompt") ?? "" }
        set { defaults.set(newValue, forKey: "organizerPrompt") }
    }

    /// Custom hand-off prompt; empty means "use built-in default".
    public static var handoffPrompt: String {
        get { defaults.string(forKey: "handoffPrompt") ?? "" }
        set { defaults.set(newValue, forKey: "handoffPrompt") }
    }

    /// API key: environment override first, then the local secrets file.
    public static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty {
            return env
        }
        return SecretStore.string(apiKeyKey)
    }

    public static func setAPIKey(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        SecretStore.set((trimmed?.isEmpty ?? true) ? nil : trimmed, for: apiKeyKey)
    }
}
