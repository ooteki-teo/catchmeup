import Foundation
import UserNotifications

/// Schedules local notifications for tasks with a due/reminder time.
/// Local notifications are delivered by the system even when the app is closed.
@MainActor
public final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    private var didInstallDelegate = false

    public override init() { super.init() }

    public func installDelegate() {
        guard !didInstallDelegate else { return }
        center.delegate = self
        didInstallDelegate = true
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        installDelegate()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Returns the notification identifier used, or nil when the task has no future fire time.
    @discardableResult
    public func schedule(task: TaskItem, leadMinutes: Int) async -> String? {
        installDelegate()
        // Never trigger a system prompt here: only schedule if already authorized.
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return nil }
        guard let fireDate = fireDate(for: task, leadMinutes: leadMinutes), fireDate > Date() else {
            return nil
        }
        let identifier = task.notificationID ?? "task_\(task.id)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier, "task_\(task.id)"])

        let content = UNMutableNotificationContent()
        content.title = "任务提醒 · \(task.title)"
        var body = task.detail ?? ""
        if let due = task.dueAt {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 HH:mm"
            body += body.isEmpty ? "截止 \(f.string(from: due))" : "\n截止 \(f.string(from: due))"
        }
        content.body = body.isEmpty ? "该任务即将到期" : body
        content.sound = .default
        content.userInfo = ["taskID": task.id]

        let comps = Self.components(from: fireDate, recurrence: task.recurrence)
        let repeats = task.recurrence != .none
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return identifier
        } catch {
            return nil
        }
    }

    public func cancel(notificationID: String?) {
        guard let notificationID else { return }
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    public func cancel(task: TaskItem) {
        center.removePendingNotificationRequests(withIdentifiers: [task.notificationID ?? "task_\(task.id)"])
    }

    public func pendingRequests() async -> [UNNotificationRequest] {
        let requests = await center.pendingNotificationRequests()
        return requests.sorted { lhs, rhs in
            Self.nextDate(lhs.trigger) < Self.nextDate(rhs.trigger)
        }
    }

    private static func nextDate(_ trigger: UNNotificationTrigger?) -> Date {
        if let t = trigger as? UNCalendarNotificationTrigger { return t.nextTriggerDate() ?? .distantFuture }
        if let t = trigger as? UNTimeIntervalNotificationTrigger { return t.nextTriggerDate() ?? .distantFuture }
        return .distantFuture
    }

    public func sendTest(title: String = "CatchMeUp", body: String = "测试通知") async {
        installDelegate()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "test_\(UUID().uuidString)", content: content, trigger: trigger))
    }

    // MARK: Helpers

    private func fireDate(for task: TaskItem, leadMinutes: Int) -> Date? {
        if let reminder = task.reminderAt { return reminder }
        guard let due = task.dueAt else { return nil }
        return due.addingTimeInterval(-Double(leadMinutes) * 60)
    }

    nonisolated static func components(from date: Date, recurrence: Recurrence) -> DateComponents {
        var calendar = Calendar.current
        calendar.timeZone = .current
        switch recurrence {
        case .none:
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        case .daily:
            return calendar.dateComponents([.hour, .minute], from: date)
        case .weekly:
            return calendar.dateComponents([.weekday, .hour, .minute], from: date)
        case .monthly:
            return calendar.dateComponents([.day, .hour, .minute], from: date)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                                   willPresent notification: UNNotification,
                                                   withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
