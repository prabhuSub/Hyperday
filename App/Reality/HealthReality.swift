import Foundation
import HealthKit

/// Workouts and per-night sleep from Apple Health (read-only, on the iPhone).
enum HealthReality {
    private static let store = HKHealthStore()

    static func authorize() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "hdDemo") { return false }   // v59: no Health sheet in screenshot runs
        #endif
        do {
            try await store.requestAuthorization(toShare: [], read: [sleep, HKObjectType.workoutType()])
            return true
        } catch {
            return false   // no HealthKit entitlement (deploy.sh fallback)
        }
    }

    static func workouts(on day: Date) async -> [DateInterval] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return await workouts(from: start, to: end)
    }

    static func workouts(from start: Date, to end: Date) async -> [DateInterval] {
        guard await authorize() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, result, _ in
                cont.resume(returning: (result ?? []).map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) })
            }
            store.execute(q)
        }
    }

    /// Minutes asleep per night, keyed by the day the night ended ("2026-10-01").
    static func sleepByNight(days: Int) async -> [String: Int] {
        guard await authorize(), let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
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
        var out: [String: Double] = [:]
        for s in samples where asleep.contains(s.value) {
            out[HeatData.key(s.endDate), default: 0] += s.endDate.timeIntervalSince(s.startDate) / 60
        }
        return out.mapValues { Int($0.rounded()) }
    }
}
