import CoreLocation
import SwiftUI

/// #3 on Today: planned blocks (left) vs what actually happened (right), 6 AM – 10 PM.
struct RealityCard: View {
    let blocks: [Block]
    let now: Date
    @EnvironmentObject private var categories: CategoryStore
    @ObservedObject private var reality = RealityStore.shared

    private let hourHeight: CGFloat = 56   // v42: taller so 15–30 min blocks are readable; time stays proportional
    private let inset: CGFloat = 10        // room above the first hour line, so the header never overlaps

    /// One box on either side of the card.
    private struct Item: Identifiable {
        let id: String
        let title: String
        let color: Color
        let start: Date
        let end: Date
        var column = 0
        var columns = 1
    }

    /// Overlapping boxes sit side by side (like Apple Calendar) instead of on top of each other.
    private static func layout(_ input: [Item]) -> [Item] {
        var items = input.filter { $0.end > $0.start }.sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }
        var i = 0
        while i < items.count {
            // A cluster = a run of items that overlap each other directly or through a chain.
            var j = i, clusterEnd = items[i].end
            var colEnds: [Date] = []
            while j < items.count && (j == i || items[j].start < clusterEnd) {
                if let c = colEnds.firstIndex(where: { $0 <= items[j].start }) {
                    items[j].column = c; colEnds[c] = items[j].end
                } else {
                    items[j].column = colEnds.count; colEnds.append(items[j].end)
                }
                clusterEnd = max(clusterEnd, items[j].end)
                j += 1
            }
            for k in i..<j { items[k].columns = colEnds.count }
            i = j
        }
        return items
    }

    var body: some View {
        let segs = reality.segments(on: now)
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)

        let planned = Self.layout(blocks.map {
            Item(id: $0.id, title: $0.title, color: categories.displayColor(for: $0), start: $0.start, end: $0.end)
        })
        // What happened = places, drives and workouts, plus every block you actually did (Done, or all steps),
        // at the time it really ran.
        let did = HistoryStore.shared.entries(on: now).filter(\.done).map {
            Item(id: "did-" + $0.id, title: "✓ " + $0.title,
                 color: categories.category(id: $0.categoryID)?.color ?? DayLiveStyle.doneGreen,
                 start: $0.start, end: max($0.actualEnd, $0.start.addingTimeInterval(15 * 60)))
        }
        let happened = Self.layout(segs.map {
            Item(id: $0.id, title: $0.label, color: color($0.kind), start: $0.start, end: $0.end)
        } + did)

        let all = planned + happened
        let firstHour = min(7, all.map { cal.component(.hour, from: $0.start) }.min() ?? 7)
        let lastHour = max(21, all.map { cal.component(.hour, from: $0.end) + 1 }.max() ?? 21)
        let top = dayStart.addingTimeInterval(TimeInterval(firstHour * 3600))
        let y: (Date) -> CGFloat = { inset + CGFloat($0.timeIntervalSince(top) / 3600) * hourHeight }
        let height = inset + CGFloat(lastHour - firstHour) * hourHeight + 6

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Caps("Planned")
                Spacer()
                Caps("What happened")
                    .frame(width: 130, alignment: .leading)
            }
            .padding(.leading, 30)
            GeometryReader { geo in
                let laneW = (geo.size.width - 30 - 8) / 2
                ZStack(alignment: .topLeading) {
                    ForEach(firstHour...lastHour, id: \.self) { h in
                        let yy = inset + CGFloat(h - firstHour) * hourHeight
                        Rectangle().fill(Theme.border).frame(height: 1).offset(y: yy)
                        Text(h % 12 == 0 ? "12\(h < 12 ? "a" : "p")" : "\(h % 12)\(h < 12 ? "a" : "p")")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.faint)
                            .offset(y: yy - 6)
                    }
                    ForEach(planned) { it in
                        let w = laneW / CGFloat(it.columns)
                        lane(it.title, color: it.color, from: y(it.start), to: y(it.end))
                            .frame(width: w - (it.columns > 1 ? 2 : 0))
                            .offset(x: 30 + w * CGFloat(it.column))
                    }
                    ForEach(happened) { it in
                        let w = laneW / CGFloat(it.columns)
                        lane(it.title, color: it.color, from: y(it.start), to: y(it.end))
                            .frame(width: w - (it.columns > 1 ? 2 : 0))
                            .offset(x: 30 + laneW + 8 + w * CGFloat(it.column))
                    }
                    if now > top && y(now) < height {
                        Rectangle().fill(Theme.red).frame(height: 2).padding(.leading, 26).offset(y: y(now))  // stays inside the card
                    }
                }
            }
            .frame(height: height)
            if happened.isEmpty {
                Text("Blocks you mark Done show up on the right at the time they ran. Set Home and Office in Settings › Reality line to add places and drives.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
        .cardBox(padding: 12)
    }

    private func color(_ k: RealitySegment.Kind) -> Color {
        switch k {
        case .drive: return DayLiveStyle.calendarBlue
        case .place: return Color(white: 0.56)
        case .workout: return DayLiveStyle.doneGreen
        }
    }

    private func lane(_ title: String, color: Color, from: CGFloat, to: CGFloat) -> some View {
        let h = max(16, to - from - 2)
        return Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(h > 34 ? 2 : 1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: h, alignment: .topLeading)
            .background(color.opacity(0.18))
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(y: from + 1)
    }
}

/// Settings › Reality line: places, the car automation, Health workouts.
struct RealitySettingsCard: View {
    @ObservedObject private var reality = RealityStore.shared
    @State private var busy: String?
    @AppStorage("realityTickWorkouts") private var tickWorkouts = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Reality line", icon: "travel", color: Color(hex: "#30B0C7"))
            placeRow("home", "Home", "Used to see when you leave")
            placeRow("office", "Office",
                     DayCloseSettings.learnedCommuteMinutes.map { "Arrivals learn your commute: \($0) min avg" }
                        ?? "Arrivals learn your commute")
            placeRow("gym", "Gym", "Optional")

            Rectangle().fill(Theme.border).frame(height: 1)
            Caps("Your car")
            Text("iPhone doesn't let apps watch Bluetooth in the background. Add two Shortcuts automations once:")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Shortcuts › Automation › New › Bluetooth (or CarPlay)")
                Text("2. Pick your car › Is Connected › Run Immediately")
                Text("3. Action: Hyperday › I'm driving")
                Text("4. Same for Is Disconnected › Hyperday › Arrived")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text)
            Button("Open Shortcuts") {
                if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
            }
            .buttonStyle(PrimaryButtonStyle())

            Rectangle().fill(Theme.border).frame(height: 1)
            Toggle("Workouts tick Fitness blocks", isOn: $tickWorkouts).font(.system(size: 14))
            Text("Reads workouts from Health. Everything stays on your iPhone.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .cardBox()
    }

    private func placeRow(_ id: String, _ name: String, _ sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 14)).foregroundStyle(Theme.text)
                Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button(busy == id ? "Locating…" : (reality.place(id) != nil ? "Saved ✓ · Reset" : "Set to here")) {
                busy = id
                LocationService.shared.currentLocation { loc in
                    Task { @MainActor in
                        if let loc { RealityStore.shared.setPlace(id, name: name, at: loc) }
                        busy = nil
                    }
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .disabled(busy != nil)
        }
    }
}
