import SwiftUI
import AppKit
import CatchMeUpCore

@main
struct CatchMeUpApp: App {
    @StateObject private var store = AppStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("CatchMeUp") {
            RootView()
                .environmentObject(store)
                .id(store.language)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L.t("新建任务")) { store.selection = .tasks }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Item detail opened as a real macOS window: movable, resizable, closable.
        WindowGroup(L.t("素材详情"), id: "item-detail", for: String.self) { $itemID in
            if let itemID {
                ItemDetailView(itemID: itemID)
                    .environmentObject(store)
            }
        }
        .defaultSize(width: 780, height: 720)

        MenuBarExtra("CatchMeUp", systemImage: "checklist") {
            MenuBarView()
                .environmentObject(store)
                .id(store.language)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Shared formatting

enum Fmt {
    private static func make(date: DateFormatter.Style, time: DateFormatter.Style) -> DateFormatter {
        let f = DateFormatter()
        f.locale = L.locale
        f.dateStyle = date
        f.timeStyle = time
        return f
    }

    static var dateTime: DateFormatter { make(date: .medium, time: .short) }
    static var full: DateFormatter { make(date: .short, time: .short) }

    static func due(_ date: Date?) -> String {
        guard let date else { return L.t("无截止时间") }
        let cal = Calendar.current
        let time = DateFormatter()
        time.locale = L.locale
        time.timeStyle = .short
        if cal.isDateInToday(date) { return L.f("今天 %@", time.string(from: date)) }
        if cal.isDateInTomorrow(date) { return L.f("明天 %@", time.string(from: date)) }
        if cal.isDateInYesterday(date) { return L.f("昨天 %@", time.string(from: date)) }
        return dateTime.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let delta = date.timeIntervalSinceNow
        let absSeconds = abs(delta)
        if absSeconds < 60 { return delta < 0 ? L.t("已过期") : L.t("即将") }
        if absSeconds < 3600 { return L.f(delta < 0 ? "%d 分钟前" : "%d 分钟后", Int(absSeconds / 60)) }
        if absSeconds < 86400 { return L.f(delta < 0 ? "%d 小时前" : "%d 小时后", Int(absSeconds / 3600)) }
        return L.f(delta < 0 ? "%d 天前" : "%d 天后", Int(absSeconds / 86400))
    }
}
