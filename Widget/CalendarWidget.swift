import SwiftUI
import WidgetKit

// v11 variation A "Week band": 3 weeks (last · this · next), Monday first.
// This week sits in a soft rounded band, today is a solid rounded square,
// a thin bar under each date shows how busy it is (longer = busier).
// Lock Screen (rectangular, one tint) and StandBy / Home Screen small (colored bars).

struct CalEntry: TimelineEntry {
    let date: Date
    let counts: [String: Int]
}

struct CalProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalEntry { CalEntry(date: .now, counts: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (CalEntry) -> Void) {
        completion(CalEntry(date: .now, counts: WidgetShared.loadCalendar() ?? (context.isPreview ? Self.sample : [:])))
    }

    /// Redraw just after midnight (today moves); the app reloads it when your plans change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalEntry>) -> Void) {
        let cal = Calendar.current
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))?.addingTimeInterval(30) ?? .now
        let entry = CalEntry(date: .now, counts: WidgetShared.loadCalendar() ?? [:])
        let next = CalEntry(date: midnight, counts: entry.counts)
        completion(Timeline(entries: [entry, next], policy: .after(midnight.addingTimeInterval(3600))))
    }

    static var sample: [String: Int] {
        var c: [String: Int] = [:]
        for i in -10...14 {
            if let d = Calendar.current.date(byAdding: .day, value: i, to: .now) { c[HeatData.key(d)] = [0, 2, 4, 6, 1, 3][abs(i) % 6] }
        }
        return c
    }
}

struct HyperdayCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.calKind, provider: CalProvider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("3-week calendar")
        .description("Last, this and next week. A bar under each date shows how busy it is.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalEntry

    private var big: Bool { family == .systemSmall }

    /// 21 days from Monday of last week.
    private var days: [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: entry.date)?.start,
              let start = cal.date(byAdding: .day, value: -7, to: thisWeek) else { return [] }
        return (0..<21).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// 0 · 1–2 · 3–4 · 5+
    private func level(_ d: Date) -> Int {
        let n = entry.counts[HeatData.key(d)] ?? 0
        return n == 0 ? 0 : n <= 2 ? 1 : n <= 4 ? 2 : 3
    }

    var body: some View {
        let all = days
        VStack(spacing: big ? 4 : 2) {
            HStack(spacing: 1) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.mono(big ? 10 : 7.5, .semibold))
                        .kerning(0.6)
                        .opacity(0.6)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<3, id: \.self) { w in
                HStack(spacing: 1) {
                    ForEach(0..<7, id: \.self) { i in
                        if all.count == 21 { cell(all[w * 7 + i]) }
                    }
                }
                .padding(.horizontal, 1)
                .background {
                    if w == 1 {   // this week
                        RoundedRectangle(cornerRadius: big ? 10 : 8, style: .continuous)
                            .fill(Color.primary.opacity(big ? 0.12 : 0.18))
                    }
                }
            }
        }
        .padding(.horizontal, big ? 0 : 1)
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular { Color.clear } else { InstrumentBackground() }   // v58: JobTrail card
        }
        .environment(\.colorScheme, .dark)
        .widgetURL(URL(string: "hyperday://calendar"))
    }

    private func cell(_ d: Date) -> some View {
        let isToday = Calendar.current.isDate(d, inSameDayAs: entry.date)
        let l = level(d)
        let barColor: Color = family == .accessoryRectangular
            ? (isToday ? .black : .white)
            : (isToday && l > 0 ? Color.black : [Color.clear, HDTone.green, HDTone.amber, HDTone.amber][l])
        let widths: [CGFloat] = big ? [0, 7, 12, 17] : [0, 5, 9, 13]
        return VStack(spacing: big ? 3 : 2) {
            Text("\(Calendar.current.component(.day, from: d))")
                .font(.mono(big ? 15 : 12, isToday ? .bold : .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isToday ? Color.black : Color.primary)
            Capsule()
                .fill(barColor)
                .frame(width: widths[l], height: big ? 2.5 : 1.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: big ? 30 : 19)
        .background {
            if isToday {
                // v58: today is the amber active tile with a soft glow (white on the Lock Screen).
                RoundedRectangle(cornerRadius: big ? 8 : 6, style: .continuous)
                    .fill(family == .accessoryRectangular ? Color.white : HDTone.amber)
                    .shadow(color: HDTone.amber.opacity(family == .accessoryRectangular ? 0 : 0.5), radius: 5)
            }
        }
    }
}
