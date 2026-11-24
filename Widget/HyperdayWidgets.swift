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
        .environment(\.colorScheme, .dark)   // v55: instrument plate in both modes
        .containerBackground(for: .widget) { InstrumentBackground() }
    }
}

// MARK: - Pieces (v58: JobTrail widget kit)

private struct WCaps: View {
    let text: String
    var color: Color = HDTone.faintDark
    var body: some View {
        Text(text.uppercased())
            .font(.mono(9.5, .semibold))
            .kerning(0.8)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private func wStatus(_ b: WidgetBlock, _ date: Date) -> HDStatus {
    if b.start <= date && date < b.end { return .running }
    if b.end <= date { return .done }
    return .waiting
}

/// Amber border + inner glow when something is running (widgets can't animate a breathing glow;
/// the live countdown and the timer bar are the moving parts).
private struct WActiveFrame: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        content.overlay {
            if active {
                ContainerRelativeShape()
                    .strokeBorder(HDTone.amber.opacity(0.55), lineWidth: 1)
                    .shadow(color: HDTone.amber.opacity(0.35), radius: 6)
                    .padding(-12)   // reach the widget's edge from inside the content margins
            }
        }
    }
}

/// Live bar that moves by itself (iOS animates timer-driven progress views in widgets).
private struct WTimerBar: View {
    let start: Date
    let end: Date
    var color: Color = HDTone.green
    var body: some View {
        ProgressView(timerInterval: start...max(end, start.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(color)
            .scaleEffect(x: 1, y: 0.8, anchor: .center)
    }
}

private struct WRow: View {
    let block: WidgetBlock
    let date: Date
    var compact = false

    var body: some View {
        let st = wStatus(block, date)
        HStack(spacing: 8) {
            JTStatusDot(status: st, size: 6, animated: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.geist(size: compact ? 12 : 13, weight: st == .running ? .semibold : .medium))
                    .foregroundStyle(st == .done ? HDTone.dim : HDTone.textHi)
                    .lineLimit(1)
                if !compact {
                    Text(detail).font(.mono(9.5)).foregroundStyle(HDTone.faintDark).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if st == .running {
                Text(timerInterval: date...max(block.end, date), countsDown: true)
                    .font(.mono(11, .semibold)).foregroundStyle(HDTone.green)
                    .monospacedDigit().multilineTextAlignment(.trailing).frame(maxWidth: 54, alignment: .trailing)
            } else {
                Text(st == .done ? "DONE" : block.start.formatted(date: .omitted, time: .shortened))
                    .font(.mono(9.5, .semibold)).kerning(0.5)
                    .foregroundStyle(st == .done ? HDTone.blue : HDTone.amber)
            }
        }
        .padding(.vertical, compact ? 2 : 3)
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
        let st: HDStatus = current != nil ? .running : (next != nil ? .waiting : .done)

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                JTStatusDot(status: st, size: 6, animated: false)
                WCaps(text: current != nil ? "Now" : (next != nil ? "Next" : "Today"), color: st.color)
                Spacer()
                Mark()
            }
            Text(current?.title ?? next?.title ?? "Nothing planned")
                .font(.geist(size: 16, weight: .semibold))
                .foregroundStyle(HDTone.textHi)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let c = current {
                Text(timerInterval: entry.date...max(c.end, entry.date), countsDown: true)
                    .font(.mono(22, .semibold)).foregroundStyle(HDTone.green)
                    .monospacedDigit().lineLimit(1)
                WTimerBar(start: c.start, end: c.end)
                WCaps(text: c.stepsTotal > 0 ? "left · \(c.stepsDone)/\(c.stepsTotal) steps" : "left")
            } else if let n = next {
                Text(timerInterval: entry.date...max(n.start, entry.date), countsDown: true)
                    .font(.mono(22, .semibold)).foregroundStyle(HDTone.amber)
                    .monospacedDigit().lineLimit(1)
                WCaps(text: "starts \(n.start.formatted(date: .omitted, time: .shortened))")
            } else {
                JTPill(text: "Day complete", kind: .done)
            }
        }
        .modifier(WActiveFrame(active: current != nil))
    }
}

private struct MediumWidget: View {
    let entry: DayEntry

    var body: some View {
        let day = entry.day ?? WidgetDay(day: entry.date, blocks: [])
        let current = day.current(at: entry.date)
        let rows = Array(([current].compactMap { $0 } + day.upcoming(at: entry.date, limit: 3)).prefix(3))
        let pct = Int(day.progress(at: entry.date) * 100)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Mark()
                Text("Today").font(.geist(size: 13, weight: .semibold)).foregroundStyle(HDTone.textHi)
                JTPill(text: current != nil ? "running" : (rows.isEmpty ? "done" : "waiting"),
                       kind: current != nil ? .running : (rows.isEmpty ? .done : .busy))
                Spacer()
                WCaps(text: "\(pct)% of day")
            }
            if let c = current { WTimerBar(start: c.start, end: c.end).padding(.vertical, 2) }
            Rectangle().fill(HDTone.hover).frame(height: 1)
            if rows.isEmpty {
                Spacer()
                Text("NOTHING ELSE TODAY").font(.mono(11, .medium)).kerning(0.8).foregroundStyle(HDTone.faintDark)
                Spacer()
            } else {
                ForEach(rows) { WRow(block: $0, date: entry.date, compact: true) }
                Spacer(minLength: 0)
            }
        }
        .modifier(WActiveFrame(active: current != nil))
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
        let current = day.current(at: entry.date)
        let done = all.filter { $0.end <= entry.date }.count

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                JTStatusDot(status: current != nil ? .running : .waiting, size: 7, animated: false)
                VStack(alignment: .leading, spacing: 0) {
                    WCaps(text: entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    Text("Today").font(.geist(size: 20, weight: .semibold)).foregroundStyle(HDTone.textHi)
                }
                Spacer()
                Mark()
            }
            // JobTrail meters
            HStack(spacing: 10) {
                meter("Done", "\(done)/\(all.count)", all.isEmpty ? 0 : Double(done) / Double(all.count), HDTone.blue)
                meter("Day", "\(Int(day.progress(at: entry.date) * 100))%", day.progress(at: entry.date), HDTone.amber)
                if let c = current {
                    VStack(alignment: .leading, spacing: 2) {
                        WCaps(text: "Left")
                        Text(timerInterval: entry.date...max(c.end, entry.date), countsDown: true)
                            .font(.geist(size: 16, weight: .medium)).monospacedDigit().foregroundStyle(HDTone.green)
                        WTimerBar(start: c.start, end: c.end)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Rectangle().fill(HDTone.hover).frame(height: 1)
            if rows.isEmpty {
                Spacer()
                Text("NOTHING PLANNED").font(.mono(11, .medium)).kerning(0.8).foregroundStyle(HDTone.faintDark)
                Spacer()
            } else {
                ForEach(rows) { WRow(block: $0, date: entry.date) }
                Spacer(minLength: 0)
            }
        }
        .modifier(WActiveFrame(active: current != nil))
    }

    private func meter(_ k: String, _ v: String, _ f: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WCaps(text: k)
            Text(v).font(.geist(size: 16, weight: .medium)).monospacedDigit().foregroundStyle(HDTone.textHi)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(HDTone.hover)
                    Capsule().fill(c).frame(width: max(4, g.size.width * min(max(f, 0), 1)))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyWidget: View {
    let needsAppGroup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Mark()
            Spacer()
            Text(needsAppGroup ? "Widgets need the Apple Developer Program" : "Open Hyperday to load your day")
                .font(.geist(size: 13, weight: .semibold))
            Text(needsAppGroup ? "App Groups aren't available on a free Apple ID." : "Your blocks appear here after the app runs once.")
                .font(.geist(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
