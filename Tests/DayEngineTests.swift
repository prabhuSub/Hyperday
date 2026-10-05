import XCTest
@testable import DayLive

/// Core-logic tests. Run with ⌘U in Xcode (a simulator is fine). No calendar or phone data is touched.
final class DayEngineTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var day = cal.date(from: DateComponents(year: 2026, month: 10, day: 6))!   // a Tuesday
    private func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }
    private func block(_ id: String, _ s: Date, _ e: Date) -> Block {
        Block(id: id, title: id, start: s, end: e, source: .plan)
    }

    // MARK: What's on now

    func testCurrentAndNext() {
        let a = block("plan-a", at(10), at(11)), b = block("plan-b", at(12), at(13))
        let snap = DayEngine.snapshot(of: [a, b], overrides: [:], now: at(10, 30))
        XCTAssertEqual(snap.current?.id, "plan-a")
        XCTAssertEqual(snap.next?.id, "plan-b")
        XCTAssertFalse(snap.overtime)
    }

    func testFreeTimeBetweenBlocks() {
        let a = block("plan-a", at(10), at(11)), b = block("plan-b", at(12), at(13))
        let snap = DayEngine.snapshot(of: [a, b], overrides: [:], now: at(11, 30))
        XCTAssertNil(snap.current)
        XCTAssertEqual(snap.next?.id, "plan-b")
    }

    func testOverlapShowsAsAlso() {
        let a = block("plan-a", at(10), at(11)), c = block("plan-c", at(10, 30), at(10, 45))
        let snap = DayEngine.snapshot(of: [a, c], overrides: [:], now: at(10, 35))
        XCTAssertEqual(snap.current?.id, "plan-a")
        XCTAssertEqual(snap.also?.id, "plan-c")
    }

    func testDayEndsWhenEverythingIsOver() {
        let a = block("plan-a", at(10), at(11))
        let snap = DayEngine.snapshot(of: [a], overrides: [:], now: at(18))
        XCTAssertNil(snap.current)
        XCTAssertNil(snap.next)
        XCTAssertFalse(snap.hasAnythingLeft)
    }

    // MARK: Overrides: Done, Start, Pause

    func testDoneEarlyEndsTheBlock() {
        let a = block("plan-a", at(10), at(11))
        let out = DayEngine.apply(["plan-a": BlockOverride(end: at(10, 40))], to: [a], now: at(10, 45))
        XCTAssertEqual(out.first?.end, at(10, 40))
    }

    func testStartLateRunsForThePlannedLength() {
        let a = block("plan-a", at(10), at(11))
        let out = DayEngine.apply(["plan-a": BlockOverride(start: at(10, 15), started: true)], to: [a], now: at(10, 20))
        XCTAssertEqual(out.first?.start, at(10, 15))
        XCTAssertEqual(out.first?.end, at(11, 15))
    }

    func testPauseMovesTheEndWhilePaused() {
        let a = block("plan-a", at(10), at(11))
        let o = BlockOverride(pausedAt: at(10, 20))
        let out = DayEngine.apply(["plan-a": o], to: [a], now: at(10, 50))
        XCTAssertEqual(out.first?.end, at(11, 30), "30 paused minutes push the end 30 minutes later")
    }

    func testResumeKeepsThePausedTime() {
        let a = block("plan-a", at(10), at(11))
        let o = BlockOverride(pausedTotal: 600)
        let out = DayEngine.apply(["plan-a": o], to: [a], now: at(10, 50))
        XCTAssertEqual(out.first?.end, at(11, 10))
    }

    func testZeroLengthBlocksAreDropped() {
        let a = block("plan-a", at(10), at(10))
        XCTAssertTrue(DayEngine.apply([:], to: [a], now: at(10)).isEmpty)
    }

    // MARK: Data safety

    func testMissingFileIsFine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hd-missing-\(UUID()).json")
        guard case .missing = SafeFile.load([Block].self, from: url) else { return XCTFail("expected .missing") }
    }

    func testCorruptFileIsKeptNotWiped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hd-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("store.json")
        try Data("{not json".utf8).write(to: url)
        guard case .unreadable = SafeFile.load([Block].self, from: url) else { return XCTFail("expected .unreadable") }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("store.bad-") }, "a .bad copy is kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the original is untouched")
    }

    func testOldBlockWithoutNewFieldsStillLoads() throws {
        let json = #"[{"id":"plan-a","title":"A","start":0,"end":3600,"source":"plan"}]"#
        let list = try JSONDecoder().decode([Block].self, from: Data(json.utf8))
        XCTAssertEqual(list.first?.declined, false)
    }

    // MARK: Edge ticks geometry

    func testTicksStartAtTopCentre() {
        let (p, n) = EdgeTicks.point(0, in: CGSize(width: 300, height: 120), r: 22, inset: 3)
        XCTAssertEqual(p.x, 150, accuracy: 0.5)
        XCTAssertEqual(p.y, 3, accuracy: 0.5)
        XCTAssertEqual(n.dy, 1, accuracy: 0.01, "first tick points down into the card")
    }
}
