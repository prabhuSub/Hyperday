import SwiftUI

// v51: dot-matrix + line charts for the Stats tab (Apple look, square dots like a LED board).

private let doneColor = Theme.text           // dots above the line
private let missColor = Color(hex: "#FF9F0A") // dots below the line

extension HistoryStore {
    /// Hours spent in your own planned blocks on a day.
    func planHours(on day: Date) -> Double { Self.planHours(entries(on: day)) }

    nonisolated static func planHours(_ entries: [HistoryEntry]) -> Double {
        entries.filter { $0.source == .plan }.reduce(0) { $0 + $1.hours }
    }

    /// Minutes done as planned (up) and minutes missed or run over (down) on a day.
    func aheadBehind(on day: Date, now: Date = .now) -> (up: Double, down: Double) {
        Self.aheadBehind(entries(on: day), now: now)
    }

    nonisolated static func aheadBehind(_ entries: [HistoryEntry], now: Date) -> (up: Double, down: Double) {
        var up = 0.0, down = 0.0
        for e in entries where e.source == .plan {
            let inPlan = min(e.actualEnd, e.plannedEnd).timeIntervalSince(e.start)
            up += max(0, inPlan) / 60
            down += max(0, e.actualEnd.timeIntervalSince(e.plannedEnd)) / 60          // ran over
            if !e.done && e.plannedEnd < now {
                down += max(0, e.plannedEnd.timeIntervalSince(e.actualEnd)) / 60     // left unfinished
            }
        }
        return (up, down)
    }
}

/// A column of square dots growing up (or down) from its edge.
private struct DotColumn: View {
    var count: Int
    var columns: Int = 1
    var dot: CGFloat
    var gap: CGFloat
    var color: Color
    var down = false
    var body: some View {
        Canvas { ctx, size in
            let step = dot + gap
            for r in 0..<count {
                for c in 0..<columns {
                    let x = CGFloat(c) * step
                    let y = down ? CGFloat(r) * step : size.height - dot - CGFloat(r) * step
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: dot, height: dot), cornerRadius: 1), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(columns) * (dot + gap) - gap)
    }
}

private struct ChartHeader: View {
    var title: String
    var right: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.hd(size: 15, weight: .bold)).foregroundStyle(Theme.text)
            Spacer()
            Text(right).font(.hd(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
        }
    }
}

private func hoursText(_ h: Double) -> String {
    h >= 10 || h == h.rounded() ? "\(Int(h.rounded()))h" : String(format: "%.1fh", h)
}

private func bigNumber(_ value: String, _ note: String?, good: Bool, trailing: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(value).font(.hd(size: 30, weight: .heavy)).foregroundStyle(Theme.text)
        if let note {
            Text(note).font(.hd(size: 13, weight: .bold))
                .foregroundStyle(good ? DayLiveStyle.doneGreen : missColor)
        }
        Spacer(minLength: 0)
        if let trailing { Text(trailing).font(.hd(size: 12)).foregroundStyle(Theme.muted) }
    }
}

// MARK: 1 · Focus this week

struct WeekDotsCard: View {
    @EnvironmentObject private var history: HistoryStore
    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let week = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week) }
        let hours = days.map { $0 > today ? 0 : history.planHours(on: $0) }
        let lastWeek = days.compactMap { cal.date(byAdding: .day, value: -7, to: $0) }
            .filter { cal.date(byAdding: .day, value: 7, to: $0)! <= today }
            .reduce(0) { $0 + history.planHours(on: $1) }
        let total = hours.reduce(0, +)
        let diff = total - lastWeek
        let maxRows = 12
        let rowMin = max(30.0, ((hours.max() ?? 0) * 60 / Double(maxRows) / 30).rounded(.up) * 30)
        let fmt = Date.FormatStyle().month(.abbreviated).day()

        VStack(alignment: .leading, spacing: 6) {
            ChartHeader(title: "Focus this week",
                        right: "\(days[0].formatted(fmt)) – \(days[6].formatted(.dateTime.day()))")
            bigNumber(hoursText(total),
                      lastWeek > 0 ? "\(diff >= 0 ? "+" : "−")\(hoursText(abs(diff))) vs last week" : nil,
                      good: diff >= 0, trailing: "1 row = \(Int(rowMin)) min")
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let isToday = cal.isDate(days[i], inSameDayAs: today)
                    VStack(spacing: 6) {
                        DotColumn(count: min(maxRows, Int((hours[i] * 60 / rowMin).rounded())), columns: 3,
                                  dot: 5, gap: 2,
                                  color: isToday ? Theme.blue : (days[i] < today ? doneColor : Theme.faint))
                            .frame(height: CGFloat(maxRows) * 7)
                        Text(days[i].formatted(.dateTime.weekday(.narrow)))
                            .font(.hd(size: 11.5, weight: .semibold))
                            .foregroundStyle(isToday ? Theme.blue : Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
        }
        .cardBox()
        // v52: Canvas dots are invisible to VoiceOver; read the numbers instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus this week")
        .accessibilityValue(([hoursText(total) + " total"] + (0..<7).filter { days[$0] <= today }.map {
            "\(days[$0].formatted(.dateTime.weekday(.wide))) \(hoursText(hours[$0]))"
        }).joined(separator: ", "))
    }
}

// MARK: 2 · Ahead / behind plan (D+ / D− style)

struct AheadBehindCard: View {
    @EnvironmentObject private var history: HistoryStore
    var body: some View {
        ViewThatFits(in: .horizontal) {
            chart(days: 30)      // wide screens
            chart(days: 14)      // narrow screens fall back to two weeks
        }
    }

    private func chart(days n: Int) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (0..<n).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let vals = days.map { history.aheadBehind(on: $0) }
        let dot: CGFloat = 5, gap: CGFloat = 2
        let upMax = 12, downMax = 6
        let ticks = stride(from: 0, to: n, by: max(1, n / 4)).map { days[$0] } + [days[n - 1]]

        return VStack(alignment: .leading, spacing: 0) {
            ChartHeader(title: "Ahead / behind plan", right: "\(n) days · 1 dot = 15 min")
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<n, id: \.self) { i in
                    VStack(spacing: 0) {
                        DotColumn(count: min(upMax, Int((vals[i].up / 15).rounded())), dot: dot, gap: gap, color: doneColor)
                            .frame(height: CGFloat(upMax) * (dot + gap))
                        Rectangle().fill(Theme.faint).frame(width: dot + 2, height: 1).padding(.vertical, 2.5)
                        DotColumn(count: min(downMax, Int((vals[i].down / 15).rounded())), dot: dot, gap: gap, color: missColor, down: true)
                            .frame(height: CGFloat(downMax) * (dot + gap), alignment: .top)
                    }
                    .frame(minWidth: dot + 3)
                    if i < n - 1 { Spacer(minLength: 2) }
                }
            }
            .padding(.top, 12)
            HStack {
                ForEach(Array(ticks.enumerated()), id: \.offset) { i, d in
                    Text(d.formatted(.dateTime.month(.abbreviated).day()))
                    if i < ticks.count - 1 { Spacer(minLength: 4) }
                }
            }
            .font(.hd(size: 11)).foregroundStyle(Theme.muted).padding(.top, 4)
            HStack(spacing: 14) {
                legend(doneColor, "Done as planned")
                legend(missColor, "Missed or over")
                Spacer(minLength: 0)
            }
            .font(.hd(size: 12)).foregroundStyle(Theme.muted).padding(.top, 8)
        }
        .cardBox()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ahead or behind plan, last \(n) days")
        .accessibilityValue({
            let up = vals.reduce(0) { $0 + $1.up }, down = vals.reduce(0) { $0 + $1.down }
            let worst = zip(days, vals).max { $0.1.down < $1.1.down }
            var t = "\(hoursText(up / 60)) done as planned, \(hoursText(down / 60)) missed or over"
            if let w = worst, w.1.down >= 15 { t += ". Most missed: \(w.0.formatted(.dateTime.weekday(.wide).month().day()))" }
            return t
        }())
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 7, height: 7); Text(t) }
    }
}

// MARK: 3 · Cumulative hours, this month vs last month

struct CumulativeLineCard: View {
    @EnvironmentObject private var history: HistoryStore
    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let monthStart = cal.dateInterval(of: .month, for: today)?.start ?? today
        let lastStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let lastLen = cal.range(of: .day, in: .month, for: lastStart)?.count ?? 30
        let dayIndex = cal.dateComponents([.day], from: monthStart, to: today).day ?? 0

        let running: (Date, Int) -> [Double] = { start, count in
            var sum = 0.0
            return (0..<count).map { k in
                sum += self.history.planHours(on: cal.date(byAdding: .day, value: k, to: start) ?? start)
                return sum
            }
        }
        let cur = running(monthStart, dayIndex + 1)
        let last = running(lastStart, lastLen)
        let nowTotal = cur.last ?? 0
        let lastByNow = last[min(dayIndex, last.count - 1)]
        let diff = nowTotal - lastByNow
        let monthName = monthStart.formatted(.dateTime.month(.wide))
        let lastName = lastStart.formatted(.dateTime.month(.wide))

        VStack(alignment: .leading, spacing: 6) {
            ChartHeader(title: "Focus hours, month to date", right: "Cumulative")
            bigNumber(hoursText(nowTotal),
                      last.last ?? 0 > 0 ? (diff >= 0 ? "ahead of \(lastName)" : "behind \(lastName)") : nil,
                      good: diff >= 0)
            LineChartShape(cur: cur, last: last, span: max(30, lastLen - 1))
                .frame(height: 100)
                .padding(.top, 8)
            HStack(spacing: 14) {
                HStack(spacing: 5) { Capsule().fill(Theme.blue).frame(width: 14, height: 3); Text("\(monthName) · \(hoursText(nowTotal))") }
                HStack(spacing: 5) {
                    Rectangle().fill(.clear).frame(width: 14, height: 2)
                        .overlay(Path { p in p.move(to: .init(x: 0, y: 1)); p.addLine(to: .init(x: 14, y: 1)) }
                            .stroke(missColor, style: StrokeStyle(lineWidth: 2, dash: [3, 3])))
                    Text("\(lastName) · \(hoursText(lastByNow)) by now")
                }
            }
            .font(.hd(size: 12)).foregroundStyle(Theme.muted).padding(.top, 4)
        }
        .cardBox()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus hours, month to date")
        .accessibilityValue("\(monthName) \(hoursText(nowTotal)), \(lastName) had \(hoursText(lastByNow)) by this day")
    }
}

private struct LineChartShape: View {
    var cur: [Double]
    var last: [Double]
    var span: Int
    var body: some View {
        Canvas { ctx, size in
            let top = max((cur + last).max() ?? 1, 1) * 1.05
            func pt(_ k: Int, _ v: Double) -> CGPoint {
                CGPoint(x: size.width * CGFloat(k) / CGFloat(span), y: size.height - size.height * CGFloat(v / top))
            }
            for f in [0.0, 0.5, 1.0] {
                var g = Path(); g.move(to: .init(x: 0, y: size.height * f)); g.addLine(to: .init(x: size.width, y: size.height * f))
                ctx.stroke(g, with: .color(Theme.border), lineWidth: 1)
            }
            func line(_ vals: [Double]) -> Path {
                var p = Path()
                for (k, v) in vals.enumerated() { k == 0 ? p.move(to: pt(k, v)) : p.addLine(to: pt(k, v)) }
                return p
            }
            ctx.stroke(line(last), with: .color(missColor), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            ctx.stroke(line(cur), with: .color(Theme.blue), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            if let v = cur.last {
                let c = pt(cur.count - 1, v)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(Theme.card))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)), with: .color(Theme.blue))
            }
        }
    }
}
