import Foundation
import HealthKit

/// Settings › Day Close (v9 #1 + #2). Stored in UserDefaults.
enum DayCloseSettings {
    private static let d = UserDefaults.standard

    /// Minutes after midnight when the day closes (default 7:00 PM).
    static var closeMinutes: Int {
        get { (d.object(forKey: "dcCloseMinutes") as? Int) ?? 19 * 60 }
        set { d.set(newValue, forKey: "dcCloseMinutes") }
    }
    static var showOnLockScreen: Bool {
        get { (d.object(forKey: "dcShowOnLock") as? Bool) ?? true }
        set { d.set(newValue, forKey: "dcShowOnLock") }
    }
    /// Sleep target in minutes. Defaults to the Health 2-week average, else 7h 30m.
    static var sleepMinutes: Int {
        get { (d.object(forKey: "dcSleepMinutes") as? Int) ?? healthSleepMinutes ?? 450 }
        set { d.set(newValue, forKey: "dcSleepMinutes") }
    }
    static var sleepIsCustom: Bool { d.object(forKey: "dcSleepMinutes") != nil }
    static var healthSleepMinutes: Int? {
        get { d.object(forKey: "dcHealthSleep") as? Int }
        set { d.set(newValue, forKey: "dcHealthSleep") }
    }
    static var routineMinutes: Int {
        get { (d.object(forKey: "dcRoutineMinutes") as? Int) ?? 45 }
        set { d.set(newValue, forKey: "dcRoutineMinutes") }
    }
    /// Your own number if you set one, else what Location learned (#3), else 25 min.
    static var commuteMinutes: Int {
        get { (d.object(forKey: "dcCommuteMinutes") as? Int) ?? learnedCommuteMinutes ?? 25 }
        set { d.set(newValue, forKey: "dcCommuteMinutes") }
    }
    static var learnedCommuteMinutes: Int? {
        get { d.object(forKey: "dcCommuteLearned") as? Int }
        set { d.set(newValue, forKey: "dcCommuteLearned") }
    }
    /// Weekdays you go to the office (Calendar weekday numbers, 1 = Sunday). Default Mon–Fri.
    static var officeDays: Set<Int> {
        get { Set((d.array(forKey: "dcOfficeDays") as? [Int]) ?? [2, 3, 4, 5, 6]) }
        set { d.set(Array(newValue).sorted(), forKey: "dcOfficeDays") }
    }
    /// Day keys you tapped "Close the day" on.
    static var closedDays: Set<String> {
        get { Set((d.array(forKey: "dcClosedDays") as? [String]) ?? []) }
        set { d.set(Array(newValue.sorted().suffix(60)), forKey: "dcClosedDays") }   // keep the latest 60
    }

    static func closeTime(on day: Date) -> Date {
        // Wall-clock time, so a daylight-saving day doesn't move it by an hour.
        let cal = Calendar.current
        return cal.date(bySettingHour: closeMinutes / 60, minute: closeMinutes % 60, second: 0, of: day)
            ?? cal.startOfDay(for: day).addingTimeInterval(TimeInterval(closeMinutes * 60))
    }

    /// From close time until midnight.
    static func isClosed(at now: Date) -> Bool { showOnLockScreen && now >= closeTime(on: now) }
}

/// #2 Tomorrow pre-flight: first block, leave-by, bed-by.
struct Preflight {
    var first: Block?
    var leaveBy: Date?      // only on office days
    var bedBy: Date?

    @MainActor
    static func forTomorrow(after now: Date = .now) -> Preflight {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return Preflight() }
        let blocks = (BlockStore.shared.planBlocks(on: tomorrow) + CalendarService.shared.events(on: tomorrow))
            .filter(FocusFilterState.allows)
        let first = DayEngine.apply(BlockStore.shared.overrides, to: blocks).min { $0.start < $1.start }
        guard let first else { return Preflight() }

        let office = DayCloseSettings.officeDays.contains(cal.component(.weekday, from: tomorrow))
        let leaveBy = office ? first.start.addingTimeInterval(-TimeInterval(DayCloseSettings.commuteMinutes * 60)) : nil
        let wake = (leaveBy ?? first.start).addingTimeInterval(-TimeInterval(DayCloseSettings.routineMinutes * 60))
        let bedBy = wake.addingTimeInterval(-TimeInterval(DayCloseSettings.sleepMinutes * 60))
        return Preflight(first: first, leaveBy: leaveBy, bedBy: bedBy)
    }
}

/// Reads your average sleep from Apple Health (on your iPhone only). Optional: without it, you set the target.
enum HealthSleep {
    private static let store = HKHealthStore()

    /// Average hours asleep per night over the last `days` nights, in minutes. nil if unavailable.
    static func averageMinutes(days: Int = 14) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        guard await HealthReality.authorize() else { return nil }   // one prompt for sleep + workouts
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, result, _ in
                cont.resume(returning: (result as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        // Group by the night (the day the sleep ended), add up asleep time, average the nights that have data.
        var perNight: [String: TimeInterval] = [:]
        for s in samples where asleep.contains(s.value) {
            perNight[HeatData.key(s.endDate), default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }
        let nights = perNight.values.filter { $0 > 2 * 3600 }
        guard !nights.isEmpty else { return nil }
        return Int((nights.reduce(0, +) / Double(nights.count) / 60).rounded())
    }

    @MainActor
    static func refreshAverage() async {
        if let m = await averageMinutes() { DayCloseSettings.healthSleepMinutes = m }
    }
}
