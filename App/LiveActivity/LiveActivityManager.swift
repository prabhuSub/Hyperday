import Combine
import ActivityKit
@preconcurrency import UserNotifications
import BackgroundTasks
import Foundation
import UIKit
import WidgetKit

/// Starts, updates and restarts the one Hyperday Live Activity.
@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    /// When on, opening the app (or any refresh) starts the Live Activity if it isn't running.
    @Published var autoStart: Bool {
        didSet { UserDefaults.standard.set(autoStart, forKey: Keys.autoStart) }
    }

    private enum Keys {
        static let autoStart = "autoStartActivity"
        static let startedAt = "activityStartedAt"
    }

    /// iOS ends a Live Activity after ~8h. Restart a bit before that.
    private let maxAge: TimeInterval = 7.5 * 3600

    private init() {
        autoStart = (UserDefaults.standard.object(forKey: Keys.autoStart) as? Bool) ?? true
        isRunning = !Self.liveActivities().isEmpty
    }

    /// Ended-but-not-dismissed activities still appear in `activities`; ignore them.
    private static func liveActivities() -> [Activity<DayActivityAttributes>] {
        Activity<DayActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private var isRefreshing = false
    private var forceStart = false

    /// One line for the app header explaining the Live Activity state.
    var statusText: String {
        if !activitiesEnabled { return "Live Activities are off · open Settings" }
        if let lastError { return lastError }
        return isRunning ? "Live on your Lock Screen" : "Not live · tap Go Live"
    }
    private var pendingRefresh = false
    private var lastWidgetDay: WidgetDay?

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Today's raw blocks: your planned blocks + calendar events (before overrides).
    func todayBlocks(now: Date = .now) -> [Block] {
        allTodayBlocks(now: now).filter(FocusFilterState.allows)
    }

    /// Unfiltered (history/stats must not depend on the current Focus).
    func allTodayBlocks(now: Date = .now) -> [Block] {
        BlockStore.shared.planBlocks(on: now) + CalendarService.shared.events(on: now)
    }

    func snapshot(now: Date = .now) -> DaySnapshot {
        var snap = DayEngine.snapshot(
            of: todayBlocks(now: now),
            overrides: BlockStore.shared.overrides,
            steps: BlockStore.shared.steps,
            now: now
        )
        snap.accentHex = snap.current.map { CategoryStore.shared.displayColorHex(for: $0) }
        snap.iconName = snap.current.map { CategoryStore.shared.category(for: $0).iconName }
        return snap
    }

    /// Recompute the day and push it to the Live Activity. Safe to call often.
    private var refreshTask: Task<Void, Never>?

    func refresh() async {
        // Coalesce overlapping calls (launch + scene change + intent). A caller that arrives mid-pass sets the
        // flag and waits: the running loop does one more pass that includes its change, so a Lock Screen tap
        // is on screen before the intent returns. All on the main actor, so the flag check and the reset
        // of `refreshTask` happen in the same turn (no missed pass).
        pendingRefresh = true
        if let running = refreshTask { await running.value; return }
        isRefreshing = true
        let task = Task { @MainActor in
            while pendingRefresh {
                pendingRefresh = false
                await performRefresh()
            }
            refreshTask = nil
            isRefreshing = false
        }
        refreshTask = task
        await task.value
    }

    /// v9 Day Close: unfinished blocks you planned today (calendar events can't be carried over).
    func notDoneToday(now: Date = .now) -> [Block] {
        let done = Set(HistoryStore.shared.entries(on: now).filter(\.done).map(\.id))
        let mine = DayEngine.apply(BlockStore.shared.overrides, to: BlockStore.shared.planBlocks(on: now))
        return mine.filter { !done.contains($0.id) }.sorted { $0.start < $1.start }
    }

    /// The "Day closed" card: done today, what's left to review, and tomorrow's pre-flight.
    private func closedState(from snap: DaySnapshot, now: Date) -> DayActivityAttributes.ContentState {
        var s = snap.contentState()
        let entries = HistoryStore.shared.entries(on: now)
        let pre = Preflight.forTomorrow(after: now)
        let reviewed = DayCloseSettings.closedDays.contains(HeatData.key(now))
        s.closed = true
        s.title = "Day closed"
        s.label = "Day closed"
        s.also = nil
        s.source = .free
        s.action = nil
        s.actionBlockID = nil
        s.currentEnd = nil
        s.overSince = nil
        s.freeStart = nil
        s.nextStart = nil
        s.nextTitle = nil
        s.accentHex = nil
        s.iconName = nil
        s.doneCount = entries.filter(\.done).count
        s.totalCount = max(snap.all.count, entries.count)
        s.reviewCount = reviewed ? 0 : notDoneToday(now: now).count
        let f = Self.focus(snap.all, now: now)   // D · big focus number + bars by hour
        s.focusMinutes = f.minutes
        s.focusByHour = f.byHour
        s.tomorrowFirst = pre.first?.start
        s.tomorrowTitle = pre.first?.title
        s.leaveBy = pre.leaveBy
        s.bedBy = pre.bedBy
        return s
    }

    /// Work + Deep Work time so far today, in total and per hour (6 AM–10 PM).
    /// v34: time you actually spent in blocks today (every category, overlaps counted once), up to now.
    /// It used to count only Work / Deep Work, so a day of meetings showed "0m".
    static func focus(_ blocks: [Block], now: Date) -> (minutes: Int, byHour: [Double]) {
        let cal = Calendar.current
        let six = cal.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        let today = cal.startOfDay(for: now)
        var spans: [(Date, Date)] = blocks.compactMap { b in
            let s = max(b.start, today), e = min(b.end, now)
            return e > s ? (s, e) : nil
        }.sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for sp in spans {
            if let last = merged.last, sp.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, sp.1) } else { merged.append(sp) }
        }
        spans = merged
        var hours = Array(repeating: 0.0, count: 16)
        for (s, e) in spans {
            for h in 0..<16 {
                let hs = six.addingTimeInterval(Double(h) * 3600), he = hs.addingTimeInterval(3600)
                let overlap = min(e, he).timeIntervalSince(max(s, hs))
                if overlap > 0 { hours[h] += overlap / 60 }
            }
        }
        let total = spans.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) }
        return (Int(total / 60), hours)
    }

    /// After midnight, record the previous day one last time as of 11:59:59 PM, so a block that was
    /// running (or a Done tapped) after the last refresh before midnight isn't lost.
    private func finalizePreviousDayIfNeeded(now: Date) {
        let cal = Calendar.current
        let key = "lastRecordedDay"
        defer { UserDefaults.standard.set(now, forKey: key) }
        guard let last = UserDefaults.standard.object(forKey: key) as? Date,
              !cal.isDate(last, inSameDayAs: now), last < now,
              let endOfLast = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last))?.addingTimeInterval(-1)
        else { return }
        CalendarService.shared.invalidate()
        HistoryStore.shared.recordToday(raw: allTodayBlocks(now: endOfLast), now: endOfLast)
    }

    /// v20: today score (top row), Pause, and the last-5-minutes heads-up.
    /// The heads-up needs no wake-up: the card goes stale at `headsUpAt` and iOS redraws it in yellow.
    private func decorate(_ s: inout DayActivityAttributes.ContentState, snap: DaySnapshot, now: Date) {
        let cats = CategoryStore.shared
        let f = Self.focus(snap.all, now: now)
        s.focusMinutes = f.minutes
        s.focusByHour = f.byHour

        // v24 journey track: every block (non-overlapping lanes) from the first start to the last end.
        if let first = snap.lanes.first?.start, let last = snap.lanes.map(\.end).max(), last > first {
            let from = min(first, now), to = max(last, now.addingTimeInterval(60))
            let span = to.timeIntervalSince(from)
            s.trackFrom = from
            s.trackTo = to
            s.track = snap.lanes.prefix(24).map {
                TrackSeg(s: $0.start.timeIntervalSince(from) / span, e: $0.end.timeIntervalSince(from) / span,
                         hex: cats.displayColorHex(for: $0))
            }
        }
        if let n = snap.next {
            s.nextHex = cats.displayColorHex(for: n)
            s.nextIcon = cats.category(for: n).iconName
            s.nextEnd = n.end
            // C · free time: the block after next, for the "Later" capsule.
            if let later = snap.all.first(where: { $0.start >= n.end && $0.id != n.id }) {
                s.laterTitle = later.title
                s.laterStart = later.start
                s.laterHex = cats.displayColorHex(for: later)
                s.laterEnd = later.end
            }
        }
        let shown = Set(snap.all.map(\.id))   // same set as the total (respects the Focus filter)
        s.doneCount = HistoryStore.shared.entries(on: now).filter { $0.done && shown.contains($0.id) }.count
        s.totalCount = snap.all.count

        guard let c = snap.current, !snap.overtime else { return }
        if c.source == .plan {
            s.canPause = true
            if BlockStore.shared.isPaused(c.id) {
                s.paused = true
                s.pausedLeft = max(0, c.end.timeIntervalSince(now))
                return
            }
        }
        let warn = c.end.addingTimeInterval(-300)
        // Only when nothing else changes the card first (an overlap ending, the next block starting).
        if c.duration > 600, warn > now, warn <= (snap.nextBoundary ?? .distantFuture) {
            s.headsUpAt = warn
            if let n = snap.next {
                let place = n.location.flatMap { $0.split(separator: "\n").first.map(String.init) }
                s.headsUp = "Next: \(n.title) \(n.start.shortTime)" + (place.map { " · \($0)" } ?? "")
                s.headsNextTitle = n.title
                s.headsNextStart = n.start
                s.headsNextPlace = place
                s.headsNextHex = CategoryStore.shared.displayColorHex(for: n)
            } else {
                s.headsUp = "Wrap up · nothing after this"
            }
        }
    }

    /// #9: while driving, show the arrival time and how it fits the next block.
    private func driveState(from snap: DaySnapshot, since: Date, now: Date) async -> DayActivityAttributes.ContentState {
        var s = snap.contentState()
        let next = snap.next ?? snap.current
        let office = DayCloseSettings.officeDays.contains(Calendar.current.component(.weekday, from: now))
            ? RealityStore.shared.place("office") : nil
        let arrive = await DriveETA.arrival(to: next?.location, orPlace: office)
        s.driving = true
        s.driveSince = since
        s.arriveAt = arrive
        if let next, let arrive {
            s.spareMinutes = Int((next.start.timeIntervalSince(arrive) / 60).rounded())
        }
        s.title = next.map { "Next: \($0.title) \($0.start.shortTime)" } ?? "Driving"
        s.also = nil
        s.action = nil
        s.actionBlockID = nil
        s.freeStart = nil
        s.nextStart = nil
        s.overSince = nil
        return s
    }

    private func performRefresh() async {
        let now = Date.now
        let snap = snapshot(now: now)
        finalizePreviousDayIfNeeded(now: now)
        HistoryStore.shared.recordToday(raw: allTodayBlocks(now: now), now: now)
        // v34: past the close time the card only closes once nothing is left today. A block still running or
        // still to come (an 11:30 PM email) keeps the normal card with its Done button; it closes after that.
        let closed = DayCloseSettings.isClosed(at: now) && !snap.hasAnythingLeft
        let cal = Calendar.current
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let closeAt = DayCloseSettings.closeTime(on: now)
        // Wake up at the close time too, so the card switches to "Day closed" on time.
        let boundary = closed ? midnight
            : [snap.nextBoundary, DayCloseSettings.showOnLockScreen && closeAt > now ? closeAt : nil].compactMap { $0 }.min()
        var state = closed ? closedState(from: snap, now: now) : snap.contentState()
        var staleAt = boundary
        if !closed {
            decorate(&state, snap: snap, now: now)
            state.boundaryAt = boundary
            if state.paused == true { staleAt = nil }               // end keeps moving while paused
            else if let h = state.headsUpAt { staleAt = [staleAt, h].compactMap { $0 }.min() }
            // v28: in free time the one stale redraw is kept for the next block's start (the card switches
            // itself to that block then); the Island's "2h+" is rounded down so it stays true meanwhile.
        }
        if !closed, let since = RealityStore.shared.driveStartedAt {
            state = await driveState(from: snap, since: since, now: now)
        }
        let content = ActivityContent(state: state, staleDate: staleAt)
        let running = Self.liveActivities()
        let inForeground = UIApplication.shared.applicationState == .active

        let closePending = DayCloseSettings.showOnLockScreen && closeAt > now
        let dayIsOver = !closed && !closePending && !snap.all.isEmpty && !snap.hasAnythingLeft
        let force = forceStart
        forceStart = false

        if dayIsOver && !force {
            // Day's over: show "Day complete" briefly, then let iOS dismiss it.
            for a in running { await a.end(content, dismissalPolicy: .default) }
        } else if let activity = running.first {
            // Only ever one Hyperday card: clear duplicates and ended cards still sitting on the Lock Screen.
            await Self.endAll(except: activity.id)
            let startedAt = (UserDefaults.standard.object(forKey: Keys.startedAt) as? Date) ?? now
            if now.timeIntervalSince(startedAt) > maxAge && inForeground {
                // Restart only in the foreground: a background request would fail and leave nothing on screen.
                await Self.endAll()
                request(content)
            } else {
                await activity.update(content)
                lastError = nil
            }
        } else if force || (autoStart && inForeground && (snap.hasAnythingLeft || closed)) {
            // (A background request always fails, so only auto-start while the app is open.)
            // Auto-start only when there's something to show; "Go Live" always starts.
            await Self.endAll()
            request(content)
        }

        isRunning = !Self.liveActivities().isEmpty
        MeetingAlerts.schedule(snap.all, now: now)
        writeWidgetDay(snap, now: now)
        writeCalendarCounts(now: now)
        BackgroundRefresh.schedule(at: boundary ?? staleAt)
    }

    /// Hand today's blocks to the Home Screen widgets (only when they changed, to save reloads).
    private func writeWidgetDay(_ snap: DaySnapshot, now: Date) {
        let store = BlockStore.shared
        let blocks = snap.all.map { b -> WidgetBlock in
            let steps = store.steps(for: b.id)
            return WidgetBlock(
                id: b.id, title: b.title, start: b.start, end: b.end,
                colorHex: CategoryStore.shared.displayColorHex(for: b),
                stepsDone: steps.filter(\.done).count, stepsTotal: steps.count,
                detail: b.source == .calendar ? (b.calendarName ?? "Calendar") : "My plan",
                nextStep: steps.first { !$0.done }?.title,
                icon: CategoryStore.shared.category(for: b).iconName,
                done: store.overrides[b.id]?.end != nil,
                isPlan: b.source == .plan,
                paused: store.isPaused(b.id)
            )
        }
        let day = WidgetDay(day: Calendar.current.startOfDay(for: now), blocks: blocks)   // not `now`: it never matched
        guard day != lastWidgetDay else { return }
        lastWidgetDay = day
        if WidgetShared.save(day) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private var lastCalendarCounts: [String: Int]?
    private var lastWeekLoad: [String: [Double]]?

    /// Blocks + events per day for the 3-week calendar widget (last week · this week · next week).
    private func writeCalendarCounts(now: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // Monday
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let from = cal.date(byAdding: .day, value: -7, to: thisWeek),
              let to = cal.date(byAdding: .day, value: 14, to: thisWeek) else { return }
        var counts: [String: Int] = [:]
        let blocks = CalendarService.shared.events(from: from, to: to)
            + BlockStore.shared.planBlocks.filter { $0.start >= from && $0.start < to }
        for b in blocks { counts[HeatData.key(b.start), default: 0] += 1 }

        // Workload for the Large heatmap widget: planned vs done hours, Monday–Sunday this week.
        var week: [String: [Double]] = [:]
        for i in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: i, to: thisWeek) else { continue }
            let key = HeatData.key(d)
            let planned = blocks.filter { cal.isDate($0.start, inSameDayAs: d) }.reduce(0) { $0 + $1.duration } / 3600
            let done = HistoryStore.shared.entries(on: d).filter(\.done).reduce(0) { $0 + $1.hours }
            week[key] = [(planned * 10).rounded() / 10, (done * 10).rounded() / 10]
        }
        if week != lastWeekLoad {
            lastWeekLoad = week
            if WidgetShared.saveWeek(week) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.heatKind) }
        }

        guard counts != lastCalendarCounts else { return }
        lastCalendarCounts = counts
        if WidgetShared.saveCalendar(counts) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.calKind)
        }
    }

    func start() async {
        autoStart = true
        forceStart = true
        await refresh()
    }

    /// Settings › "Preview all card styles": shows A (running), B (last 5 min), C (free) and D (day closed)
    /// on the real Lock Screen card for 7 s each with sample content, then puts your real day back.
    /// Lock the phone or go Home to watch (iOS hides an app's own card while the app is open).
    func previewStyles() async {
        guard let activity = Self.liveActivities().first else {
            lastError = "Tap Go Live first, then Preview."
            return
        }
        let bg = UIApplication.shared.beginBackgroundTask(withName: "preview")
        defer { UIApplication.shared.endBackgroundTask(bg) }
        for (state, stale) in Self.previewStates(now: .now) {
            await activity.update(ActivityContent(state: state, staleDate: stale))
            try? await Task.sleep(for: .seconds(5))   // v48: 11 states now, 5 s each
        }
        await refresh()
    }

    /// Settings › Test: hold ONE sample style (0 A running, 1 B last 5 min, 2 C free, 3 D closed) for 60 s.
    func previewOne(_ index: Int) async {
        guard let activity = Self.liveActivities().first else {
            lastError = "Tap Go Live first, then pick a style."
            return
        }
        let bg = UIApplication.shared.beginBackgroundTask(withName: "preview-one")
        defer { UIApplication.shared.endBackgroundTask(bg) }
        let all = Self.previewStates(now: .now)
        guard all.indices.contains(index) else { return }
        await activity.update(ActivityContent(state: all[index].0, staleDate: all[index].1))
        try? await Task.sleep(for: .seconds(60))
        await refresh()
    }

    /// Settings › Test: a real mini-day around now, so the card changes on its own:
    /// running now (A), its last 5 minutes start in ~1 min (B), a 3-minute gap (C), then the next block,
    /// then a later one. Titles start with "Test ·" so they're easy to remove.
    func loadTestDay() async {
        let now = Date.now
        func at(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }
        let store = BlockStore.shared
        removeTestDay()
        // v48: one test day that walks through every case in about an hour.
        // Done earlier → running now with steps (Step button) → short free gap → a photo task → Standup → Gym.
        if let id = store.add(title: "Test · Inbox zero", start: at(-70), minutes: 20, categoryIDs: ["work"]) {
            store.finish(blockID: id, at: at(-52))                       // marked done, a bit early
        }
        if let id = store.add(title: "Test · Deep work", start: at(-24), minutes: 30, categoryIDs: ["deepwork"]) {
            store.setSteps([Step(title: "Outline", done: true), Step(title: "Draft the intro"),
                            Step(title: "Charts"), Step(title: "Send for review")], for: id)
        }
        if let id = store.add(title: "Test · Read the letter", start: at(9), minutes: 10, categoryIDs: ["learning"]) {
            PhotoStore.shared.add(Self.testPhoto(), to: id)              // a photo task (never read)
        }
        _ = store.add(title: "Test · Standup", start: at(20), minutes: 15, categoryIDs: ["meetings"])
        _ = store.add(title: "Test · Gym", start: at(45), minutes: 30, categoryIDs: ["fitness"])
        autoStart = true
        forceStart = true
        await refresh()
    }

    /// A plain test picture for the photo task, drawn on the phone (no real photo needed).
    private static func testPhoto() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.96, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.76, green: 0.31, blue: 0.16, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 200))
            let title = NSAttributedString(string: "Test letter", attributes: [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: UIColor.white])
            title.draw(at: CGPoint(x: 60, y: 60))
            UIColor(white: 0.75, alpha: 1).setFill()
            for i in 0..<14 { ctx.fill(CGRect(x: 60, y: 280 + i * 60, width: i % 4 == 3 ? 420 : 780, height: 18)) }
        }
    }

    func removeTestDay() {
        let store = BlockStore.shared
        for b in store.planBlocks where b.title.hasPrefix("Test · ") { store.delete(id: b.id) }
    }

    func clearTestDay() async {
        removeTestDay()
        await refresh()
    }

    static func previewStates(now: Date) -> [(DayActivityAttributes.ContentState, Date?)] {
        let cal = Calendar.current
        let purple = "#BF5AF2", green = "#30D158", orange = "#FF9F0A", blue = "#0A84FF"
        func t(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }
        func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
        var base = DayActivityAttributes.ContentState(
            label: "Next · Standup at \(time(t(45)))", title: "Deep work", also: nil, source: .plan,
            segments: [1, 0.4, 0, 0], dayProgress: 0.45, currentEnd: t(40), actionBlockID: "preview",
            action: .done, stepsDone: nil, stepsTotal: nil, accentHex: green, alsoIsStep: nil,
            freeStart: nil, nextStart: nil, nextTitle: nil, overSince: nil, iconName: "deepwork")
        base.currentStart = t(-20)
        base.nextHex = purple; base.nextIcon = "meetings"
        base.doneCount = 3; base.totalCount = 7; base.focusMinutes = 130
        base.trackFrom = t(-180); base.trackTo = t(300)
        base.track = [TrackSeg(s: 0.02, e: 0.22, hex: blue), TrackSeg(s: 0.33, e: 0.42, hex: green),
                      TrackSeg(s: 0.47, e: 0.53, hex: purple), TrackSeg(s: 0.62, e: 0.78, hex: blue),
                      TrackSeg(s: 0.86, e: 0.97, hex: orange)]

        base.canPause = true

        // A · running
        let a = base

        // B · last 5 minutes (goes stale in 1 s → iOS redraws it as Now → Next)
        var b = base
        b.currentStart = t(-55); b.currentEnd = t(5)
        b.headsUpAt = now; b.boundaryAt = t(5)
        b.headsNextTitle = "Standup"; b.headsNextStart = t(5); b.headsNextPlace = "Room 3B"; b.headsNextHex = purple
        b.headsUp = "Next: Standup \(time(t(5))) · Room 3B"

        // C · free time, next block in 5 min, Gym later
        var c = base
        c.title = "Free"; c.source = .free; c.action = nil; c.actionBlockID = nil
        c.accentHex = nil; c.iconName = nil; c.currentStart = nil; c.currentEnd = nil
        c.freeStart = t(-10); c.nextStart = t(5); c.nextTitle = "Standup"; c.nextEnd = t(20)
        c.label = "Next · Standup at \(time(t(5)))"
        c.laterTitle = "Gym"; c.laterStart = t(180); c.laterEnd = t(240); c.laterHex = orange

        // D · day closed
        var d = base
        d.closed = true; d.title = "Day closed"; d.source = .free; d.action = nil; d.actionBlockID = nil
        d.currentEnd = nil; d.doneCount = 4; d.totalCount = 7; d.reviewCount = 0; d.focusMinutes = 190
        d.focusByHour = [0, 0, 20, 55, 60, 30, 0, 45, 60, 25, 0, 0, 0, 0, 0, 0]
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        d.tomorrowFirst = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        d.tomorrowTitle = "Standup"
        d.bedBy = cal.date(bySettingHour: 23, minute: 0, second: 0, of: now)

        // v48 · every other state, so each can be checked without waiting for the moment of the day.
        // E · paused (timer frozen at 25:30, Resume in yellow)
        var e = base
        e.paused = true; e.pausedLeft = 25 * 60 + 30

        // F · overtime (ran 6 min past its end; yellow, +6:00 OVER)
        var f = base
        f.currentStart = t(-66); f.currentEnd = t(-6); f.overSince = t(-6)

        // G · steps (Step 2/4 button, the next step under the title)
        var g = base
        g.title = "Write the report"; g.iconName = "work"; g.accentHex = blue
        g.stepsDone = 1; g.stepsTotal = 4; g.action = .checkStep
        g.also = "Step 2 · Draft the intro"; g.alsoIsStep = true

        // H · a calendar event (no Pause: Hyperday never edits your calendar)
        var h = base
        h.title = "Design review"; h.source = .calendar; h.iconName = "meetings"; h.accentHex = purple
        h.canPause = false; h.currentStart = t(-10); h.currentEnd = t(20)

        // I · free time with only a Next (no Later)
        var i = c
        i.laterTitle = nil; i.laterStart = nil; i.laterEnd = nil; i.laterHex = nil
        i.freeStart = t(-30); i.nextStart = t(25); i.nextEnd = t(55)
        i.label = "Next · Standup at \(time(t(25)))"

        // J · day closed with 3 tasks still to review
        var j = d
        j.reviewCount = 3; j.doneCount = 4; j.totalCount = 7

        // K · driving to the next place
        var k = base
        k.driving = true; k.title = "Drive to Office"; k.source = .free; k.action = nil; k.actionBlockID = nil
        k.driveSince = t(-12); k.arriveAt = t(18); k.spareMinutes = 7

        return [(a, nil), (b, now.addingTimeInterval(1)), (c, nil), (d, nil),
                (e, nil), (f, nil), (g, nil), (h, nil), (i, nil), (j, nil), (k, nil)]
    }

    func stop() async {
        autoStart = false
        for a in Self.liveActivities() {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
    }

    /// Ends every Hyperday Live Activity immediately (including ended ones iOS keeps showing for up to 4 hours).
    private static func endAll(except keep: String? = nil) async {
        for a in Activity<DayActivityAttributes>.activities where a.id != keep {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func request(_ content: ActivityContent<DayActivityAttributes.ContentState>) {
        guard activitiesEnabled else {
            lastError = "Live Activities are off. Turn them on in Settings › Hyperday."
            return
        }
        do {
            let attributes = DayActivityAttributes(dayStart: Calendar.current.startOfDay(for: .now))
            _ = try Activity<DayActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
            UserDefaults.standard.set(Date.now, forKey: Keys.startedAt)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Best-effort wake-ups at block boundaries. iOS decides the real timing (can be late or skipped).
/// v1.1 replaces this with pushes from the Raspberry Pi for exact switching.
enum BackgroundRefresh {
    static let id = "com.prabhu.daylive.refresh"

    static func schedule(at date: Date?) {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = date ?? Date.now.addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}


/// v23 #11: "Standup in 5 min · Room 3B" five minutes before each calendar meeting.
/// A scheduled local notification fires on time even when the app is asleep (a Live Activity alert
/// would need the app awake or a push server). Only calendar events, never your own blocks.
enum MeetingAlerts {
    private static let prefix = "hd-meet-"

    @MainActor
    static func schedule(_ blocks: [Block], now: Date) {
        let center = UNUserNotificationCenter.current()
        guard (UserDefaults.standard.object(forKey: "meetingAlerts") as? Bool) ?? true else {
            Task { @MainActor in
                let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
                center.removePendingNotificationRequests(withIdentifiers: old)
            }
            return
        }
        let upcoming = blocks
            .filter { $0.source == .calendar && !$0.declined && $0.start.addingTimeInterval(-300) > now }
            .sorted { $0.start < $1.start }
            .prefix(12)
        let requests: [UNNotificationRequest] = upcoming.map { b in
            let c = UNMutableNotificationContent()
            c.title = "\(b.title) in 5 min"
            c.body = [b.location?.split(separator: "\n").first.map(String.init), b.calendarName]
                .compactMap { $0 }.joined(separator: " · ")
            c.sound = .default
            c.interruptionLevel = .active
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                        from: b.start.addingTimeInterval(-300))
            return UNNotificationRequest(identifier: prefix + b.id, content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
        Task { @MainActor in
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for r in requests { try? await center.add(r) }
        }
    }
}
