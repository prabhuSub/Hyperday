import SwiftUI

/// Stats tab: three big numbers, Week/Month/Year, hours by category, meeting load, blocks.
struct StatsView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var categories: CategoryStore
    @State private var range: StatsRange = .week
    @State private var showRecap = false

    var body: some View {
        let s = history.summary(range)

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Caps(s.subtitle)
                            Text(s.title)
                                .font(.system(size: 26, weight: .heavy))   // v27: modest
                                .foregroundStyle(Theme.text)
                        }
                        PillNav(options: StatsRange.allCases, selection: $range) { $0.rawValue }
                        InfoRow(items: [
                            InfoItem(label: "Focused", value: hours(s.focusedHours), color: DayLiveStyle.doneGreen),
                            InfoItem(label: "Steps done", value: "\(s.stepsDone)", color: Theme.blue),
                            InfoItem(label: "Streak", value: "\(s.streak) day\(s.streak == 1 ? "" : "s")", color: Color(hex: "#FF9F0A")),
                        ])
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bg)

                    VStack(spacing: 12) {
                        HeatmapCard()
                        GoodDayCard()
                        if s.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Caps("No history yet")
                                Text("Stats fill in as you use Hyperday. To preview the look now: Settings › Load sample data.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.muted)
                            }
                            .cardBox()
                        }
                        categoryCard(s)
                        meetingCard(s)
                        blocksCard(s)
                        if !s.isEmpty {
                            Button("See weekly recap") { showRecap = true }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
            .background(Theme.section)
        }
        .task { await LiveActivityManager.shared.refresh() }
        .fullScreenCover(isPresented: $showRecap) { WeeklyRecapView() }   // records today before showing numbers
    }

    private func hours(_ h: Double) -> String {
        h >= 10 ? "\(Int(h.rounded()))h" : (h * 3600).hoursMinutes
    }

    /// v27: one stacked bar of where the time went, then a legend with color dots and big hour numbers.
    private func categoryCard(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Caps("Where the time went")
            if s.byCategory.isEmpty {
                Text("—").foregroundStyle(Theme.faint)
            } else {
                GeometryReader { geo in
                    let total = max(s.byCategory.map(\.hours).reduce(0, +), 0.01)
                    let gap: CGFloat = 3
                    let w = geo.size.width - gap * CGFloat(max(s.byCategory.count - 1, 0))
                    HStack(spacing: gap) {
                        ForEach(s.byCategory) { c in
                            Capsule().fill(c.color).frame(width: max(6, w * c.hours / total))
                        }
                    }
                }
                .frame(height: 12)
            }
            VStack(spacing: 0) {
                ForEach(Array(s.byCategory.enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 10) {
                        Circle().fill(c.color).frame(width: 10, height: 10)
                        Text(c.name).font(.system(size: 14)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        bigSmallText(hours(c.hours), size: 15).foregroundStyle(Theme.text)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) } }
                }
            }
        }
        .cardBox()
    }

    private func meetingCard(_ s: StatsSummary) -> some View {
        let total = max(s.meetingHours + s.planHours, 0.01)
        let meetingsColor = categories.category(id: "meetings")?.color ?? Theme.blue
        return VStack(alignment: .leading, spacing: 10) {
            Caps("Meeting load")
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(meetingsColor).frame(width: geo.size.width * s.meetingHours / total)
                    Rectangle().fill(Theme.section)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())   // v27
            HStack {
                (Text(hours(s.meetingHours)).bold().foregroundColor(Theme.text) + Text(" meetings"))
                Spacer()
                (Text(hours(s.planHours)).bold().foregroundColor(Theme.text) + Text(" your plan"))
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
        }
        .cardBox()
    }

    private func blocksCard(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Caps("Blocks")
            HStack(alignment: .top, spacing: 12) {
                stat("\(s.blocksDone)", "Done")
                stat("\(s.endedEarly)", "Ended early")
                stat("\(s.missed)", "Missed")
            }
        }
        .cardBox()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
