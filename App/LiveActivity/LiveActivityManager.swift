import Combine
import ActivityKit
import UserNotifications
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
        s.tomorrowFirst = pre.first?.start
        s.tomorrowTitle = pre.first?.title
        s.leaveBy = pre.leaveBy
        s.bedBy = pre.bedBy
        return s
    }

    /// v20: today score (top row), Pause, and the last-5-minutes heads-up.
    /// The heads-up needs no wake-up: the card goes stale at `headsUpAt` and iOS redraws it in yellow.
    private func decorate(_ s: inout DayActivityAttributes.ContentState, snap: DaySnapshot, now: Date) {
        let cats = CategoryStore.shared
        var focus: TimeInterval = 0
        for b in snap.all {
            let ids = cats.categories(for: b).map(\.id)
            let focusShare = Double(ids.filter { $0 == "work" || $0 == "deepwork" }.count) / Double(max(ids.count, 1))
            focus += max(0, min(b.end, now).timeIntervalSince(b.start)) * focusShare
        }
        s.focusMinutes = Int(focus / 60)
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
        HistoryStore.shared.recordToday(raw: allTodayBlocks(now: now), now: now)
        let closed = DayCloseSettings.isClosed(at: now)
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
            // v21: waiting for the next block more than an hour out, the Island shows "20h" / "1d 4h".
            // Go stale an hour before so iOS redraws it as a live mm:ss countdown, no wake-up needed.
            else if snap.current == nil, let n = state.nextStart, n.addingTimeInterval(-3600) > now {
                staleAt = [staleAt, n.addingTimeInterval(-3600)].compactMap { $0 }.min()
            }
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
                nextStep: steps.first { !$0.done }?.title
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
        guard UserDefaults.standard.object(forKey: "meetingAlerts") as? Bool ?? true else {
            center.getPendingNotificationRequests { reqs in
                center.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix(prefix) })
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
        center.getPendingNotificationRequests { reqs in
            let old = reqs.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for r in requests { center.add(r) }
        }
    }
}
