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
    @State private var seenIDs: Set<String>?   // v57: rows not seen before blur in and flash
    @Environment(\.scenePhase) private var scenePhase

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let snap = activity.snapshot(now: now)

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("today.top").background(JTScrollProbe(tab: "today"))   // v74: tapping Today scrolls this page all the way up
                    // Card + buttons move as one block: TV-app style, they lift and fade together
                    // as they scroll up under the title. The round + covers adding once they're gone.
                    VStack(alignment: .leading, spacing: 12) {
                        hero(snap: snap).jtStagger(0)
                        heroButtons.jtStagger(1)   // same left/right edges as the card above
                    }
                    .padding(.horizontal, Theme.edge)   // same margin as the title and the cards below
                    .padding(.top, 6)
                    .scrollTransition(.interactive, axis: .vertical) { view, phase in
                        view
                            .opacity(phase.value < 0 ? 1 + phase.value * 0.8 : 1)
                            .offset(y: phase.value < 0 ? phase.value * -40 : 0)
                            .scaleEffect(phase.value < 0 ? 1 + phase.value * 0.04 : 1, anchor: .top)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if !calendarGranted { calendarBanner.jtStagger(0) }
                        meters(snap).jtStagger(1)          // v58: JobTrail fleet-card meters
                        JTSectionHead("Schedule", sub: "\(snap.all.count) block\(snap.all.count == 1 ? "" : "s")") { legend }
                            .jtStagger(2)
                        timeline(snap: snap).jtStagger(3)
                        JTSectionHead("Plan vs real").jtStagger(4)
                        RealityCard(blocks: snap.all, now: now).jtStagger(5)
                        Color.clear.frame(height: 0).id("today.top.bottom")
                    }
                    .padding(.horizontal, Theme.edge)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .jtScrollsToTop("today", anchor: "today.top")   // v60/v74: tapping Today scrolls all the way up
            .background(DotPage())
            .refreshable {                       // v59: pull to refresh the day + Live Activity
                now = .now
                await activity.refresh()
            }
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
            if CalendarService.shared.needsPrompt && !UserDefaults.standard.bool(forKey: "hdDemo") {   // v57: no prompt in screenshot runs
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
                HStack(spacing: 8) {
                    // v57: live status dot (pulses; ripples while a block is running).
                    ZStack {
                        if heroStatus(snap) == .running { RippleRings(color: HDTone.green, size: 7) }
                        PulseDot(color: heroStatus(snap).color, size: 7, live: heroStatus(snap) != .done)
                    }
                    .frame(width: 10, height: 10)
                    Text("\(date) · \(state)")
                        .font(.hdMono(size: 11, weight: .medium))
                        .kerning(0.9)
                        .foregroundStyle(HDTone.dim)
                    Spacer(minLength: 8)
                    heroTimer(snap: snap)
                }
                Text(title)
                    .font(.hd(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                    .id(title)
                    .hdBlurIn()                      // v57: a new current block fades in from blur
                HStack(alignment: .center, spacing: 10) {
                    Text(subtitle)
                        .font(.hd(size: 14))
                        .foregroundStyle(HDTone.soft)
                    Spacer(minLength: 4)
                    // v59: JobTrail pulse graph: heartbeat while running, drift while waiting.
                    JTPulseButton(info: heroInfo(snap)).frame(width: 64, height: 24)   // v60: tap for details
                }
                if let c = snap.current {
                    // v57: JobTrail progress bar: green while running, red when over time.
                    let total = max(c.end.timeIntervalSince(c.start), 1)
                    HDProgressBar(value: now.timeIntervalSince(c.start) / total,
                                  color: snap.overtime ? HDTone.danger : HDTone.green)
                        .padding(.top, 4)
                }
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
                    .font(.hd(size: 12))
                    .foregroundStyle(activity.lastError == nil ? HDTone.dim : HDTone.danger)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZStack(alignment: .leading) {
            InstrumentBackground()
            DotGrid().fill(HDTone.instrumentDot)                                        // v58: JobTrail map dots
            JTDriftGlow(color: heroStatus(snap).color, active: heroStatus(snap) != .done)   // v59: wandering status light
            JTEdge(color: heroStatus(snap).color, live: heroStatus(snap) == .running)        // v59: breathing accent edge
        }.clipShape(Chamfer(cut: 14)))
        .overlay(Chamfer(cut: 14).strokeBorder(HDTone.lineDark, lineWidth: 1))
        // v57: active card = amber border + soft glow; while a block runs it is "hot" and the glow breathes.
        .hdGlow(radius: 16, active: heroStatus(snap) != .done, hot: heroStatus(snap) == .running || heroStatus(snap) == .failed)
        .animation(HDEase.standard(0.5), value: heroStatus(snap) == .running)
    }

    /// v60: what the hero's pulse graph pops up.
    private func heroInfo(_ snap: DaySnapshot) -> JTPulseInfo {
        if let c = snap.current {
            let st = store.steps(for: c.id)
            var items = [
                JTKV(key: "Started", value: c.start.shortTime),
                JTKV(key: "Ends", value: c.end.shortTime),
                JTKV(key: "Length", value: c.end.timeIntervalSince(c.start).hoursMinutes),
                JTKV(key: "Source", value: c.source == .calendar ? (c.calendarName ?? "Calendar") : "My plan"),
            ]
            if !st.isEmpty { items.append(JTKV(key: "Steps", value: "\(st.filter(\.done).count)/\(st.count)", color: HDTone.amber)) }
            if let n = snap.next { items.append(JTKV(key: "Next", value: "\(n.title) · \(n.start.shortTime)")) }
            return JTPulseInfo(title: c.title, status: heroStatus(snap), subtitle: categories.category(for: c).name.uppercased(),
                               items: items, range: c.start...c.end)
        }
        if let n = snap.next {
            return JTPulseInfo(title: "Free until \(n.start.shortTime)", status: .waiting,
                               subtitle: "NEXT · \(n.title)",
                               items: [JTKV(key: "Next", value: n.title), JTKV(key: "Starts", value: n.start.shortTime),
                                       JTKV(key: "Length", value: n.end.timeIntervalSince(n.start).hoursMinutes),
                                       JTKV(key: "Left today", value: "\(snap.all.filter { $0.start >= now }.count) blocks")],
                               range: now...n.start)
        }
        return dayInfo(snap)
    }

    /// v60: the whole day, for the Today card's pulse graph.
    private func dayInfo(_ snap: DaySnapshot) -> JTPulseInfo {
        let done = snap.all.filter { $0.end <= now }.count
        let nums = todayNumbers(snap)
        var items = [JTKV(key: "Blocks", value: "\(done)/\(snap.all.count) done", color: HDTone.blue)]
        items += nums.map { JTKV(key: $0.label, value: $0.value) }
        if let c = snap.current { items.append(JTKV(key: "Now", value: c.title, color: HDTone.green)) }
        if let n = snap.next { items.append(JTKV(key: "Next", value: "\(n.start.shortTime) \(n.title)", color: HDTone.amber)) }
        let first = snap.all.first?.start ?? now, last = snap.all.map(\.end).max() ?? now
        return JTPulseInfo(title: "Today", status: snap.current != nil ? .running : (snap.next != nil ? .waiting : .done),
                           subtitle: now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased(),
                           items: items, range: snap.all.isEmpty ? nil : first...max(last, first.addingTimeInterval(60)))
    }

    /// Running = a block is live · failed = over time · waiting = free until the next · done = day complete.
    private func heroStatus(_ snap: DaySnapshot) -> HDStatus {
        if snap.current != nil { return snap.overtime ? .failed : .running }
        return snap.next != nil ? .waiting : .done
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
                    .font(.hd(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo task")
        }
    }

    /// Live timer pill on the card: green countdown, yellow +over, or countdown to the next block.
    @ViewBuilder
    private func heroTimer(snap: DaySnapshot) -> some View {
        if let c = snap.current, snap.overtime {
            LiveTimerPill(range: c.end...c.end.addingTimeInterval(24 * 3600), down: false, prefix: "+", status: .failed)
        } else if let c = snap.current, c.end > now {
            // One clock for check and range (the 30s `now` can be behind Date.now → inverted range crash).
            let t = min(Date.now, c.end)
            LiveTimerPill(range: t...c.end, down: true, status: .running)
        } else if snap.current == nil, let n = snap.next, n.start > now {
            let t = min(Date.now, n.start)
            LiveTimerPill(range: t...n.start, down: true, status: .waiting)
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

    /// v58: JobTrail legend (run · wait · done) beside the Schedule head.
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([("run", HDStatus.running), ("wait", .waiting), ("done", .done)], id: \.0) { item in
                HStack(spacing: 4) {
                    Circle().fill(item.1.color).frame(width: 6, height: 6)
                    Text(item.0).font(.mono(10)).foregroundStyle(HDTone.faintDark)
                }
            }
        }
    }

    /// v58: three meters with growing bars in one glowing card (JobTrail fleet card).
    private func meters(_ snap: DaySnapshot) -> some View {
        let items = todayNumbers(snap)
        let done = snap.all.filter { $0.end <= now }.count
        let fractions: [Double] = [
            min(1, focusedSeconds(snap) / (6 * 3600)),                       // a 6h focus day fills the bar
            stepsFraction(snap),
            snap.all.isEmpty ? 0 : Double(done) / Double(snap.all.count),   // day progress
        ]
        let colors = [HDTone.green, HDTone.amber, HDTone.blue]
        return JTCard(state: activity.isRunning ? .glow : .normal, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    JTStatusDot(status: snap.current != nil ? .running : (snap.next != nil ? .waiting : .done), size: 6)
                    Text("Today").font(.geist(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    JTPulseButton(info: dayInfo(snap), boxed: false)
                        .frame(width: 44, height: 14)
                    Text("\(done)/\(snap.all.count) DONE").font(.mono(11, .medium)).kerning(0.6).foregroundStyle(HDTone.faintDark)
                        .contentTransition(.numericText())
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        JTMeter(key: item.label, value: item.value, fraction: fractions[i], color: colors[i])
                    }
                }
            }
        }
    }

    private func focusedSeconds(_ snap: DaySnapshot) -> TimeInterval {
        var focused: TimeInterval = 0
        for b in snap.all {
            let cats = categories.categories(for: b).map(\.id)
            let share = 1 / Double(max(cats.count, 1))
            let focusCount = cats.filter { $0 == "work" || $0 == "deepwork" }.count
            focused += max(0, min(b.end, now).timeIntervalSince(b.start)) * share * Double(focusCount)
        }
        return focused
    }

    private func stepsFraction(_ snap: DaySnapshot) -> Double {
        let st = snap.all.flatMap { store.steps(for: $0.id) }
        return st.isEmpty ? 0 : Double(st.filter(\.done).count) / Double(st.count)
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
            InfoItem(label: "Meetings left", value: "\(meetingsLeft)", color: HDTone.blue),
        ]
    }

    private func timeline(snap: DaySnapshot) -> some View {
        VStack(spacing: 0) {
            if snap.all.isEmpty {
                Text("Nothing planned. Tap Add block, or load sample data in Settings.")
                    .font(.hd(size: 14))
                    .foregroundStyle(Theme.muted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(snap.all.enumerated()), id: \.element.id) { index, block in
                // v57: inset hairline so the connector line runs unbroken down the icon column.
                if index > 0 { Rectangle().fill(Theme.navActive).frame(height: 1).padding(.leading, 60) }
                let isNew = seenIDs.map { !$0.contains(block.id) } ?? false
                SwipeRow(leading: leadingActions(block), trailing: trailingActions(block)) {
                    BlockRow(block: block, now: now,
                             color: categories.displayColor(for: block),
                             steps: store.steps(for: block.id),
                             icon: categories.category(for: block).iconName,
                             pill: rowPill(block, snap: snap),
                             above: index > 0 ? flow(snap.all[index - 1], block, snap: snap) : nil,
                             below: index < snap.all.count - 1 ? flow(block, snap.all[index + 1], snap: snap) : nil)
                        .hdRowFlash(isNew)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = block }
                        // v35: long-press = Apple's own menu. Calendar events: Edit and Mark done only.
                        .contextMenu { blockMenu(block) }
                }
                .hdBlurIn(isNew)
            }
        }
        .background(HDTone.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .onAppear { if seenIDs == nil { seenIDs = Set(snap.all.map(\.id)) } }
        .onChange(of: snap.all.map(\.id)) { _, ids in
            // Let the new rows render once with their entry effects, then remember them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { seenIDs = Set(ids) }
        }
    }

    /// Connector between two neighbouring rows: green flowing into the running block,
    /// amber along what's still waiting, still grey through the past.
    private func flow(_ a: Block, _ b: Block, snap: DaySnapshot) -> FlowState {
        if b.id == snap.current?.id { return .running }
        if a.id == snap.current?.id || b.start > now { return .waiting }
        return .idle
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HDIcon(icon, size: 20)
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))   // v24: round icon buttons
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
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
                .font(.hd(size: 14))
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
            .font(.hd(size: 14, weight: .semibold))
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
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(HDTone.hover).frame(height: 16)
                    ForEach(lanes) { b in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color(b).opacity(b.end <= now ? 0.55 : 1))
                            .frame(width: max(6, w * (f(b.end) - f(b.start)) - 2), height: 16)
                            .hdShimmer(b.contains(now), color: .white)   // v58: the running lane shimmers
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .offset(x: w * f(b.start))
                    }
                    // v57: amber "now" knob with a soft glow.
                    Circle().fill(HDTone.amber).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                        .shadow(color: HDTone.amber.opacity(0.5), radius: 6)
                        .offset(x: min(max(w * f(now) - 7, 0), w - 14))
                        .animation(HDEase.standard(0.6), value: now)
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
            .font(.hdMono(size: 10, weight: .medium))
            .foregroundStyle(HDTone.faintDark)
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
