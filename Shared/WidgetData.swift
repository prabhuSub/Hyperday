import Foundation

/// Today's blocks, written by the app into the shared App Group so the Home Screen widgets can read them.
struct WidgetBlock: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var colorHex: String
    var stepsDone: Int
    var stepsTotal: Int
    var detail: String        // "Tesla" / "My plan"
    var nextStep: String? = nil   // first unchecked step, for the Lock Screen "Now" widget
    // v47 dock-style widgets
    var icon: String? = nil       // category icon name (solid)
    var done: Bool? = nil         // marked Done
    var isPlan: Bool? = nil       // your own block (can Pause)
    var paused: Bool? = nil
}

struct WidgetDay: Codable, Equatable {
    var day: Date
    var blocks: [WidgetBlock]

    func isToday(_ date: Date) -> Bool { Calendar.current.isDate(day, inSameDayAs: date) }
    func todays(_ date: Date) -> [WidgetBlock] { isToday(date) ? blocks : [] }

    func current(at date: Date) -> WidgetBlock? {
        todays(date).filter { $0.start <= date && date < $0.end }.min { $0.start < $1.start }
    }

    func upcoming(at date: Date, limit: Int) -> [WidgetBlock] {
        Array(todays(date).filter { $0.start > date }.sorted { $0.start < $1.start }.prefix(limit))
    }

    func progress(at date: Date) -> Double {
        let list = todays(date)
        guard let first = list.map(\.start).min(), let last = list.map(\.end).max(), last > first else { return 0 }
        return min(max(date.timeIntervalSince(first) / last.timeIntervalSince(first), 0), 1)
    }

    static var sample: WidgetDay {
        let now = Date.now
        func t(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }
        return WidgetDay(day: now, blocks: [
            WidgetBlock(id: "1", title: "Commute", start: t(-180), end: t(-135), colorHex: "#64D2FF", stepsDone: 0, stepsTotal: 0, detail: "My plan"),
            WidgetBlock(id: "2", title: "Deep Work — ORBIT AI", start: t(-34), end: t(86), colorHex: "#30D158", stepsDone: 4, stepsTotal: 6, detail: "My plan", nextStep: "Write eval prompts"),
            WidgetBlock(id: "3", title: "Standup", start: t(26), end: t(41), colorHex: "#E31937", stepsDone: 0, stepsTotal: 0, detail: "Tesla"),
            WidgetBlock(id: "4", title: "Lunch", start: t(146), end: t(191), colorHex: "#64D2FF", stepsDone: 0, stepsTotal: 0, detail: "My plan"),
            WidgetBlock(id: "5", title: "Gym — Legs", start: t(506), end: t(566), colorHex: "#FF9F0A", stepsDone: 0, stepsTotal: 4, detail: "My plan"),
        ])
    }
}

enum WidgetShared {
    static let appGroup = "group.com.prabhu.daylive"
    static let kind = "HyperdayToday"
    static let nowKind = "HyperdayLockNow"
    static let dayKind = "HyperdayLockDay"
    static let circleKind = "HyperdayLockCircle"
    static let heatKind = "HyperdayHeat"
    static let calKind = "HyperdayCalendar"

    static var calURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-calendar.json")
    }

    @discardableResult
    static func saveCalendar(_ counts: [String: Int]) -> Bool {
        guard let url = calURL, let data = try? JSONEncoder().encode(counts) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// This week's workload for the Large heatmap widget: day key → [planned hours, done hours].
    static var weekURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-week.json")
    }

    @discardableResult
    static func saveWeek(_ load: [String: [Double]]) -> Bool {
        guard let url = weekURL, let data = try? JSONEncoder().encode(load) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func loadWeek() -> [String: [Double]]? {
        guard let url = weekURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: [Double]].self, from: data)
    }

    static func loadCalendar() -> [String: Int]? {
        guard let url = calURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: Int].self, from: data)
    }

    static var heatURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-heat.json")
    }

    @discardableResult
    static func saveHeat(_ heat: HeatData) -> Bool {
        guard let url = heatURL, let data = try? JSONEncoder().encode(heat) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func loadHeat() -> HeatData? {
        guard let url = heatURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HeatData.self, from: data)
    }

    /// nil when the App Group isn't available (e.g. a free Apple ID).
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-day.json")
    }

    @discardableResult
    static func save(_ day: WidgetDay) -> Bool {
        guard let url = fileURL, let data = try? JSONEncoder().encode(day) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func load() -> WidgetDay? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetDay.self, from: data)
    }
}
