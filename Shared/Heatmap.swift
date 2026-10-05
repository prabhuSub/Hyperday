import SwiftUI

/// Blocks done per day, for the GitHub-style heatmap (Stats card + widgets).
/// A block counts when you tapped Done on it or checked all its steps.
struct HeatData: Codable, Equatable {
    var counts: [String: Int]     // "2026-09-30" -> blocks done
    var updated: Date = .now

    init(counts: [String: Int], updated: Date = .now) {
        self.counts = counts
        self.updated = updated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counts = try c.decode([String: Int].self, forKey: .counts)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? .now
    }

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func count(_ day: Date) -> Int { counts[Self.key(day)] ?? 0 }

    /// Days in a row with at least one block done, ending today (or yesterday, if today has none yet).
    func streak(now: Date = .now) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: now)
        if count(day) == 0, let y = cal.date(byAdding: .day, value: -1, to: day) { day = y }
        var n = 0
        while count(day) > 0, n < 3650, let prev = cal.date(byAdding: .day, value: -1, to: day) {
            n += 1
            day = prev
        }
        return n
    }

    func best(days: Int = 371, now: Date = .now) -> Int {
        let cal = Calendar.current
        var best = 0, run = 0
        for i in stride(from: days, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            run = count(d) > 0 ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    func total(days: Int = 365, now: Date = .now) -> Int {
        let cal = Calendar.current
        return (0..<days).reduce(0) { sum, i in
            sum + (cal.date(byAdding: .day, value: -i, to: now).map(count) ?? 0)
        }
    }

    func thisWeek(now: Date = .now) -> Int {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return (0..<7).reduce(0) { sum, i in
            guard let d = cal.date(byAdding: .day, value: i, to: start), d <= now else { return sum }
            return sum + count(d)
        }
    }

    static let sample: HeatData = {
        var c: [String: Int] = [:]
        var seed: UInt64 = 7
        for i in 0..<371 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Int((seed >> 33) % 10)
            let d = Calendar.current.date(byAdding: .day, value: -i, to: .now) ?? .now
            c[key(d)] = i < 12 ? max(3, r) : (r < 2 ? 0 : r - 1)
        }
        return HeatData(counts: c)
    }()
}

enum HeatStyle {
    case green, white   // white = Lock Screen (iOS draws it in one color)

    /// 0 · 1–2 · 3–4 · 5–6 · 7+
    static func level(_ n: Int) -> Int { n == 0 ? 0 : n <= 2 ? 1 : n <= 4 ? 2 : n <= 6 ? 3 : 4 }

    func color(_ level: Int, dark: Bool) -> Color {
        switch self {
        case .white:
            return Color.primary.opacity([0.16, 0.38, 0.58, 0.8, 1][level])
        case .green:
            let light = ["#EBEDF0", "#B7ECC4", "#6FD98A", "#30D158", "#1F8A3B"]
            let darkHex = ["#1F2023", "#123D20", "#1B6B33", "#27A348", "#39D35C"]
            return Color(hex: (dark ? darkHex : light)[level])
        }
    }
}

/// Weeks as columns (Sunday on top), newest week on the right, like GitHub.
struct HeatGrid: View {
    let data: HeatData
    var weeks: Int = 53
    var endWeekOffset: Int = 0          // 26 = the half-year before the last 26 weeks
    var cell: CGFloat = 11
    var gap: CGFloat = 3
    var style: HeatStyle = .green
    var showMonths = true
    var selected: Date? = nil
    var now: Date = .now
    var onTap: ((Date) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var columns: [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let lastStart = cal.date(byAdding: .day, value: -7 * endWeekOffset, to: thisWeek) else { return [] }
        return (0..<weeks).reversed().map { back -> [Date?] in
            guard let start = cal.date(byAdding: .day, value: -7 * back, to: lastStart) else { return [] }
            return (0..<7).map { i in
                guard let d = cal.date(byAdding: .day, value: i, to: start) else { return nil }
                return d <= today ? d : nil
            }
        }
    }

    var body: some View {
        let cols = columns
        VStack(alignment: .leading, spacing: 3) {
            if showMonths {
                HStack(spacing: gap) {
                    ForEach(cols.indices, id: \.self) { i in
                        let first = cols[i].compactMap { $0 }.first
                        let label = first.flatMap { d -> String? in
                            Calendar.current.component(.day, from: d) <= 7
                                ? d.formatted(.dateTime.month(.abbreviated)) : nil
                        }
                        Text(label ?? "")
                            .font(.system(size: max(8, cell * 0.8)))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .frame(width: cell, alignment: .leading)
                    }
                }
            }
            HStack(alignment: .top, spacing: gap) {
                ForEach(cols.indices, id: \.self) { i in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { r in
                            square(cols[i].indices.contains(r) ? cols[i][r] : nil)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func square(_ day: Date?) -> some View {
        if let day {
            let shape = RoundedRectangle(cornerRadius: max(1.5, cell * 0.22), style: .continuous)
            let isSel = selected.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
            shape
                .fill(style.color(HeatStyle.level(data.count(day)), dark: scheme == .dark))
                .frame(width: cell, height: cell)
                .overlay(shape.stroke(Color.primary, lineWidth: isSel ? 1.5 : 0))
                .contentShape(Rectangle())
                .onTapGesture { onTap?(day) }
                .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)): \(data.count(day)) done")
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }
}

struct HeatLegend: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 4) {
            Text("Less")
            ForEach(0..<5, id: \.self) { l in
                RoundedRectangle(cornerRadius: 2).fill(HeatStyle.green.color(l, dark: scheme == .dark))
                    .frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}
