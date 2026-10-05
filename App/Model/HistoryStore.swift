import Combine
import Foundation
import SwiftUI
import WidgetKit

/// One block as it actually happened on a given day.
struct HistoryEntry: Codable, Hashable, Identifiable {
    var id: String            // block id
    var title: String
    var categoryID: String
    var source: BlockSource
    var start: Date
    var plannedEnd: Date
    var actualEnd: Date       // Done tap, planned end, or "now" if still running
    var stepsDone: Int
    var stepsTotal: Int
    var done: Bool            // tapped Done, or every step checked
    var extraCategoryIDs: [String]? = nil   // more categories; time is split evenly

    var hours: Double { max(0, actualEnd.timeIntervalSince(start)) / 3600 }
    var categoryIDs: [String] { [categoryID] + (extraCategoryIDs ?? []) }
    /// Hours per category, split evenly when a block has several.
    var shares: [(id: String, hours: Double)] {
        let ids = categoryIDs
        return ids.map { ($0, hours / Double(ids.count)) }
    }
    func hours(in ids: Set<String>) -> Double { shares.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.hours } }
    var endedEarly: Bool { done && actualEnd < plannedEnd.addingTimeInterval(-60) }
}

struct DayRecord: Codable, Hashable {
    var day: String           // "2026-09-28"
    var entries: [HistoryEntry]
    var isDemo: Bool = false
}

extension DayRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        entries = try c.decode([HistoryEntry].self, forKey: .entries)
        isDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }
}

enum StatsRange: String, CaseIterable, Hashable {
    case week = "Week", month = "Month", year = "Year"
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }
}

struct CategoryHours: Identifiable {
    var id: String
    var name: String
    var color: Color
    var hours: Double
}

struct StatsSummary {
    var title: String
    var subtitle: String
    var focusedHours: Double
    var stepsDone: Int
    var streak: Int
    var byCategory: [CategoryHours]
    var meetingHours: Double
    var planHours: Double
    var blocksDone: Int
    var endedEarly: Int
    var missed: Int
    var isEmpty: Bool
}

/// Daily log that feeds the Stats tab. Saved as JSON in Documents.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var days: [String: DayRecord] = [:]

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("daylive-history.json")
    }()

    private init() {
        load()
        publishHeat()
    }

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var hasDemo: Bool { days.values.contains { $0.isDemo } }

    // MARK: Recording

    /// Rewrites today's record from the live blocks. Called on every refresh.
    func recordToday(raw: [Block], now: Date) {
        let bs = BlockStore.shared
        let cs = CategoryStore.shared
        let entries: [HistoryEntry] = raw.filter { $0.start <= now }.map { b in
            let o = bs.overrides[b.id]
            let st = bs.steps(for: b.id)
            let start = min(b.start, o?.start ?? b.start)
            let end = min(b.end, o?.end ?? b.end, now)
            let allSteps = !st.isEmpty && st.allSatisfy(\.done)
            let cats = cs.categories(for: b).map(\.id)
            return HistoryEntry(
                id: b.id, title: b.title, categoryID: cats.first ?? cs.category(for: b).id, source: b.source,
                start: start, plannedEnd: b.end, actualEnd: max(start, end),
                stepsDone: st.filter(\.done).count, stepsTotal: st.count,
                done: o?.end != nil || allSteps,
                extraCategoryIDs: cats.count > 1 ? Array(cats.dropFirst()) : nil
            )
        }
        let key = Self.key(now)
        let record = DayRecord(day: key, entries: entries)
        guard days[key] != record else { return }
        days[key] = record
        save()
    }

    // MARK: Heatmap

    /// Blocks done per day (Done tapped, or every step checked).
    var heat: HeatData {
        HeatData(counts: days.mapValues { rec in rec.entries.filter(\.done).count }.filter { $0.value > 0 })
    }

    func entries(on day: Date) -> [HistoryEntry] {
        (days[Self.key(day)]?.entries ?? []).sorted { $0.start < $1.start }
    }

    private var lastHeatCounts: [String: Int]?

    /// Hand the counts to the heatmap widgets when they change.
    private func publishHeat() {
        let h = heat
        guard h.counts != lastHeatCounts else { return }
        lastHeatCounts = h.counts
        if WidgetShared.saveHeat(h) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.heatKind)
        }
    }

    // MARK: Stats

    func summary(_ range: StatsRange, now: Date = .now) -> StatsSummary {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let keys: [String] = (0..<range.days).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.map(Self.key)
        let entries = keys.compactMap { days[$0] }.flatMap(\.entries)

        let categories = CategoryStore.shared.categories
        var byID: [String: Double] = [:]
        for e in entries { for s in e.shares { byID[s.id, default: 0] += s.hours } }
        let byCategory = categories
            .map { CategoryHours(id: $0.id, name: $0.name, color: $0.color, hours: byID[$0.id] ?? 0) }
            .filter { $0.hours > 0.05 }

        let plans = entries.filter { $0.source == .plan }
        let startDay = cal.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
        let fmt: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()).uppercased() }

        let title: String
        switch range {
        case .week: title = "This week"
        case .month: title = "Last 30 days"
        case .year: title = "Last 12 months"
        }

        return StatsSummary(
            title: title,
            subtitle: "\(fmt(startDay)) – \(fmt(today))",
            focusedHours: entries.reduce(0) { $0 + $1.hours(in: ["work", "deepwork"]) },
            stepsDone: entries.reduce(0) { $0 + $1.stepsDone },
            streak: streak(now: now),
            byCategory: byCategory,
            meetingHours: entries.reduce(0) { $0 + $1.hours(in: ["meetings"]) },
            planHours: plans.reduce(0) { $0 + $1.hours },
            blocksDone: entries.filter(\.done).count,
            endedEarly: entries.filter(\.endedEarly).count,
            missed: plans.filter { !$0.done && $0.plannedEnd < now }.count,
            isEmpty: entries.isEmpty
        )
    }

    /// Days in a row where every block you planned yourself was Done. Today only counts once it qualifies.
    func streak(now: Date = .now) -> Int {
        let cal = Calendar.current
        var count = 0
        for i in 0..<400 {
            guard let day = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: now)) else { break }
            let plans = days[Self.key(day)]?.entries.filter { $0.source == .plan } ?? []
            let good = !plans.isEmpty && plans.allSatisfy(\.done)
            if good { count += 1 } else if i == 0 { continue } else { break }
        }
        return count
    }

    // MARK: Demo data

    func setDemoDays(_ records: [DayRecord]) {
        days = days.filter { !$0.value.isDemo }
        for r in records where days[r.day] == nil { days[r.day] = r }
        save()
    }

    func removeDemo() {
        days = days.filter { !$0.value.isDemo }
        save()
    }

    // MARK: Persistence

    /// True when the file couldn't be read or decoded: saving is off so it is never overwritten.
    private var loadBlocked = false

    private func load() {
        switch SafeFile.load([DayRecord].self, from: fileURL) {
        case .loaded(let list):
            days = Dictionary(list.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
            loadBlocked = false
        case .missing: loadBlocked = false
        case .unavailable, .unreadable: loadBlocked = true
        }
    }

    /// Called when the app becomes active: a file that was locked at launch can be read now.
    func retryLoadIfNeeded() {
        guard loadBlocked else { return }
        load()
        if !loadBlocked { publishHeat() }
    }

    private func save() {
        guard !loadBlocked else { return }
        let list = days.values.sorted { $0.day < $1.day }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: .atomic)
        publishHeat()
    }
}

// MARK: - Sample data

/// "Load sample data" in Settings: 8 weeks of history + a planned day like the mockup.
/// Never touches your real calendars.
@MainActor
enum DemoData {
    static var isLoaded: Bool { HistoryStore.shared.hasDemo }

    static func load(now: Date = .now) {
        HistoryStore.shared.setDemoDays(history(now: now))
        loadToday(now: now)
    }

    static func remove() {
        HistoryStore.shared.removeDemo()
        BlockStore.shared.removeDemo()
    }

    /// Small deterministic random generator so the sample looks the same every time.
    private struct Rng {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private static func at(_ day: Date, _ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
    }

    private static func history(now: Date) -> [DayRecord] {
        let cal = Calendar.current
        var rng = Rng(state: 42)
        var out: [DayRecord] = []
        for back in 1...56 {
            guard let day = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now)) else { continue }
            let weekday = cal.component(.weekday, from: day)   // 1 = Sunday
            let weekend = weekday == 1 || weekday == 7
            let recent = back <= 9                               // last 9 days: perfect streak
            var e: [HistoryEntry] = []
            func add(_ id: String, _ title: String, _ cat: String, _ src: BlockSource,
                     _ sh: Int, _ sm: Int, _ eh: Int, _ em: Int, steps: Int = 0, doneChance: Double = 1) {
                let start = at(day, sh, sm), planned = at(day, eh, em)
                let r1 = rng.next(), r2 = rng.next(), r3 = rng.next()
                var done = src == .plan && (recent || r1 < doneChance)
                if back == 10 && src == .plan && id == "deep" { done = false }  // the day that ended the streak
                let early = done && r2 < 0.15
                let end = early ? planned.addingTimeInterval(-20 * 60) : planned
                let stepsDone = steps == 0 ? 0 : (done ? steps : Int(r3 * Double(steps)))
                e.append(HistoryEntry(id: "demo-\(back)-\(id)", title: title, categoryID: cat, source: src,
                                      start: start, plannedEnd: planned, actualEnd: end,
                                      stepsDone: stepsDone, stepsTotal: steps, done: done))
            }
            if weekend {
                let g = rng.next()
                if g < 0.5 { add("gym", "Long run", "fitness", .plan, 9, 0, 10, 0, doneChance: 0.8) }
                add("family", "Family time", "family", .plan, 11, 0, 14, 0)
                add("personal", "Side project", "personal", .plan, 15, 0, 17, 0, steps: 3, doneChance: 0.85)
            } else {
                add("commute", "Commute", "personal", .plan, 8, 30, 9, 15)
                let n = 4 + Int(rng.next() * 3)
                add("deep", "Deep Work — ORBIT AI", "deepwork", .plan, 9, 30, 11, 30, steps: n, doneChance: 0.85)
                add("standup", "Standup", "meetings", .calendar, 10, 0, 10, 15)
                let o = rng.next()
                if o < 0.7 { add("oneonone", "1:1 / Review", "meetings", .calendar, 13, 0, 14, 0) }
                add("work", "ORBIT delivery", "work", .calendar, 14, 0, 16, 30)
                let extraGym = rng.next()
                if [2, 4, 6].contains(weekday) || extraGym < 0.3 {
                    add("gym", "Gym — Legs", "fitness", .plan, 18, 30, 19, 30, steps: 4, doneChance: 0.8)
                }
                add("dinner", "Dinner", "family", .plan, 19, 30, 20, 30)
            }
            out.append(DayRecord(day: HistoryStore.key(day), entries: e, isDemo: true))
        }
        return out
    }

    /// Today's planned blocks around "now", matching the mockup.
    private static func loadToday(now: Date) {
        let cal = Calendar.current
        let q = (now.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900
        let base = Date(timeIntervalSinceReferenceDate: q)
        func t(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }
        let p = BlockStore.demoPrefix
        let blocks = [
            Block(id: p + "commute", title: "Commute", start: t(-180), end: t(-135), source: .plan),
            Block(id: p + "deep", title: "Deep Work — ORBIT AI", start: t(-60), end: t(60), source: .plan),
            Block(id: p + "standup", title: "Standup", start: t(75), end: t(90), source: .plan),
            Block(id: p + "lunch", title: "Lunch", start: t(120), end: t(165), source: .plan),
            Block(id: p + "gym", title: "Gym — Legs", start: t(300), end: t(360), source: .plan),
        ].filter { cal.isDate($0.start, inSameDayAs: now) || $0.start > now }
        let steps: [String: [Step]] = [
            p + "deep": [
                Step(title: "Review Ziplabs API", done: true), Step(title: "Design map layer", done: true),
                Step(title: "Hook up data feed", done: true), Step(title: "Add clustering", done: true),
                Step(title: "Wire up map layer"), Step(title: "Write test plan"),
            ],
            p + "gym": [
                Step(title: "Squats"), Step(title: "Romanian deadlifts"),
                Step(title: "Lunges"), Step(title: "Calf raises"),
            ],
        ]
        let cats = [p + "commute": "personal", p + "deep": "deepwork", p + "standup": "meetings",
                    p + "lunch": "personal", p + "gym": "fitness"]
        BlockStore.shared.addDemo(blocks: blocks, steps: steps, categories: cats, finished: [p + "commute": t(-135)])
    }
}
