import SwiftUI
import WidgetKit

// MARK: - Timeline

struct DayEntry: TimelineEntry {
    let date: Date
    let day: WidgetDay?
    var needsAppGroup: Bool = false
    var metric: CircleMetric = .nextStart
}

/// Entries at every block start/end today, plus every 5 minutes for the next 2 hours
/// (the Lock Screen widgets show minutes left, which can't tick on their own).
func dayTimeline(metric: CircleMetric = .nextStart) -> Timeline<DayEntry> {
    let now = Date.now
    let day = WidgetShared.load()
    var dates: Set<Date> = [now]
    for b in day?.todays(now) ?? [] {
        if b.start > now { dates.insert(b.start) }
        if b.end > now { dates.insert(b.end) }
    }
    let minute = Calendar.current.component(.minute, from: now)
    let minuteStart = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now   // :04:30 → :04:00
    let firstTick = minuteStart.addingTimeInterval(Double(5 - minute % 5) * 60)
    for i in 0..<24 { dates.insert(firstTick.addingTimeInterval(Double(i) * 300)) }
    let entries = dates.sorted().prefix(80).map {
        DayEntry(date: $0, day: day, needsAppGroup: WidgetShared.fileURL == nil, metric: metric)
    }
    let tomorrow = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 + 60)
    return Timeline(entries: Array(entries), policy: .after(min(tomorrow, now.addingTimeInterval(2 * 3600))))
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, day: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let day = WidgetShared.load()
        completion(DayEntry(date: .now, day: day ?? (context.isPreview ? .sample : nil),
                            needsAppGroup: WidgetShared.fileURL == nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        completion(dayTimeline())
    }
}

// MARK: - Widget

struct HyperdayTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind, provider: DayProvider()) { entry in
            HyperdayWidgetView(entry: entry)
        }
        .configurationDisplayName("Hyperday")
        .description("What's on now and what's next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HyperdayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        Group {
            if entry.day == nil {
                EmptyWidget(needsAppGroup: entry.needsAppGroup)
            } else {
                switch family {
                case .systemMedium: MediumWidget(entry: entry)
                case .systemLarge: LargeWidget(entry: entry)
                default: SmallWidget(entry: entry)
                }
            }
        }
        .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
    }
}

// MARK: - Pieces

private struct WCaps: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct Ring: View {
    let progress: Double
    var color: Color
    var width: CGFloat = 5
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: width)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct WRow: View {
    let block: WidgetBlock
    let date: Date

    var body: some View {
        let isNow = block.start <= date && date < block.end
        let done = block.end <= date
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: block.colorHex))
                .opacity(done ? 0.4 : 1)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.system(size: 13, weight: isNow ? .bold : .medium))
                    .foregroundStyle(done ? .secondary : .primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isNow {
                Text("NOW")
                    .font(.system(size: 8, weight: .heavy))
                    .kerning(1)
                    .foregroundStyle(Color(hex: "#E31937"))
            }
        }
    }

    private var detail: String {
        var parts = [block.start.formatted(date: .omitted, time: .shortened), block.detail]
        if block.stepsTotal > 0 { parts.append("\(block.stepsDone)/\(block.stepsTotal) steps") }
        return parts.joined(separator: " · ")
    }
}

private struct Mark: View {
    var body: some View {
        Image("HyperdayMark")
            .resizable()
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Families

private struct SmallWidget: View {
    let entry: DayEntry

    var body: some View {
        let day = entry.day ?? WidgetDay(day: entry.date, blocks: [])
        let current = day.current(at: entry.date)
        let next = day.upcoming(at: entry.date, limit: 1).first
        let color = Color(hex: current?.colorHex ?? next?.colorHex ?? "#30D158")

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                WCaps(text: current != nil ? "Now" : (next != nil ? "Next" : "Today"), color: color)
                Spacer()
                Mark()
            }
            Text(current?.title ?? next?.title ?? "Nothing planned")
                .font(.system(size: 16, weight: .bold))
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    if let c = current {
                        Text(timerInterval: entry.date...c.end, countsDown: true)
                            .font(.system(size: 18, weight: .bold).monospacedDigit())
                            .lineLimit(1)
                        Text(c.stepsTotal > 0 ? "left · \(c.stepsDone)/\(c.stepsTotal) steps" : "left")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if let n = next {
                        Text(n.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 18, weight: .bold))
                        Text(n.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Ring(progress: day.progress(at: entry.date), color: color)
                    .frame(width: 36, height: 36)
            }
        }
    }
}

private struct MediumWidget: View {
    let entry: DayEntry

    var body: some View {
        let day = entry.day ?? WidgetDay(day: entry.date, blocks: [])
        let rows = Array(([day.current(at: entry.date)].compactMap { $0 } + day.upcoming(at: entry.date, limit: 3)).prefix(3))
        let pct = Int(day.progress(at: entry.date) * 100)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                WCaps(text: "\(entry.date.formatted(.dateTime.weekday(.wide))) · \(pct)% of day")
                Spacer()
                Mark()
            }
            if rows.isEmpty {
                Spacer()
                Text("Nothing else today").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(rows) { WRow(block: $0, date: entry.date) }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LargeWidget: View {
    let entry: DayEntry

    var body: some View {
        let day = entry.day ?? WidgetDay(day: entry.date, blocks: [])
        let all = day.todays(entry.date).sorted { $0.start < $1.start }
        // Show a window around "now": up to 2 finished items, then what's current and upcoming.
        let firstLive = all.firstIndex { $0.end > entry.date } ?? all.count
        let startIndex = max(0, firstLive - 2)
        let rows = Array(all.dropFirst(startIndex).prefix(7))
        let color = Color(hex: day.current(at: entry.date)?.colorHex ?? "#30D158")

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    WCaps(text: entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    Text("Today").font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Ring(progress: day.progress(at: entry.date), color: color, width: 4)
                    .frame(width: 32, height: 32)
            }
            if rows.isEmpty {
                Spacer()
                Text("Nothing planned").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(rows) { WRow(block: $0, date: entry.date) }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct EmptyWidget: View {
    let needsAppGroup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Mark()
            Spacer()
            Text(needsAppGroup ? "Widgets need the Apple Developer Program" : "Open Hyperday to load your day")
                .font(.system(size: 13, weight: .semibold))
            Text(needsAppGroup ? "App Groups aren't available on a free Apple ID." : "Your blocks appear here after the app runs once.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
