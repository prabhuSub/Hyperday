import EventKit
import Foundation
import UIKit

/// Reads today's events from every calendar on the phone (Tesla, Google, iCloud…).
final class CalendarService {
    static let shared = CalendarService()

    let store = EKEventStore()

    /// One day's events, cached until the calendar changes (Today used to query EventKit every 30 s).
    private var dayCache: [Date: [Block]] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            self?.dayCache = [:]
        }
    }

    /// Forget cached days (calendar access changed, or a new day started).
    func invalidate() { dayCache = [:] }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var needsPrompt: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Today's events for the Live Activity (declined invites left out).
    func events(on day: Date) -> [Block] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        if let hit = dayCache[start] { return hit }
        let list = events(from: start, to: end)
        if hasAccess {
            if dayCache.count > 7 { dayCache = [:] }
            dayCache[start] = list
        }
        return list
    }

    /// Events from every calendar on the phone in a date range (Calendar tab).
    func events(from start: Date, to end: Date, includeDeclined: Bool = false) -> [Block] {
        guard hasAccess, end > start else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.availability != .free }
            .compactMap { event -> Block? in
                let declined = event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
                if declined && !includeDeclined { return nil }
                return Block(
                    // Recurring events share an identifier, so the start time keeps ids unique per occurrence.
                    id: "cal-\(event.calendarItemIdentifier)-\(Int(event.startDate.timeIntervalSince1970))",
                    title: event.title ?? "Event",
                    start: event.startDate,
                    end: event.endDate,
                    source: .calendar,
                    calendarName: event.calendar?.title,
                    declined: declined,
                    location: event.location?.isEmpty == false ? event.location : nil
                )
            }
    }

    /// Every event calendar on the phone: name + its iOS color (for Settings › Calendars).
    func calendarList() -> [CalendarInfo] {
        guard hasAccess else { return [] }
        var seen = Set<String>()
        return store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .compactMap { c in
                guard seen.insert(c.title).inserted else { return nil }
                return CalendarInfo(name: c.title, hex: UIColor(cgColor: c.cgColor).hexString)
            }
    }
}

struct CalendarInfo: Hashable {
    let name: String
    let hex: String
}

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
