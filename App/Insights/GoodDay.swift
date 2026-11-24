import SwiftUI

/// #4 Good-Day formula: what your good days (6+ blocks done) have in common, computed on the iPhone.
struct GoodDayFactor: Identifiable {
    var id: String { name }
    let name: String
    let good: Int      // % of good days with this
    let other: Int     // % of other days with this
}

struct GoodDayReport {
    var goodDays = 0
    var otherDays = 0
    var factors: [GoodDayFactor] = []
    var missing: String?
}

@MainActor
enum GoodDay {
    static let goodThreshold = 6

    static func compute(sleep: [String: Int], workouts: [DateInterval], now: Date = .now) -> GoodDayReport {
        let cal = Calendar.current
        let history = HistoryStore.shared
        let reality = RealityStore.shared
        var good: [Date] = [], other: [Date] = []
        for i in 1...56 {
            guard let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: now)) else { continue }
            let entries = history.entries(on: d)
            guard !entries.isEmpty else { continue }
            if entries.filter(\.done).count >= goodThreshold { good.append(d) } else { other.append(d) }
        }
        var report = GoodDayReport(goodDays: good.count, otherDays: other.count)
        guard good.count >= 4, other.count >= 4 else {
            report.missing = "Needs at least 4 good days (\(goodThreshold)+ done) and 4 other days in the last 8 weeks. "
                + "So far: \(good.count) good, \(other.count) other."
            return report
        }

        func pct(_ days: [Date], _ test: (Date) -> Bool?) -> Int? {
            let known = days.compactMap(test)
            guard !known.isEmpty else { return nil }
            return Int((Double(known.filter { $0 }.count) / Double(known.count) * 100).rounded())
        }
        func factor(_ name: String, _ test: @escaping (Date) -> Bool?) -> GoodDayFactor? {
            guard let g = pct(good, test), let o = pct(other, test) else { return nil }
            return GoodDayFactor(name: name, good: g, other: o)
        }

        let tests: [(String, (Date) -> Bool?)] = [
            ("Slept 7h or more", { d in sleep[HeatData.key(d)].map { $0 >= 420 } }),
            ("First block before 9:30", { d in
                history.entries(on: d).map(\.start).min().map {
                    cal.component(.hour, from: $0) * 60 + cal.component(.minute, from: $0) < 9 * 60 + 30
                }
            }),
            ("3 or fewer meetings", { d in history.entries(on: d).filter { $0.categoryIDs.contains("meetings") }.count <= 3 }),
            ("Workout the day before", { d in
                guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { return nil }
                return workouts.contains { cal.isDate($0.start, inSameDayAs: prev) }
            }),
            ("Commute under 30 min", { d in
                let ev = reality.events.filter { cal.isDate($0.date, inSameDayAs: d) }
                guard let left = ev.first(where: { $0.kind == .departed && $0.place == "Home" }),
                      let arrived = ev.first(where: { $0.kind == .arrived && $0.place == "Office" && $0.date > left.date })
                else { return nil }
                return arrived.date.timeIntervalSince(left.date) < 30 * 60
            }),
        ]
        report.factors = tests.compactMap { factor($0.0, $0.1) }.sorted { ($0.good - $0.other) > ($1.good - $1.other) }
        return report
    }
}

struct GoodDayCard: View {
    @State private var report: GoodDayReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Caps("What your good days have in common")
            if let report {
                if let missing = report.missing {
                    Text(missing).font(.geist(size: 13)).foregroundStyle(Theme.muted)
                } else {
                    Text("Good day = \(GoodDay.goodThreshold)+ blocks done. Last 8 weeks: \(report.goodDays) good days, \(report.otherDays) others.")
                        .font(.geist(size: 12.5)).foregroundStyle(Theme.muted)
                    ForEach(report.factors) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(f.name).font(.geist(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(f.good)% vs \(f.other)%").font(.geist(size: 12)).foregroundStyle(Theme.muted)
                            }
                            GeometryReader { g in
                                VStack(alignment: .leading, spacing: 3) {
                                    Capsule().fill(DayLiveStyle.doneGreen).frame(width: g.size.width * CGFloat(f.good) / 100, height: 7)
                                    Capsule().fill(Theme.faint).frame(width: g.size.width * CGFloat(f.other) / 100, height: 7)
                                }
                            }
                            .frame(height: 17)
                        }
                        .padding(.top, 6)
                    }
                    if let flat = report.factors.last, abs(flat.good - flat.other) < 10 {
                        Text("\(flat.name) barely differs, so it doesn't seem to matter for you.")
                            .font(.geist(size: 11.5)).foregroundStyle(Theme.muted)
                    }
                }
            } else {
                Text("Looking at your last 8 weeks…").font(.geist(size: 13)).foregroundStyle(Theme.muted)
            }
        }
        .cardBox()
        .task {
            let sleep = await HealthReality.sleepByNight(days: 57)
            let start = Calendar.current.date(byAdding: .day, value: -58, to: .now) ?? .now
            let workouts = await HealthReality.workouts(from: start, to: .now)
            report = GoodDay.compute(sleep: sleep, workouts: workouts)
        }
    }
}
