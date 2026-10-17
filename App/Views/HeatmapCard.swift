import SwiftUI

/// "Open in Calendar" from the heatmap: the Calendar tab opens on this day instead of today.
enum CalendarJump {
    static var pending: Date?
    static let notification = Notification.Name("HyperdayOpenCalendarDay")

    static func open(_ day: Date) {
        pending = Calendar.current.startOfDay(for: day)
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

/// First card on Stats: 12 months of blocks done, GitHub-style. Opens scrolled to this week.
struct HeatmapCard: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var picked: Date?

    var body: some View {
        let data = history.heat
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Caps("Blocks done · last 12 months")
                Spacer()
                Text("\(data.total()) total")
                    .font(.hd(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HeatGrid(data: data, weeks: 53, cell: 12, gap: 3, selected: picked) { picked = $0 }
                        .padding(.vertical, 2)
                        .id("grid")
                }
                .onAppear { proxy.scrollTo("grid", anchor: .trailing) }
            }
            HStack {
                let streak = data.streak()
                (Text("\(streak)-day").bold().foregroundColor(Theme.text) + Text(" streak · best \(data.best())"))
                    .font(.hd(size: 12))
                    .foregroundStyle(Theme.muted)
                Spacer()
                HeatLegend()
            }
        }
        .cardBox(padding: 14)
        .sheet(item: Binding(get: { picked.map(PickedDay.init) }, set: { picked = $0?.day })) { p in
            HeatDaySheet(day: p.day)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct PickedDay: Identifiable {
    let day: Date
    var id: Date { day }
}

/// Tap a square: that day's blocks, what you finished, and a way into the Calendar.
struct HeatDaySheet: View {
    let day: Date
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = history.entries(on: day)
        let done = entries.filter(\.done).count
        let focused = entries.reduce(0) { $0 + $1.hours(in: ["work", "deepwork"]) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(HeatStyle.green.color(HeatStyle.level(done), dark: false))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.hd(size: 20, weight: .bold))
                    Text(entries.isEmpty ? "Nothing recorded this day"
                         : "\(done) of \(entries.count) blocks done · \((focused * 3600).hoursMinutes) focused")
                        .font(.hd(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries) { e in
                        HStack(spacing: 10) {
                            HDIcon(e.done ? "step-done" : "step-open", size: 20)
                                .foregroundStyle(e.done ? DayLiveStyle.doneGreen : Theme.faint)
                            Text(e.title)
                                .font(.hd(size: 14))
                                .foregroundStyle(e.done ? Theme.text : Theme.muted)
                                .lineLimit(1)
                            Spacer()
                            Text(e.start.shortTime)
                                .font(.hd(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
                }
            }
            Button("Open in Calendar") {
                dismiss()
                CalendarJump.open(day)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(20)
        .background(Theme.bg)
    }
}
