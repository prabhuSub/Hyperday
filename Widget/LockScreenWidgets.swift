import AppIntents
import SwiftUI
import WidgetKit

// Lock Screen widgets picked from the v4 mockups: A "Now", C "Day strip", F "Circles".
// iOS draws these in white only, so everything is primary/secondary opacity, no category colors.

// MARK: - Helpers

private extension WidgetDay {
    static let empty = WidgetDay(day: .distantPast, blocks: [])
}

private func minutesLeft(_ from: Date, _ to: Date) -> String {
    let m = max(0, Int(to.timeIntervalSince(from) / 60))
    return m >= 60 ? String(format: "%d:%02d", m / 60, m % 60) : "\(m)m"
}

private func clock(_ d: Date) -> String {
    d.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
}

private struct Caps: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct Segments: View {
    let done: Int
    let total: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i < done ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.28)))
                    .frame(height: 4)
            }
        }
    }
}

private struct TimeBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.28))
                Capsule().fill(Color.primary).frame(width: g.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - A · Now + steps (rectangular)

struct HyperdayNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.nowKind, provider: DayProvider()) { entry in
            NowRect(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Now")
        .description("The current block, time left, step bar and next step.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct NowRect: View {
    let entry: DayEntry

    var body: some View {
        let day = entry.day ?? .empty
        let now = entry.date
        VStack(alignment: .leading, spacing: 2) {
            if let c = day.current(at: now) {
                Caps(text: "Now · \(minutesLeft(now, c.end)) left")
                Text(c.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                if c.stepsTotal > 0 {
                    Segments(done: c.stepsDone, total: c.stepsTotal).padding(.vertical, 1)
                } else {
                    TimeBar(progress: now.timeIntervalSince(c.start) / max(c.end.timeIntervalSince(c.start), 1))
                        .padding(.vertical, 1)
                }
                Group {
                    if let step = c.nextStep {
                        Text("Step \(c.stepsDone + 1)/\(c.stepsTotal): \(step)")
                    } else if let n = day.upcoming(at: now, limit: 1).first {
                        Text("Next: \(n.title) \(clock(n.start))")
                    } else {
                        Text("Last one today")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else if let n = day.upcoming(at: now, limit: 1).first {
                Caps(text: "Next · in \(minutesLeft(now, n.start))")
                Text(n.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text("\(clock(n.start)) – \(clock(n.end)) · \(n.detail)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Caps(text: "Hyperday")
                Text(entry.day == nil ? "Open Hyperday" : "Day complete")
                    .font(.system(size: 15, weight: .bold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }
}

// MARK: - C · Day strip (rectangular)

struct HyperdayDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.dayKind, provider: DayProvider()) { entry in
            DayStripFamily(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Day strip")
        .description("Your whole day as a strip, with where you are now and what's next. Also a one-line version above the clock.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

/// Rectangular strip, or (v21) the one-line version next to the date above the clock.
struct DayStripFamily: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry
    var body: some View {
        if family == .accessoryInline { DayStripInline(entry: entry) } else { DayStripRect(entry: entry) }
    }
}

/// One line above the clock: "▰▰▰▱▱▱ 41m Deep work" (bar first so a long title truncates, not the bar) — what's on, time left, how far through the day.
/// iOS allows only text here (one line, no shapes), so the bar is drawn with characters.
struct DayStripInline: View {
    let entry: DayEntry

    var body: some View {
        let day = entry.day ?? .empty
        let now = entry.date
        let cells = 6
        let filled = Int((day.progress(at: now) * Double(cells)).rounded())
        let bar = String(repeating: "▰", count: filled) + String(repeating: "▱", count: cells - filled)
        if day.todays(now).isEmpty {
            Text("Hyperday · nothing planned")
        } else if let c = day.current(at: now) {
            Text("\(bar) \(minutesLeft(now, c.end)) \(c.title)")
        } else if let n = day.upcoming(at: now, limit: 1).first {
            Text("\(bar) Free · \(n.title) \(clock(n.start))")
        } else {
            Text("\(bar) Day done")
        }
    }
}

struct DayStripRect: View {
    let entry: DayEntry

    var body: some View {
        let day = entry.day ?? .empty
        let now = entry.date
        let blocks = day.todays(now)
        let left = blocks.filter { $0.end > now }.count
        let pct = Int(day.progress(at: now) * 100)
        let range = window(blocks, now: now)
        let from = range.0
        let to = range.1

        VStack(alignment: .leading, spacing: 3) {
            Caps(text: "\(now.formatted(.dateTime.weekday(.abbreviated))) · \(pct)% of day · \(left) left")
            GeometryReader { g in
                let span = to.timeIntervalSince(from)
                let x: (Date) -> CGFloat = { g.size.width * CGFloat(min(max($0.timeIntervalSince(from) / span, 0), 1)) }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.22))
                    ForEach(blocks) { b in
                        let opacity: Double = b.end <= now ? 0.45 : (b.start <= now ? 1 : 0.75)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(opacity))
                            .frame(width: max(2, x(b.end) - x(b.start) - 1))
                            .offset(x: x(b.start))
                    }
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 16)
                        .offset(x: x(now) - 1)
                }
            }
            .frame(height: 10)
            HStack {
                let marks = ticks(from, to)
                ForEach(marks.indices, id: \.self) { i in
                    Text(marks[i].formatted(.dateTime.hour(.defaultDigits(amPM: .narrow))))
                    if i < marks.count - 1 { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
            if let n = day.upcoming(at: now, limit: 1).first {
                Text("Next: \(n.title) \(clock(n.start))")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            } else {
                Text(entry.day == nil ? "Open Hyperday" : "Nothing else today")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    /// 8 AM – 8 PM, stretched to whole hours if blocks fall outside it.
    private func window(_ blocks: [WidgetBlock], now: Date) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        var from = start.addingTimeInterval(8 * 3600)
        var to = start.addingTimeInterval(20 * 3600)
        if let first = blocks.map(\.start).min(), first < from {
            from = cal.dateInterval(of: .hour, for: first)?.start ?? first
        }
        if let last = blocks.map(\.end).max(), last > to {
            to = min(start.addingTimeInterval(86_400), cal.dateInterval(of: .hour, for: last)?.end ?? last)
        }
        return (max(from, start), to)
    }

    private func ticks(_ from: Date, _ to: Date) -> [Date] {
        let step = to.timeIntervalSince(from) / 3
        return (0...3).map { from.addingTimeInterval(Double($0) * step) }
    }
}

// MARK: - F · Circles (pick what each one shows)

enum CircleMetric: String, AppEnum, CaseIterable {
    case timeLeft, steps, nextStart, blocksLeft

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static var caseDisplayRepresentations: [CircleMetric: DisplayRepresentation] = [
        .timeLeft: "Time left",
        .steps: "Steps done",
        .nextStart: "Next start",
        .blocksLeft: "Blocks left",
    ]
}

struct CircleConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Hyperday circle"
    static var description = IntentDescription("Choose what the circle shows.")

    @Parameter(title: "Show", default: .nextStart)
    var metric: CircleMetric
}

struct CircleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: .now, day: .sample) }

    func snapshot(for configuration: CircleConfigIntent, in context: Context) async -> DayEntry {
        DayEntry(date: .now, day: WidgetShared.load() ?? .sample, metric: configuration.metric)
    }

    func timeline(for configuration: CircleConfigIntent, in context: Context) async -> Timeline<DayEntry> {
        dayTimeline(metric: configuration.metric)
    }
}

struct HyperdayCircleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShared.circleKind, intent: CircleConfigIntent.self, provider: CircleProvider()) { entry in
            CircleView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Circle")
        .description("Time left, steps done, next start or blocks left. Long-press it to choose.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct CircleView: View {
    let entry: DayEntry

    var body: some View {
        let v = values()
        let progress = v.0
        let big = v.1
        let small = v.2
        ZStack {
            Circle().stroke(Color.primary.opacity(0.28), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(big)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(small)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
        }
        .padding(3)
        .widgetAccentable()
    }

    private func values() -> (Double, String, String) {
        let day = entry.day ?? .empty
        let now = entry.date
        let current = day.current(at: now)
        switch entry.metric {
        case .timeLeft:
            guard let c = current else { return (0, "—", "LEFT") }
            let p = now.timeIntervalSince(c.start) / max(c.end.timeIntervalSince(c.start), 1)
            return (p, minutesLeft(now, c.end), "LEFT")
        case .steps:
            guard let c = current, c.stepsTotal > 0 else { return (0, "—", "STEPS") }
            return (Double(c.stepsDone) / Double(c.stepsTotal), "\(c.stepsDone)/\(c.stepsTotal)", "STEPS")
        case .nextStart:
            guard let n = day.upcoming(at: now, limit: 1).first else { return (1, "✓", "DONE") }
            return (day.progress(at: now), clock(n.start), "NEXT")
        case .blocksLeft:
            let all = day.todays(now)
            let left = all.filter { $0.end > now }.count
            return (all.isEmpty ? 0 : Double(all.count - left) / Double(all.count), "\(left)", "LEFT")
        }
    }
}
