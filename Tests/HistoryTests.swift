import XCTest
@testable import DayLive

/// v52: history maths, midnight handling, skipped-day backfill and save/restore.
@MainActor
final class HistoryTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var day = cal.date(from: DateComponents(year: 2026, month: 10, day: 6))!
    private func at(_ h: Int, _ m: Int = 0, dayOffset: Int = 0) -> Date {
        let d = cal.date(byAdding: .day, value: dayOffset, to: day)!
        return cal.date(bySettingHour: h, minute: m, second: 0, of: d)!
    }
    private func entry(_ s: Date, planned: Date, actual: Date, done: Bool, source: BlockSource = .plan) -> HistoryEntry {
        HistoryEntry(id: UUID().uuidString, title: "x", categoryID: "work", source: source, start: s,
                     plannedEnd: planned, actualEnd: actual, stepsDone: 0, stepsTotal: 0, done: done)
    }

    // MARK: Ahead / behind

    func testDoneOnTimeIsAllAhead() {
        let r = HistoryStore.aheadBehind([entry(at(10), planned: at(11), actual: at(11), done: true)], now: at(12))
        XCTAssertEqual(r.up, 60, accuracy: 0.01)
        XCTAssertEqual(r.down, 0, accuracy: 0.01)
    }

    func testRunningOverCountsBelowTheLine() {
        let r = HistoryStore.aheadBehind([entry(at(10), planned: at(11), actual: at(11, 20), done: true)], now: at(12))
        XCTAssertEqual(r.up, 60, accuracy: 0.01)
        XCTAssertEqual(r.down, 20, accuracy: 0.01)
    }

    func testUnfinishedPastBlockCountsTheRestAsMissed() {
        let r = HistoryStore.aheadBehind([entry(at(10), planned: at(11), actual: at(10, 15), done: false)], now: at(12))
        XCTAssertEqual(r.up, 15, accuracy: 0.01)
        XCTAssertEqual(r.down, 45, accuracy: 0.01)
    }

    func testBlockStillRunningIsNotMissedYet() {
        let r = HistoryStore.aheadBehind([entry(at(10), planned: at(11), actual: at(10, 30), done: false)], now: at(10, 30))
        XCTAssertEqual(r.down, 0, accuracy: 0.01)
    }

    func testCalendarEventsAreIgnored() {
        let e = entry(at(10), planned: at(11), actual: at(11), done: true, source: .calendar)
        let r = HistoryStore.aheadBehind([e], now: at(12))
        XCTAssertEqual(r.up + r.down, 0)
        XCTAssertEqual(HistoryStore.planHours([e]), 0)
    }

    func testDoneAfterThePlanIsRecordedAsOvertime() {
        XCTAssertEqual(HistoryStore.recordedEnd(applied: at(11), doneAt: at(11, 25)), at(11, 25))
        XCTAssertEqual(HistoryStore.recordedEnd(applied: at(11), doneAt: nil), at(11))
    }

    // MARK: Midnight

    func testBlockCrossingMidnightIsCutToToday() {
        let (s, e) = HistoryStore.window(start: at(23), end: at(1, dayOffset: 1), now: at(23, 59, dayOffset: 0))
        XCTAssertEqual(s, at(23))
        XCTAssertEqual(e, at(23, 59))
    }

    func testNextMorningOnlyGetsTheAfterMidnightPart() {
        let (s, e) = HistoryStore.window(start: at(23), end: at(1, dayOffset: 1), now: at(9, dayOffset: 1))
        XCTAssertEqual(s, cal.startOfDay(for: at(9, dayOffset: 1)))
        XCTAssertEqual(e, at(1, dayOffset: 1))
    }

    // MARK: Skipped days

    func testSkippedDaysAreAllFinalized() {
        // Last opened Thursday 10 PM, next opened Saturday morning: Thursday and Friday both get recorded.
        let days = HistoryStore.daysToFinalize(last: at(22), now: at(8, dayOffset: 2))
        XCTAssertEqual(days, [cal.startOfDay(for: at(22)), cal.startOfDay(for: at(8, dayOffset: 1))])
    }

    func testSameDayFinalizesNothing() {
        XCTAssertTrue(HistoryStore.daysToFinalize(last: at(8), now: at(22)).isEmpty)
    }

    func testBackfillIsCappedAtTwoWeeks() {
        XCTAssertEqual(HistoryStore.daysToFinalize(last: at(8), now: at(8, dayOffset: 40)).count, 14)
    }

    // MARK: Save / restore

    func testDayRecordRoundTrips() throws {
        let rec = DayRecord(day: "2026-10-06", entries: [entry(at(10), planned: at(11), actual: at(10, 50), done: true)])
        let back = try JSONDecoder().decode([DayRecord].self, from: JSONEncoder().encode([rec]))
        XCTAssertEqual(back, [rec])
    }

    func testOldRecordWithoutDemoFlagStillLoads() throws {
        let json = #"[{"day":"2026-10-06","entries":[]}]"#
        let list = try JSONDecoder().decode([DayRecord].self, from: Data(json.utf8))
        XCTAssertEqual(list.first?.isDemo, false)
    }

    func testRealPhoneFileShapeLoads() throws {
        // Same shape as daylive-history.json on the phone (Apple reference-date seconds).
        let json = #"[{"day":"2026-10-01","isDemo":false,"entries":[{"done":true,"source":"plan","plannedEnd":812253600,"stepsDone":0,"start":812250900,"actualEnd":812253600,"title":"Commute","stepsTotal":0,"categoryID":"personal","id":"p1"}]}]"#
        let list = try JSONDecoder().decode([DayRecord].self, from: Data(json.utf8))
        XCTAssertEqual(list.first?.entries.first?.hours ?? 0, 0.75, accuracy: 0.001)
    }
}
