import SwiftUI
import WidgetKit

// GitHub-style "blocks done" heatmap widgets (v8): full-width grids with equal margins,
// numbers colored against last week, and on Large a "today + next" row.

struct HeatEntry: TimelineEntry {
    let date: Date
    let data: HeatData?
    var day: WidgetDay? = nil
    var week: [String: [Double]] = [:]
}

struct HeatProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeatEntry { HeatEntry(date: .now, data: .sample, day: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (HeatEntry) -> Void) {
        let heat = WidgetShared.loadHeat() ?? (context.isPreview ? .sample : nil)
        completion(HeatEntry(date: .now, data: heat, day: WidgetShared.load() ?? (context.isPreview ? .sample : nil),
                             week: WidgetShared.loadWeek() ?? [:]))
    }

    /// Redraw at every block start/end today (for "Next"), and just after midnight for the new day.
    /// The app also reloads this whenever a block is done.
    func getTimeline(in context: Context, completion: @escaping (Timeline<HeatEntry>) -> Void) {
        let now = Date.now
        let cal = Calendar.current
        let heat = WidgetShared.loadHeat()
        let day = WidgetShared.load()
        let week = WidgetShared.loadWeek() ?? [:]
        var dates: Set<Date> = [now]
        for b in day?.todays(now) ?? [] {
            if b.start > now { dates.insert(b.start) }
            if b.end > now { dates.insert(b.end) }
        }
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))?.addingTimeInterval(60) ?? now
        let entries = dates.filter { $0 < midnight }.sorted().prefix(40).map { HeatEntry(date: $0, data: heat, day: day, week: week) }
        completion(Timeline(entries: Array(entries), policy: .after(midnight)))
    }
}

struct HyperdayHeatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.heatKind, provider: HeatProvider()) { entry in
            HeatWidgetView(entry: entry)
        }
        .configurationDisplayName("Blocks done")
        .description("Your GitHub-style grid of blocks done each day, with your streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Compared with last week

private enum Trend {
    case up, down, same

    var color: Color {
        switch self {
        case .up: return Color(hex: "#30D158")
        case .down: return Color(hex: "#FF453A")
        case .same: return Color(hex: "#8E8E93")
        }
    }

    var arrow: String { self == .up ? "↑" : self == .down ? "↓" : "=" }

    static func of(_ now: Int, vs before: Int) -> Trend { now > before ? .up : now < before ? .down : .same }
}

private struct Numbers {
    let streak: Int, streakDelta: Int, streakTrend: Trend
    let best: Int, bestIsNew: Bool
    let week: Int, weekDelta: Int, weekTrend: Trend

    init(_ d: HeatData, now: Date) {
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        streak = d.streak(now: now)
        let oldStreak = d.streak(now: lastWeek)
        streakDelta = abs(streak - oldStreak)
        streakTrend = Trend.of(streak, vs: oldStreak)
        best = d.best(now: now)
        bestIsNew = streak > 0 && streak >= best
        week = d.thisWeek(now: now)
        let oldWeek = d.thisWeek(now: lastWeek)   // last week, up to the same weekday
        weekDelta = abs(week - oldWeek)
        weekTrend = Trend.of(week, vs: oldWeek)
    }
}

// MARK: - Views

struct HeatWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeatEntry

    var body: some View {
        let data = entry.data ?? HeatData(counts: [:])
        Group {
            switch family {
            case .accessoryRectangular: lock(data)
            case .systemMedium: medium(data)
            case .systemLarge: large(data)
            default: small(data)
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular { AccessoryWidgetBackground() } else { Color(UIColor.systemBackground) }
        }
    }

    private func caps(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 9.5, weight: .heavy))
            .kerning(1.3)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// A grid that fills the given width exactly: weeks fixed, square size computed.
    private func fullGrid(_ d: HeatData, weeks: Int, width: CGFloat, gap: CGFloat,
                          offset: Int = 0, months: Bool = true) -> some View {
        let cell = max(3, (width - gap * CGFloat(weeks - 1)) / CGFloat(weeks))
        return HeatGrid(data: d, weeks: weeks, endWeekOffset: offset, cell: cell, gap: gap,
                        showMonths: months, now: entry.date)
    }

    private func trendText(_ value: String, _ trend: Trend, _ delta: String) -> Text {
        Text(value).foregroundColor(trend.color) + Text(" \(trend.arrow)\(delta.isEmpty ? "" : " " + delta)").foregroundColor(trend.color)
    }

    // Small: 9 weeks, edge to edge, colored streak.
    private func small(_ d: HeatData) -> some View {
        let n = Numbers(d, now: entry.date)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                caps("Streak")
                Spacer()
                trendText("\(n.streak)d", n.streakTrend, "")
                    .font(.system(size: 13, weight: .heavy))
            }
            GeometryReader { geo in
                fullGrid(d, weeks: 9, width: geo.size.width, gap: 2.6, months: false)
            }
        }
    }

    // Medium: 6 months, edge to edge, colored streak + this week.
    private func medium(_ d: HeatData) -> some View {
        let n = Numbers(d, now: entry.date)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                caps("6 months")
                Spacer()
                (trendText("\(n.streak)d streak", n.streakTrend, "")
                 + Text("  ·  ").foregroundColor(.secondary)
                 + trendText("\(n.week) this wk", n.weekTrend, ""))
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
            }
            GeometryReader { geo in
                fullGrid(d, weeks: 26, width: geo.size.width, gap: 2.6)
            }
        }
    }

    // Large (v14): 6-month grid on top, this week's workload below, Streak · Best · This week at the bottom.
    private func large(_ d: HeatData) -> some View {
        let n = Numbers(d, now: entry.date)
        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    caps("Blocks done · 6 months")
                    Spacer()
                    Text("\(d.total()) total").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                fullGrid(d, weeks: 26, width: geo.size.width, gap: 2.6)
                Divider()
                workload(width: geo.size.width)
                    .frame(maxHeight: .infinity)   // bars grow to fill the space above the numbers
                Divider()
                HStack(spacing: 0) {
                    stat("Streak", "\(n.streak)d", n.streakTrend, "\(n.streakDelta)")
                    stat("Best", "\(n.best)d", n.bestIsNew ? .up : .same, n.bestIsNew ? "new" : "")
                    stat("This week", "\(n.week)", n.weekTrend, "\(n.weekDelta)")
                }
            }
        }
    }

    /// Mon–Sun bars: grey = hours planned, green = hours done, today's letter in a white pill.
    private func workload(width: CGFloat) -> some View {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: entry.date)?.start ?? entry.date
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let vals = days.map { entry.week[HeatData.key($0)] ?? [0, 0] }
        let maxH = max(4, vals.map { max($0[0], $0[1]) }.max() ?? 4)
        let planned = vals.reduce(0) { $0 + $1[0] }
        let done = vals.reduce(0) { $0 + $1[1] }
        let green = Color(hex: "#30D158")
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                caps("This week · workload")
                Spacer()
                (Text("\(Int(planned.rounded()))h").bold() + Text(" planned · ")
                 + Text("\(Int(done.rounded()))h").bold().foregroundColor(green) + Text(" done"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { g in
            // Height left for the bars after the hours label (on top) and the day pill (below).
            let barH = max(30, g.size.height - 12 - 17 - 8)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days.indices, id: \.self) { i in
                    let isToday = Calendar.current.isDate(days[i], inSameDayAs: entry.date)
                    VStack(spacing: 3) {
                        Text(vals[i][0] == 0 ? "–" : (vals[i][0].formatted(.number.precision(.fractionLength(0...(vals[i][0] < 10 ? 1 : 0)))) + "h"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isToday ? .primary : .secondary)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.12))
                                .frame(height: max(2, barH * vals[i][0] / maxH))
                            RoundedRectangle(cornerRadius: 4).fill(green)
                                .frame(height: barH * min(vals[i][1], maxH) / maxH)
                        }
                        .frame(width: 20, height: barH, alignment: .bottom)
                        Text(["M", "T", "W", "T", "F", "S", "S"][i])
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(isToday ? Color(UIColor.systemBackground) : .secondary)
                            .frame(width: 20, height: 17)
                            .background { if isToday { RoundedRectangle(cornerRadius: 5).fill(Color.primary) } }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ trend: Trend, _ delta: String) -> some View {
        VStack(spacing: 1) {
            caps(label)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 24, weight: .heavy))
                Text("\(trend.arrow)\(delta.isEmpty || delta == "0" ? "" : " " + delta)")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(trend.color)
        }
        .frame(maxWidth: .infinity)
    }

    private func lock(_ d: HeatData) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(d.streak(now: entry.date))-DAY STREAK")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            HeatGrid(data: d, weeks: 16, cell: 5.6, gap: 1.8, style: .white, showMonths: false, now: entry.date)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }
}
