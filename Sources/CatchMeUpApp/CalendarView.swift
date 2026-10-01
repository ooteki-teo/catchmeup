import SwiftUI
import UserNotifications
import CatchMeUpCore

struct CalendarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("未来 30 天的日历日程").foregroundStyle(.secondary)
                Spacer()
                if !store.calendarAuthorized {
                    Button("授权日历访问") { Task { await store.requestCalendarAccess() } }
                        .buttonStyle(.borderedProminent)
                }
                Button {
                    Task { await store.refresh() }
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple-calevent://") ?? URL(fileURLWithPath: "/Applications/Calendar.app"))
                } label: { Label("打开日历", systemImage: "calendar") }
            }
            .padding(12)

            Divider()

            if store.calendarEvents.isEmpty {
                EmptyState(icon: "calendar", title: "暂无日程",
                           subtitle: store.calendarAuthorized ? "带截止时间的任务会自动写入日历" : "请先授权日历访问")
            } else {
                List(store.calendarEvents) { event in
                    HStack(alignment: .top, spacing: 12) {
                        VStack {
                            Text(dayString(event.start)).font(.caption2).foregroundStyle(.secondary)
                            Text(timeString(event.start)).font(.body.weight(.semibold))
                        }
                        .frame(width: 64)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.body.weight(.medium))
                            HStack(spacing: 8) {
                                Label(event.calendarName, systemImage: "calendar")
                                if let notes = event.notes, !notes.isEmpty {
                                    Text(notes).lineLimit(1)
                                }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(timeRange(event))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M/d"; return f.string(from: date)
    }
    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
    private func timeRange(_ event: EKEventSummary) -> String {
        "\(timeString(event.start)) – \(timeString(event.end))"
    }
}

struct JobsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("已调度的本地通知。即使关闭 App，系统仍会按时提醒。")
                    .foregroundStyle(.secondary)

                Card(title: "待触发的提醒") {
                    if store.pendingRequests.isEmpty {
                        Text("暂无调度中的提醒").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(store.pendingRequests, id: \.identifier) { request in
                            HStack {
                                Image(systemName: "bell").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.content.title).font(.body)
                                    if !request.content.body.isEmpty {
                                        Text(request.content.body).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if let date = nextDate(request.trigger) {
                                    Text("\(Fmt.relative(date)) · \(Fmt.due(date))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                            if request.identifier != store.pendingRequests.last?.identifier { Divider() }
                        }
                    }
                }

                Card(title: "测试") {
                    HStack {
                        Text("发送一条测试通知（3 秒后）").font(.body)
                        Spacer()
                        Button {
                            Task { await store.sendTestNotification() }
                        } label: { Label("发送测试通知", systemImage: "bell.badge") }
                    }
                }

                Card(title: "提醒规则") {
                    Label("任务设置截止时间后，默认在截止前 \(store.reminderLeadInput) 分钟提醒", systemImage: "clock")
                    Label("重复任务（每天/每周/每月）会按周期重复提醒", systemImage: "repeat")
                    Label("可在设置中调整提前量和是否写入日历", systemImage: "gearshape")
                }
                .font(.body)
            }
            .padding(24)
        }
    }

    private func nextDate(_ trigger: Any?) -> Date? {
        if let t = trigger as? UNCalendarNotificationTrigger { return t.nextTriggerDate() }
        if let t = trigger as? UNTimeIntervalNotificationTrigger { return t.nextTriggerDate() }
        return nil
    }
}
