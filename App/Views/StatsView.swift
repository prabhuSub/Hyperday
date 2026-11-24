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
                                .font(.hd(size: 26, weight: .semibold))
                                .contentTransition(.opacity)
                                .foregroundStyle(Theme.text)
                        }
                        PillNav(options: StatsRange.allCases, selection: $range) { $0.rawValue }
                        // v58: JobTrail fleet card with meters and growing bars.
                        JTCard(state: s.streak > 0 ? .glow : .normal, padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    JTStatusDot(status: s.streak > 0 ? .running : .idle, size: 6)
                                    Text(s.subtitle).font(.geist(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer()
                                    JTPill(text: range.rawValue, kind: .busy)
                                }
                                HStack(alignment: .top, spacing: 10) {
                                    JTMeter(key: "Focused", value: hours(s.focusedHours),
                                            fraction: min(1, s.focusedHours / max(1, range.focusGoalHours)), color: HDTone.green)
                                    JTMeter(key: "Steps done", value: "\(s.stepsDone)",
                                            fraction: min(1, Double(s.stepsDone) / 50), color: HDTone.amber)
                                    JTMeter(key: "Streak", value: "\(s.streak)d",
                                            fraction: min(1, Double(s.streak) / 7), color: HDTone.blue)
                                }
                            }
                        }
                        .id(range)   // bars regrow when the range changes
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.clear)

                    VStack(spacing: 12) {
                        WeekDotsCard().jtStagger(1)        // v51 · v58 staggered entry
                        AheadBehindCard().jtStagger(2)     // v51
                        CumulativeLineCard().jtStagger(3)  // v51
                        HeatmapCard().jtStagger(4)
                        GoodDayCard().jtStagger(5)
                        if s.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Caps("No history yet")
                                Text("Stats fill in as you use Hyperday. To preview the look now: Settings › Load sample data.")
                                    .font(.hd(size: 14))
                                    .foregroundStyle(Theme.muted)
                            }
                            .cardBox()
                        }
                        categoryCard(s).jtStagger(6)
                        meetingCard(s).jtStagger(7)
                        blocksCard(s).jtStagger(8)
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
            .background(DotPage())
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
                        ForEach(Array(s.byCategory.enumerated()), id: \.element.id) { i, c in
                            GrowSegment(color: c.color, width: max(6, w * c.hours / total), delay: Double(i) * 0.07)
                        }
                    }
                }
                .frame(height: 12)
            }
            VStack(spacing: 0) {
                ForEach(Array(s.byCategory.enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 10) {
                        Circle().fill(c.color).frame(width: 8, height: 8)
                        Text(c.name).font(.hd(size: 14)).foregroundStyle(Theme.text).lineLimit(1)
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
            JTGrowBar(value: s.meetingHours / total, color: meetingsColor, height: 8)   // v58: grows in
            HStack {
                (Text(hours(s.meetingHours)).bold().foregroundColor(Theme.text) + Text(" meetings"))
                Spacer()
                (Text(hours(s.planHours)).bold().foregroundColor(Theme.text) + Text(" your plan"))
            }
            .font(.hd(size: 13))
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
            Text(value).font(.hdMono(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(label.uppercased()).font(.hdMono(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


extension StatsRange {
    /// v58: what fills the Focused bar (about 4h of focus a day).
    var focusGoalHours: Double { Double(days) * 4 }
}

/// v58: a stacked-bar segment that grows from zero, one after another.
private struct GrowSegment: View {
    let color: Color
    let width: CGFloat
    let delay: Double
    @State private var shown = false
    var body: some View {
        Capsule().fill(color)
            .frame(width: shown ? width : 0)
            .frame(width: width, alignment: .leading)
            .onAppear { withAnimation(HDEase.entry(0.8).delay(0.2 + delay)) { shown = true } }
    }
}
