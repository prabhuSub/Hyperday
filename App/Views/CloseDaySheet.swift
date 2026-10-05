import SwiftUI

/// v9 #1: the 30-second review behind "Day closed · Review".
/// Swipe each unfinished block to Tomorrow or Drop; "Close the day" carries the rest to tomorrow.
struct CloseDaySheet: View {
    @EnvironmentObject private var store: BlockStore
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var notDone: [Block] = []
    @State private var story: String?

    @State private var today = Date.now   // fixed while the sheet is open (across midnight too)

    var body: some View {
        let entries = history.entries(on: today)
        let done = entries.filter(\.done)
        let total = max(LiveActivityManager.shared.allTodayBlocks(now: today).count, entries.count)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Caps("Close the day · \(today.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                        (Text("\(done.count)").foregroundColor(DayLiveStyle.doneGreen) + Text(" of \(total) done"))
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(Theme.text)
                    }

                    if let story {
                        VStack(alignment: .leading, spacing: 6) {
                            Caps("Your day")
                            Text(story)
                                .font(.system(size: 15))
                                .italic()
                                .foregroundStyle(Theme.text)
                            Text("Written on your iPhone by Apple Intelligence from today's blocks and places.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                        .cardBox()
                    }

                    if !notDone.isEmpty {
                        Caps("Not done · mark or move each")
                        VStack(spacing: 0) {
                            ForEach(Array(notDone.enumerated()), id: \.element.id) { index, b in
                                if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                                SwipeRow(leading: [
                                    SwipeAction(title: "Done", icon: "done", color: DayLiveStyle.doneGreen) { markDone(b) },
                                ], trailing: [
                                    SwipeAction(title: "Tomorrow", icon: "move", color: Theme.blue) { move(b) },
                                    SwipeAction(title: "Drop", icon: "close", color: Color(white: 0.56)) { drop(b) },
                                ]) {
                                    row(b)
                                }
                            }
                        }
                        .cardBox(padding: 0)
                        Text("Tap the circle or swipe right if you did it. Swipe left: Tomorrow (same time) or Drop. Anything left here moves to tomorrow when you close the day.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }

                    if !done.isEmpty {
                        Caps("Done")
                        VStack(spacing: 0) {
                            ForEach(Array(done.enumerated()), id: \.element.id) { index, e in
                                if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                                HStack(spacing: 10) {
                                    HDIcon("done", size: 16).foregroundStyle(DayLiveStyle.doneGreen)
                                    Text(e.title).font(.system(size: 14)).foregroundStyle(Theme.muted).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            }
                        }
                        .cardBox(padding: 0)
                    }

                    Button("Close the day", action: closeDay)
                        .buttonStyle(CloseButtonStyle())
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Theme.section)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
        }
        .onAppear { notDone = LiveActivityManager.shared.notDoneToday(now: today) }
        .task { await loadStory() }
    }

    /// #6 Evening story: generated once per day, kept for the rest of it.
    private func loadStory() async {
        let key = "story-" + HeatData.key(today)
        if let saved = UserDefaults.standard.string(forKey: key) { story = saved; return }
        guard AIPlanner.isAvailable else { return }
        let entries = history.entries(on: today)
        let reality = RealityStore.shared.segments(on: today).map {
            "\($0.label) \($0.start.shortTime)–\($0.end.shortTime)"
        }
        let done = entries.filter(\.done).map(\.title)
        let notDone = entries.filter({ !$0.done }).map(\.title)
        if let text = try? await AIPlanner.story(done: done, notDone: notDone, reality: reality) {
            story = text
            UserDefaults.standard.set(text, forKey: key)
        }
    }

    private func row(_ b: Block) -> some View {
        HStack(spacing: 10) {
            // Tap the circle (or swipe right) if you did it but forgot to tap Done: counts as done today.
            Button { markDone(b) } label: {
                Circle().stroke(DayLiveStyle.stepYellow, lineWidth: 1.5).frame(width: 18, height: 18)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(b.title) done")
            RoundedRectangle(cornerRadius: 2).fill(CategoryStore.shared.displayColor(for: b)).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.title).font(.system(size: 15)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(b.start.shortTime) · \(b.duration.hoursMinutes)").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Theme.card)
    }

    private func move(_ b: Block) {
        store.move(id: b.id, byDays: 1)
        notDone.removeAll { $0.id == b.id }
    }

    /// Missed tapping Done: mark it done at its planned end, so it counts for today
    /// (streak, heatmap, "done today") without changing how long it ran.
    private func markDone(_ b: Block) {
        withAnimation(.easeOut(duration: 0.2)) { notDone.removeAll { $0.id == b.id } }
        store.finish(blockID: b.id, at: b.end)
        Task { await LiveActivityManager.shared.refresh() }
    }

    private func drop(_ b: Block) {
        store.delete(id: b.id)
        notDone.removeAll { $0.id == b.id }
    }

    private func closeDay() {
        for b in notDone { store.move(id: b.id, byDays: 1) }
        notDone = []
        DayCloseSettings.closedDays.insert(HeatData.key(today))
        Task { await LiveActivityManager.shared.refresh() }
        dismiss()
    }
}

private struct CloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.text))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Settings › Day Close (v9 #1 + #2).
struct DayCloseSettingsCard: View {
    @State private var close = DayCloseSettings.closeTime(on: .now)
    @State private var show = DayCloseSettings.showOnLockScreen
    @State private var sleep = DayCloseSettings.sleepMinutes
    @State private var routine = DayCloseSettings.routineMinutes
    @State private var commute = DayCloseSettings.commuteMinutes
    @State private var office = DayCloseSettings.officeDays
    @State private var healthAvg = DayCloseSettings.healthSleepMinutes
    @State private var reading = false

    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Day Close", icon: "done", color: Color(hex: "#FF375F"))
            DatePicker("Close my day at", selection: $close, displayedComponents: [.hourAndMinute])
                .font(.system(size: 14))
            Toggle("Show on Lock Screen", isOn: $show).font(.system(size: 14))

            Rectangle().fill(Theme.border).frame(height: 1)
            Caps("Tomorrow pre-flight")
            Stepper(value: $sleep, in: 300...600, step: 15) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sleep target  \(TimeInterval(sleep * 60).hoursMinutes)").font(.system(size: 14))
                    Text(healthAvg.map { "Your 2-week average in Health: \(TimeInterval($0 * 60).hoursMinutes)" }
                         ?? "Tap Use Health to read your average sleep")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            Button(reading ? "Reading Health…" : "Use Health average") {
                reading = true
                Task {
                    await HealthSleep.refreshAverage()
                    healthAvg = DayCloseSettings.healthSleepMinutes
                    if let h = healthAvg { sleep = h }
                    reading = false
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .disabled(reading)
            Stepper(value: $routine, in: 0...120, step: 5) {
                Text("Morning routine  \(routine) min").font(.system(size: 14))
            }
            Stepper(value: $commute, in: 0...120, step: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Commute  \(commute) min").font(.system(size: 14))
                    Text("Learned automatically once Location arrives (roadmap #3)")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Office days").font(.system(size: 14))
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        let on = office.contains(day)
                        Button {
                            if on { office.remove(day) } else { office.insert(day) }
                        } label: {
                            Text(weekdays[day - 1])
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(on ? Theme.bg : Theme.text)
                                .background(Circle().fill(on ? Theme.text : Theme.card))
                                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Leave-by shows only on office days.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .cardBox()
        .onChange(of: close) { _, v in
            let c = Calendar.current.dateComponents([.hour, .minute], from: v)
            DayCloseSettings.closeMinutes = (c.hour ?? 19) * 60 + (c.minute ?? 0)
            refresh()
        }
        .onChange(of: show) { _, v in DayCloseSettings.showOnLockScreen = v; refresh() }
        .onChange(of: sleep) { _, v in DayCloseSettings.sleepMinutes = v; refresh() }
        .onChange(of: routine) { _, v in DayCloseSettings.routineMinutes = v; refresh() }
        .onChange(of: commute) { _, v in DayCloseSettings.commuteMinutes = v; refresh() }
        .onChange(of: office) { _, v in DayCloseSettings.officeDays = v; refresh() }
    }

    private func refresh() { Task { await LiveActivityManager.shared.refresh() } }
}
