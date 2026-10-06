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
    @ObservedObject private var photos = PhotoStore.shared   // v36: rows show photo thumbnails
    @State private var extending: Block?   // v32: long-press the running plan block
    @State private var now = Date.now
    @State private var calendarGranted = CalendarService.shared.hasAccess
    @Environment(\.scenePhase) private var scenePhase

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
        .sheet(isPresented: $showingScan) { PhotoTaskSheet().presentationDetents([.large]) }   // v36
        .sheet(isPresented: $showingClose) {
            CloseDaySheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showingAdd) {
            QuickAddSheet()
                .presentationDetents([.large])
        }
        .sheet(item: $extending) { block in
            ExtendSheet(block: block) { add in
                store.extend(id: block.id, by: add)
                Task { await activity.refresh() }
            }
            .presentationDetents([.height(300)])
        }
        .sheet(item: $editing) { block in
            BlockEditorSheet(
                block: store.planBlocks.first { $0.id == block.id } ?? block,   // raw plan, not timer-adjusted
                steps: store.steps(for: block.id),
                categoryIDs: store.manualCategoryIDs(for: block.id)
            ) {
                store.delete(id: block.id)
                Task { await activity.refresh() }
            }
            .presentationDetents([.large])
        }
        .onReceive(tick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings (or the background): pick up calendar access and a new day right away.
            if phase == .active { calendarGranted = CalendarService.shared.hasAccess; now = .now }
        }
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
                if snap.lanes.count > 0 {
                    AppJourney(lanes: snap.lanes, now: now, color: { categories.displayColor(for: $0) })
                        .padding(.top, 8)
                }
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
            Color(red: 0.15, green: 0.17, blue: 0.24),   // v32: flat, no gradients
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    /// Add block · Go/Stop Live · Plan with words · Scan — one row under the card.
    private var heroButtons: some View {
        HStack(spacing: 10) {
            Button("Add block") { showingAdd = true }
                .buttonStyle(PrimaryButtonStyle())
            Button(activity.isRunning ? "Stop Live" : "Go Live") {
                Task {
                    if activity.isRunning { await activity.stop() } else { await activity.start() }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            // #5 Plan with words · v36 Photo task (replaces Scan to blocks)
            iconButton("siri", label: "Plan with words") { showingWords = true }
            Button { showingScan = true } label: {
                Image(systemName: "camera")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo task")
        }
    }

    /// Live timer pill on the card: green countdown, yellow +over, or countdown to the next block.
    @ViewBuilder
    private func heroTimer(snap: DaySnapshot) -> some View {
        if let c = snap.current, snap.overtime {
            LiveTimerPill(range: c.end...c.end.addingTimeInterval(24 * 3600), down: false, prefix: "+",
                          fill: Color(red: 1, green: 0.84, blue: 0.04), text: .black)
        } else if let c = snap.current, c.end > now {
            // One clock for check and range (the 30s `now` can be behind Date.now → inverted range crash).
            let t = min(Date.now, c.end)
            LiveTimerPill(range: t...c.end, down: true, fill: DayLiveStyle.doneGreen, text: .white)
        } else if snap.current == nil, let n = snap.next, n.start > now {
            let t = min(Date.now, n.start)
            LiveTimerPill(range: t...n.start, down: true, fill: .white.opacity(0.18), text: .white)
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
            InfoItem(label: "Focused", value: focused.hoursMinutes, color: DayLiveStyle.doneGreen),
            InfoItem(label: "Steps", value: stepsTotal == 0 ? "—" : "\(stepsDone)/\(stepsTotal)", color: Theme.blue),
            InfoItem(label: "Meetings left", value: "\(meetingsLeft)", color: Color(hex: "#BF5AF2")),
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
                    BlockRow(block: block, now: now,
                             color: categories.displayColor(for: block),
                             steps: store.steps(for: block.id),
                             icon: categories.category(for: block).iconName,
                             pill: rowPill(block, snap: snap))
                        .contentShape(Rectangle())
                        .onTapGesture { editing = block }
                        // v35: long-press = Apple's own menu. Calendar events: Edit and Mark done only.
                        .contextMenu { blockMenu(block) }
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
                .background(Circle().fill(Theme.card))   // v24: round icon buttons
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// v35: the long-press menu on a block in Today.
    @ViewBuilder
    private func blockMenu(_ block: Block) -> some View {
        Button { editing = block } label: { Label("Edit", systemImage: "pencil") }
        if block.source == .plan && block.end > now {
            Button {
                store.extend(id: block.id, by: 15)
                Task { await activity.refresh() }
            } label: { Label("Extend 15 min", systemImage: "clock") }
            Button { extending = block } label: { Label("Extend…", systemImage: "timer") }
        }
        if block.start <= now && store.overrides[block.id]?.end == nil {
            Button {
                store.finish(blockID: block.id, at: min(now, block.end))
                Task { await activity.refresh() }
            } label: { Label("Mark done", systemImage: "checkmark") }
        }
        if block.source == .plan {
            Divider()
            Button(role: .destructive) {
                store.delete(id: block.id)
                Task { await activity.refresh() }
            } label: { Label("Delete", systemImage: "trash") }
        }
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


/// v24: the day as a journey on the Today card — colored blocks on one track, a white knob at now,
/// hour marks underneath. Same look as the Lock Screen card.
struct AppJourney: View {
    let lanes: [Block]
    let now: Date
    let color: (Block) -> Color

    var body: some View {
        let from = min(lanes.first?.start ?? now, now)
        let to = max(lanes.map(\.end).max() ?? now, now.addingTimeInterval(60))
        let span = to.timeIntervalSince(from)
        let f: (Date) -> CGFloat = { CGFloat(min(max($0.timeIntervalSince(from) / span, 0), 1)) }
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                // v45: thick bars (16 pt, were 8) so short blocks read as blocks, not dots.
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.15)).frame(height: 16)
                    ForEach(lanes) { b in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color(b).opacity(b.end <= now ? 0.55 : 1))
                            .frame(width: max(6, w * (f(b.end) - f(b.start)) - 2), height: 16)
                            .offset(x: w * f(b.start))
                    }
                    Circle().fill(Color.white).frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: min(max(w * f(now) - 13, 0), w - 26))
                        .animation(.easeInOut(duration: 0.6), value: now)
                }
                .frame(height: 28)
            }
            .frame(height: 28)
            HStack {
                ForEach(Self.ticks(from, to), id: \.self) { d in
                    Text(d.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow))))
                    if d != Self.ticks(from, to).last { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's blocks on a timeline")
    }

    /// Up to 5 evenly spread hour marks across the window.
    static func ticks(_ a: Date, _ b: Date) -> [Date] {
        let cal = Calendar.current
        guard let first = cal.nextDate(after: a.addingTimeInterval(-1), matching: DateComponents(minute: 0), matchingPolicy: .nextTime),
              b > first else { return [] }
        let hours = max(1, Int(b.timeIntervalSince(first) / 3600))
        let step = max(1, Int((Double(hours) / 4).rounded(.up)))
        return stride(from: 0, through: hours, by: step).map { first.addingTimeInterval(Double($0) * 3600) }
    }
}
