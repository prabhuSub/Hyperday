import Combine
import SwiftUI
import UIKit

/// Today tab: big title, info row, Add / Go Live, today's timeline.
struct TodayView: View {
    @EnvironmentObject private var store: BlockStore
    @EnvironmentObject private var activity: LiveActivityManager
    @EnvironmentObject private var categories: CategoryStore

    @State private var showingAdd = false
    @State private var showingClose = false
    @State private var showingWords = false
    @State private var showingScan = false
    @State private var editing: Block?
    @State private var now = Date.now
    @State private var calendarGranted = CalendarService.shared.hasAccess

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let snap = activity.snapshot(now: now)

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Card + buttons move as one block: TV-app style, they lift and fade together
                    // as they scroll up under the title. The round + covers adding once they're gone.
                    VStack(alignment: .leading, spacing: 12) {
                        hero(snap: snap)
                        heroButtons   // same left/right edges as the card above
                    }
                    .padding(.horizontal, 20)   // same margin as the title and the cards below
                    .padding(.top, 6)
                    .scrollTransition(.interactive, axis: .vertical) { view, phase in
                        view
                            .opacity(phase.value < 0 ? 1 + phase.value * 0.8 : 1)
                            .offset(y: phase.value < 0 ? phase.value * -40 : 0)
                            .scaleEffect(phase.value < 0 ? 1 + phase.value * 0.04 : 1, anchor: .top)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        if !calendarGranted { calendarBanner }
                        InfoRow(items: todayNumbers(snap))
                        Text("Schedule")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.text)
                        timeline(snap: snap)
                        Text("Plan vs real")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .padding(.top, 8)
                        RealityCard(blocks: snap.all, now: now)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Theme.section)
        }
        .sheet(isPresented: $showingWords) { PlanWithWordsSheet().presentationDetents([.large]) }
        .sheet(isPresented: $showingScan) { ScanSheet().presentationDetents([.large]) }
        .sheet(isPresented: $showingClose) {
            CloseDaySheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showingAdd) {
            QuickAddSheet()
                .presentationDetents([.large])
        }
        .sheet(item: $editing) { block in
            BlockEditorSheet(
                block: block,
                steps: store.steps(for: block.id),
                categoryIDs: store.manualCategoryIDs(for: block.id)
            ) {
                store.delete(id: block.id)
                Task { await activity.refresh() }
            }
            .presentationDetents([.large])
        }
        .onReceive(tick) { now = $0 }
        .task {
            if CalendarService.shared.needsPrompt {
                calendarGranted = await CalendarService.shared.requestAccess()
            }
            await activity.refresh()
        }
    }

    // MARK: Hero

    private func hero(snap: DaySnapshot) -> some View {
        let title: String
        let subtitle: String
        if let c = snap.current, snap.overtime {
            title = c.title
            subtitle = "Over time since \(c.end.shortTime) · tap Done on the Lock Screen"
        } else if let c = snap.current {
            title = c.title
            subtitle = "\(c.source == .calendar ? (c.calendarName ?? "Calendar") : "My plan") · until \(c.end.shortTime)"
        } else if let n = snap.next {
            title = "Free"
            subtitle = "Next: \(n.title) at \(n.start.shortTime)"
        } else {
            title = snap.all.isEmpty ? "Nothing planned" : "Day complete"
            subtitle = snap.all.isEmpty ? "Tap Add block to plan your day" : "Nothing else today"
        }

        let date = now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
        let state = snap.current != nil ? (snap.overtime ? "OVER TIME" : "NOW") : (snap.next != nil ? "FREE" : "TODAY")
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(date) · \(state)")
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(1.4)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 8)
                    heroTimer(snap: snap)
                }
                Text(title)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
            }
            // Tap the live block's name to open it (replaces the old LIVE NOW pill).
            .contentShape(Rectangle())
            .onTapGesture { if let c = snap.current { editing = c } }

            if DayCloseSettings.isClosed(at: now) && !DayCloseSettings.closedDays.contains(HeatData.key(now)) {
                Button("Close the day") { showingClose = true }
                    .buttonStyle(SecondaryButtonStyle(width: 242))
            }

            if !activity.isRunning || activity.lastError != nil {
                Text(activity.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(activity.lastError == nil ? Color.white.opacity(0.7) : Theme.red)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.11, green: 0.15, blue: 0.22), Color(red: 0.24, green: 0.21, blue: 0.31)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    /// Add block · Go/Stop Live · Plan with words · Scan — one row under the card.
    private var heroButtons: some View {
        HStack(spacing: 10) {
            Button("Add block") { showingAdd = true }
                .buttonStyle(PrimaryButtonStyle(width: 124))
            Button(activity.isRunning ? "Stop Live" : "Go Live") {
                Task {
                    if activity.isRunning { await activity.stop() } else { await activity.start() }
                }
            }
            .buttonStyle(SecondaryButtonStyle(width: 124))
            Spacer(minLength: 16)   // left pair hugs the card's left edge, icons hug its right edge
            // #5 Plan with words · #8 Scan to blocks
            iconButton("siri", label: "Plan with words") { showingWords = true }
            iconButton("calendar-scan", label: "Scan to blocks") { showingScan = true }
        }
    }

    /// Live timer pill on the card: green countdown, yellow +over, or countdown to the next block.
    @ViewBuilder
    private func heroTimer(snap: DaySnapshot) -> some View {
        if let c = snap.current, snap.overtime {
            LiveTimerPill(range: c.end...c.end.addingTimeInterval(24 * 3600), down: false, prefix: "+",
                          fill: Color(red: 1, green: 0.84, blue: 0.04), text: .black)
        } else if let c = snap.current, c.end > now {
            LiveTimerPill(range: Date.now...c.end, down: true, fill: DayLiveStyle.doneGreen, text: .white)
        } else if snap.current == nil, let n = snap.next, n.start > now {
            LiveTimerPill(range: Date.now...n.start, down: true, fill: .white.opacity(0.18), text: .white)
        }
    }

    private func rowPill(_ block: Block, snap: DaySnapshot) -> RowPill {
        let steps = store.steps(for: block.id)
        let done = store.overrides[block.id]?.end != nil || (!steps.isEmpty && steps.allSatisfy(\.done))
        if block.id == snap.current?.id { return snap.overtime ? .over(block.end) : .live(block.end) }
        if done { return .done }
        if block.end <= now { return .ended }
        if block.start > now { return .upcoming(block.start) }
        return .live(block.end)
    }

    /// FOCUSED (Work + Deep Work so far) · STEPS · MEETINGS LEFT
    private func todayNumbers(_ snap: DaySnapshot) -> [InfoItem] {
        var focused: TimeInterval = 0
        var stepsDone = 0, stepsTotal = 0, meetingsLeft = 0
        for b in snap.all {
            let cats = categories.categories(for: b).map(\.id)
            let share = 1 / Double(max(cats.count, 1))
            let focusCount = cats.filter { $0 == "work" || $0 == "deepwork" }.count
            focused += max(0, min(b.end, now).timeIntervalSince(b.start)) * share * Double(focusCount)
            if cats.contains("meetings") && b.end > now { meetingsLeft += 1 }
            let st = store.steps(for: b.id)
            stepsDone += st.filter(\.done).count
            stepsTotal += st.count
        }
        return [
            InfoItem(label: "Focused", value: focused.hoursMinutes),
            InfoItem(label: "Steps", value: stepsTotal == 0 ? "—" : "\(stepsDone) / \(stepsTotal)"),
            InfoItem(label: "Meetings left", value: "\(meetingsLeft)"),
        ]
    }

    private func timeline(snap: DaySnapshot) -> some View {
        VStack(spacing: 0) {
            if snap.all.isEmpty {
                Text("Nothing planned. Tap Add block, or load sample data in Settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(snap.all.enumerated()), id: \.element.id) { index, block in
                if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                SwipeRow(leading: leadingActions(block), trailing: trailingActions(block)) {
                    Button {
                        editing = block
                    } label: {
                        BlockRow(block: block, now: now,
                                 color: categories.displayColor(for: block),
                                 steps: store.steps(for: block.id),
                                 icon: categories.category(for: block).iconName,
                                 pill: rowPill(block, snap: snap))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardBox(padding: 0)
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HDIcon(icon, size: 20)
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Swipe right: Start (timer from now). Only blocks you planned; calendar events don't swipe.
    private func leadingActions(_ block: Block) -> [SwipeAction] {
        guard block.source == .plan, block.end > now else { return [] }
        return [SwipeAction(title: "Start", icon: "start", color: DayLiveStyle.planGreen) {
            store.start(blockID: block.id, at: .now)
            Task { await activity.refresh() }
        }]
    }

    /// Swipe left: Tomorrow + Delete. Only blocks you planned; calendar events stay read-only.
    private func trailingActions(_ block: Block) -> [SwipeAction] {
        guard block.source == .plan else { return [] }
        return [
            SwipeAction(title: "Tomorrow", icon: "move", color: Theme.blue) {
                store.move(id: block.id, byDays: 1)
                Task { await activity.refresh() }
            },
            SwipeAction(title: "Delete", icon: "delete", color: Theme.red) {
                store.delete(id: block.id)
                Task { await activity.refresh() }
            },
        ]
    }

    private var calendarBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Caps("Calendar access is off")
            Text("Turn it on so your Tesla and personal events show up.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            Button("Allow access") {
                Task {
                    calendarGranted = await CalendarService.shared.requestAccess()
                    if !calendarGranted, let url = URL(string: UIApplication.openSettingsURLString) {
                        await UIApplication.shared.open(url)
                    }
                    await activity.refresh()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .cardBox()
    }
}


/// White outline button on the dark Today card.
private struct HeroOutlineButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 116, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.45), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
