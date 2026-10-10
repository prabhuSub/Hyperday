import AppIntents
import SwiftUI
import WidgetKit

// v47 dock-style widgets (CoolDock look, Prabhu approved): a black tray, slightly lighter rounded tiles,
// big light numbers, thin ring gauges, solid icons with no background.

private let tray = Color(red: 0.06, green: 0.063, blue: 0.07)
private let tileFill = Color(red: 0.12, green: 0.125, blue: 0.14)
private let ink = Color(white: 0.95)
private let muted = Color(white: 0.55)
private let green = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
private let cyan = Color(hex: "#64D2FF")

private struct Tile<C: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: () -> C
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(tileFill))
    }
}

private struct Ring<C: View>: View {
    let value: Double
    let color: Color
    var line: CGFloat = 4.5
    @ViewBuilder var center: () -> C
    var body: some View {
        ZStack {
            Circle().stroke(Color(white: 0.22), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .padding(line / 2)
    }
}

private func t(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

// MARK: Medium · Now strip

struct DockNowView: View {
    let entry: DayEntry
    var body: some View {
        let now = entry.date
        let day = entry.day
        let cur = day?.current(at: now)
        let next = day?.upcoming(at: now, limit: 1).first
        HStack(spacing: 6) {
            Tile {
                VStack(alignment: .leading, spacing: 3) {
                    if let cur {
                        Text(timerInterval: now...max(now, cur.end), countsDown: true)
                            .font(.system(size: 24, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(cur.title) left").font(.system(size: 10.5)).foregroundStyle(muted).lineLimit(1)
                    } else if let next {
                        Text(timerInterval: now...max(now, next.start), countsDown: true)
                            .font(.system(size: 24, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("free").font(.system(size: 10.5)).foregroundStyle(muted)
                    } else {
                        Text("Done").font(.system(size: 24, weight: .semibold))
                        Text("for today").font(.system(size: 10.5)).foregroundStyle(muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Tile {
                HStack(spacing: 8) {
                    if let next {
                        HDIcon(next.icon ?? "event", size: 22).foregroundStyle(Color(hex: next.colorHex))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(t(next.start)).font(.system(size: 10.5)).foregroundStyle(muted)
                        }
                    } else {
                        HDIcon("done", size: 20).foregroundStyle(green)
                        Text("Nothing next").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            Tile(padding: 9) {
                let p = day?.progress(at: now) ?? 0
                Ring(value: p, color: green) {
                    Text("\(Int((p * 100).rounded()))").font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(width: 72)
        }
        .foregroundStyle(ink)
        .padding(8)   // the black tray shows around the tiles
        .widgetURL(URL(string: "hyperday://today"))
    }
}

// MARK: Medium · Day strip

struct DockDayView: View {
    let entry: DayEntry

    /// Active minutes in each hour so far today (blocks merged), the last ≤10 hours.
    private func hours(_ blocks: [WidgetBlock], now: Date) -> [Double] {
        let cal = Calendar.current
        guard let first = blocks.map(\.start).min() else { return [] }
        let startHour = cal.dateInterval(of: .hour, for: max(first, now.addingTimeInterval(-9 * 3600)))?.start ?? first
        var out: [Double] = []
        var h = startHour
        while h <= now && out.count < 10 {
            let end = min(h.addingTimeInterval(3600), now)
            var mins = 0.0
            var covered: [(Date, Date)] = []
            for b in blocks.sorted(by: { $0.start < $1.start }) {
                let s = max(b.start, h), e = min(b.end, end)
                guard e > s else { continue }
                if let last = covered.last, s < last.1 { covered[covered.count - 1].1 = max(last.1, e) } else { covered.append((s, e)) }
            }
            for c in covered { mins += c.1.timeIntervalSince(c.0) / 60 }
            out.append(mins)
            h = h.addingTimeInterval(3600)
        }
        return out
    }

    var body: some View {
        let now = entry.date
        let blocks = entry.day?.todays(now) ?? []
        let done = blocks.filter { $0.done == true || $0.end <= now }.count
        let bars = hours(blocks, now: now)
        let active = bars.reduce(0, +)
        let car = CarShared.load()
        HStack(spacing: 6) {
            Tile {
                HStack(spacing: 8) {
                    HDIcon("done", size: 20).foregroundStyle(green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(done)/\(blocks.count)").font(.system(size: 20, weight: .semibold)).monospacedDigit()
                        Text("blocks done").font(.system(size: 10.5)).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                }
            }
            Tile {
                VStack(spacing: 5) {
                    HStack {
                        Text("Focus").foregroundStyle(muted)
                        Spacer()
                        Text("\(Int(active) / 60)h \(Int(active) % 60)m")
                    }
                    .font(.system(size: 10.5))
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(bars.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(bars[i] >= 15 ? green : Color(white: 0.24))
                                .frame(height: max(6, CGFloat(bars[i] / 60) * 28))
                        }
                    }
                    .frame(height: 28, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity)
            Tile(padding: 9) {
                Ring(value: Double(car?.battery ?? 0) / 100, color: car?.charging == true ? green : cyan) {
                    if let car {
                        VStack(spacing: 0) {
                            HDIcon("bolt", size: 13)
                            Text("\(car.battery)").font(.system(size: 12, weight: .semibold))
                        }
                    } else {
                        HDIcon("car", size: 22)
                    }
                }
            }
            .frame(width: 72)
        }
        .foregroundStyle(ink)
        .padding(8)   // the black tray shows around the tiles
    }
}

// MARK: Small · Now with Pause / Done

struct DockSmallNowView: View {
    let entry: DayEntry
    var body: some View {
        let now = entry.date
        let cur = entry.day?.current(at: now)
        let next = entry.day?.upcoming(at: now, limit: 1).first
        Tile(padding: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HDIcon((cur ?? next)?.icon ?? "free", size: 22)
                        .foregroundStyle((cur ?? next).map { Color(hex: $0.colorHex) } ?? green)
                    Spacer()
                    if let cur { Text("ends \(t(cur.end))").font(.system(size: 11)).foregroundStyle(muted) }
                }
                Spacer(minLength: 2)
                if let b = cur ?? next {
                    Text(timerInterval: now...max(now, cur?.end ?? b.start), countsDown: true)
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(cur == nil ? "until \(b.title)" : b.title).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
                } else {
                    Text("Done").font(.system(size: 30, weight: .semibold))
                    Text("for today").font(.system(size: 12)).foregroundStyle(muted)
                }
                Spacer(minLength: 6)
                if let cur, cur.done != true {
                    HStack(spacing: 6) {
                        if cur.isPlan == true {
                            Button(intent: PauseBlockIntent(blockID: cur.id, pause: cur.paused != true)) {
                                Image(systemName: cur.paused == true ? "play.fill" : "pause.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity).frame(height: 30)
                                    .background(Capsule().fill(Color(white: 0.2)))
                            }
                            .buttonStyle(.plain)
                        }
                        Button(intent: BlockActionIntent(blockID: cur.id, action: .done)) {
                            HDIcon("done", size: 15).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).frame(height: 30)
                                .background(Capsule().fill(green))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(ink)
        .padding(8)   // the black tray shows around the tiles
    }
}

// MARK: Small · 4 tiles

struct DockSmallTilesView: View {
    let entry: DayEntry
    var body: some View {
        let now = entry.date
        let blocks = entry.day?.todays(now) ?? []
        let left = blocks.filter { $0.end > now && $0.done != true }.count
        let p = entry.day?.progress(at: now) ?? 0
        let car = CarShared.load()
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Tile(padding: 6) {
                    VStack(spacing: 3) {
                        Ring(value: p, color: green, line: 4) {
                            Text("\(Int((p * 100).rounded()))").font(.system(size: 11, weight: .semibold))
                        }
                        Text("Day").font(.system(size: 9.5)).foregroundStyle(muted)
                    }
                }
                Tile(padding: 6) {
                    VStack(spacing: 4) {
                        HDIcon(car?.locked == false ? "lock" : "lock", size: 20)
                            .foregroundStyle(car?.locked == false ? Color(hex: "#FF453A") : ink)
                        Text(car?.locked == false ? "Unlocked" : (car == nil ? "Car" : "Locked"))
                            .font(.system(size: 9.5)).foregroundStyle(muted)
                    }
                }
            }
            GridRow {
                Tile(padding: 6) {
                    VStack(spacing: 2) {
                        Text(car.map { "\($0.battery)%" } ?? "–").font(.system(size: 18, weight: .semibold))
                        Text("Car").font(.system(size: 9.5)).foregroundStyle(muted)
                    }
                }
                Tile(padding: 6) {
                    VStack(spacing: 2) {
                        Text("\(left)").font(.system(size: 18, weight: .semibold))
                        Text("Left").font(.system(size: 9.5)).foregroundStyle(muted)
                    }
                }
            }
        }
        .foregroundStyle(ink)
        .padding(8)   // the black tray shows around the tiles
    }
}

// MARK: Widgets

struct HyperdayDockNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HyperdayDockNow", provider: DayProvider()) {
            DockNowView(entry: $0).containerBackground(for: .widget) { tray }
        }
        .configurationDisplayName("Now strip").description("Time left, what's next and how much of the day is done.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct HyperdayDockDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HyperdayDockDay", provider: DayProvider()) {
            DockDayView(entry: $0).containerBackground(for: .widget) { tray }
        }
        .configurationDisplayName("Day strip").description("Blocks done, focus by hour and your car's battery.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct HyperdayDockSmallNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HyperdayDockSmallNow", provider: DayProvider()) {
            DockSmallNowView(entry: $0).containerBackground(for: .widget) { tray }
        }
        .configurationDisplayName("Now · Pause / Done").description("Countdown with Pause and Done right on the widget.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct HyperdayDockTilesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HyperdayDockTiles", provider: DayProvider()) {
            DockSmallTilesView(entry: $0).containerBackground(for: .widget) { tray }
        }
        .configurationDisplayName("4 tiles").description("Day ring, car lock, car battery and blocks left.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
