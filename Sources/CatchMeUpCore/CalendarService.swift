import Foundation
import EventKit

/// Syncs tasks (with a due date) into the user's calendar as events with an alarm.
@MainActor
public final class CalendarService {
    public static let shared = CalendarService()

    private let store = EKEventStore()

    public init() {}

    public var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    @discardableResult
    public func requestAccess() async -> Bool {
        if hasAccess { return true }
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// Create or update a calendar event for the task. Returns the event identifier.
    @discardableResult
    public func upsertEvent(for task: TaskItem, leadMinutes: Int) -> String? {
        guard hasAccess, let due = task.dueAt else { return nil }
        let event: EKEvent
        if let existingID = task.calendarEventID,
           let found = store.event(withIdentifier: existingID) {
            event = found
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = store.defaultCalendarForNewEvents
        }
        guard let eventCalendar = event.calendar ?? store.defaultCalendarForNewEvents else { return nil }
        event.calendar = eventCalendar
        event.title = task.title
        event.notes = task.detail
        event.startDate = due
        event.endDate = due.addingTimeInterval(30 * 60)
        event.alarms = [EKAlarm(relativeOffset: -Double(leadMinutes) * 60)]
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    public func deleteEvent(identifier: String?) {
        guard let identifier, let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    @discardableResult
    public func deleteEvent(for task: TaskItem) -> Bool {
        guard let identifier = task.calendarEventID, let event = store.event(withIdentifier: identifier) else { return false }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Upcoming events from the default calendar, for the calendar view.
    public func upcomingEvents(days: Int = 14) -> [EKEvent] {
        guard hasAccess else { return [] }
        let calendars = store.calendars(for: .event)
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}
