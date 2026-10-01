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
                .frame(minWidth: 1040, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建任务") { store.selection = .tasks }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Item detail opened as a real macOS window: movable, resizable, closable.
        WindowGroup("素材详情", id: "item-detail", for: String.self) { $itemID in
            if let itemID {
                ItemDetailView(itemID: itemID)
                    .environmentObject(store)
            }
        }
        .defaultSize(width: 780, height: 720)

        MenuBarExtra("CatchMeUp", systemImage: "checklist") {
            MenuBarView()
                .environmentObject(store)
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
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func due(_ date: Date?) -> String {
        guard let date else { return "无截止时间" }
        let cal = Calendar.current
        let time = DateFormatter()
        time.locale = Locale(identifier: "zh_CN")
        time.dateFormat = "HH:mm"
        if cal.isDateInToday(date) { return "今天 \(time.string(from: date))" }
        if cal.isDateInTomorrow(date) { return "明天 \(time.string(from: date))" }
        if cal.isDateInYesterday(date) { return "昨天 \(time.string(from: date))" }
        return dateTime.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let delta = date.timeIntervalSinceNow
        let absSeconds = abs(delta)
        if absSeconds < 60 { return delta < 0 ? "已过期" : "即将" }
        if absSeconds < 3600 { return "\(Int(absSeconds / 60)) 分钟\(delta < 0 ? "前" : "后")" }
        if absSeconds < 86400 { return "\(Int(absSeconds / 3600)) 小时\(delta < 0 ? "前" : "后")" }
        return "\(Int(absSeconds / 86400)) 天\(delta < 0 ? "前" : "后")"
    }
}
