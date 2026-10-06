import Combine
import Foundation

/// Your planned blocks + Done/Start-next overrides, saved as JSON in the app's Documents folder.
/// (No App Group needed: the widget only renders ContentState; intents run in the app process.)
@MainActor
final class BlockStore: ObservableObject {
    static let shared = BlockStore()

    @Published private(set) var planBlocks: [Block] = []
    @Published private(set) var overrides: [String: BlockOverride] = [:]
    /// Steps per block id (plan blocks and calendar events alike).
    @Published private(set) var steps: [String: [Step]] = [:]
    /// Manual category per block id; beats the auto rules.
    @Published private(set) var categoryOverrides: [String: String] = [:]
    /// Extra categories after the first (the first one, in categoryOverrides, sets the color).
    @Published private(set) var extraCategories: [String: [String]] = [:]

    private struct Snapshot: Codable {
        var planBlocks: [Block]
        var overrides: [String: BlockOverride]
        var steps: [String: [Step]]?   // optional so files saved before steps existed still load
        var categoryOverrides: [String: String]?
        var extraCategories: [String: [String]]?
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("daylive-store.json")
    }()

    private init() {
        load()
        pruneOld()
    }

    // MARK: Plan blocks

    @discardableResult
    func add(title: String, start: Date, minutes: Int, categoryID: String? = nil, categoryIDs: [String] = []) -> String? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, minutes > 0 else { return nil }
        let block = Block(
            id: "plan-" + UUID().uuidString,
            title: clean,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            source: .plan
        )
        planBlocks.append(block)
        planBlocks.sort { $0.start < $1.start }
        if let categoryID { categoryOverrides[block.id] = categoryID }
        if !categoryIDs.isEmpty { applyCategories(categoryIDs, for: block.id) }
        save()
        return block.id
    }

    func delete(id: String) {
        PhotoStore.shared.removeAll(for: id)   // v36: a deleted block's photos go with it
        planBlocks.removeAll { $0.id == id }
        overrides[id] = nil
        steps[id] = nil
        categoryOverrides[id] = nil
        extraCategories[id] = nil
        save()
    }

    /// nil = back to automatic (rules).
    func setCategory(_ categoryID: String?, for blockID: String) {
        categoryOverrides[blockID] = categoryID
        extraCategories[blockID] = nil
        save()
    }

    /// Manual categories in the order picked (first sets the color). Empty = automatic.
    func manualCategoryIDs(for blockID: String) -> [String] {
        guard let first = categoryOverrides[blockID] else { return [] }
        return [first] + (extraCategories[blockID] ?? [])
    }

    func setCategories(_ ids: [String], for blockID: String) {
        applyCategories(ids, for: blockID)
        save()
    }

    private func applyCategories(_ ids: [String], for blockID: String) {
        var seen = Set<String>()
        let unique = ids.filter { seen.insert($0).inserted }
        categoryOverrides[blockID] = unique.first
        extraCategories[blockID] = unique.count > 1 ? Array(unique.dropFirst()) : nil
    }

    /// Move a planned block to the same time on another day (default: the next day). Steps and categories come along.
    func move(id: String, byDays days: Int = 1) {
        guard let i = planBlocks.firstIndex(where: { $0.id == id }),
              let s = Calendar.current.date(byAdding: .day, value: days, to: planBlocks[i].start),
              let e = Calendar.current.date(byAdding: .day, value: days, to: planBlocks[i].end) else { return }
        planBlocks[i].start = s
        planBlocks[i].end = e
        planBlocks.sort { $0.start < $1.start }
        overrides[id] = nil
        save()
    }

    // MARK: Demo data

    static let demoPrefix = "plan-demo-"

    func addDemo(blocks: [Block], steps demoSteps: [String: [Step]], categories: [String: String], finished: [String: Date]) {
        planBlocks.removeAll { $0.id.hasPrefix(Self.demoPrefix) }
        planBlocks.append(contentsOf: blocks)
        planBlocks.sort { $0.start < $1.start }
        for (k, v) in demoSteps { steps[k] = v }
        for (k, v) in categories { categoryOverrides[k] = v }
        for (k, v) in finished { overrides[k] = BlockOverride(start: nil, end: v) }
        save()
    }

    func removeDemo() {
        planBlocks.removeAll { $0.id.hasPrefix(Self.demoPrefix) }
        steps = steps.filter { !$0.key.hasPrefix(Self.demoPrefix) }
        categoryOverrides = categoryOverrides.filter { !$0.key.hasPrefix(Self.demoPrefix) }
        extraCategories = extraCategories.filter { !$0.key.hasPrefix(Self.demoPrefix) }
        overrides = overrides.filter { !$0.key.hasPrefix(Self.demoPrefix) }
        save()
    }

    /// Edit a planned block. Clears Done/Start-next overrides so the new times take effect.
    func update(id: String, title: String, start: Date, minutes: Int) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = planBlocks.firstIndex(where: { $0.id == id }), !clean.isEmpty, minutes > 0 else { return }
        let newEnd = start.addingTimeInterval(TimeInterval(minutes * 60))
        // Only a change of time resets Done / Start / Pause; fixing a typo keeps them.
        let timesChanged = abs(planBlocks[i].start.timeIntervalSince(start)) >= 60
            || abs(planBlocks[i].end.timeIntervalSince(newEnd)) >= 60
        planBlocks[i].title = clean
        planBlocks[i].start = start
        planBlocks[i].end = newEnd
        planBlocks.sort { $0.start < $1.start }
        if timesChanged { overrides[id] = nil }
        save()
    }

    /// v32 Extend: push a Hyperday block's planned end later. Keeps Start/Pause state, so a running
    /// timer just gets longer. Calendar events are never edited.
    func extend(id: String, by minutes: Int) {
        guard minutes > 0, let i = planBlocks.firstIndex(where: { $0.id == id }) else { return }
        planBlocks[i].end = planBlocks[i].end.addingTimeInterval(TimeInterval(minutes * 60))
        save()
    }

    // MARK: Steps

    func steps(for blockID: String) -> [Step] { steps[blockID] ?? [] }

    func setSteps(_ list: [Step], for blockID: String) {
        let cleaned = list
            .map { Step(id: $0.id, title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), done: $0.done) }
            .filter { !$0.title.isEmpty }
        steps[blockID] = cleaned.isEmpty ? nil : cleaned
        save()
    }

    func toggleStep(blockID: String, stepID: String) {
        guard var list = steps[blockID], let i = list.firstIndex(where: { $0.id == stepID }) else { return }
        list[i].done.toggle()
        steps[blockID] = list
        save()
    }

    /// Lock Screen button: check the first unchecked step.
    func checkNextStep(blockID: String) {
        guard var list = steps[blockID], let i = list.firstIndex(where: { !$0.done }) else { return }
        list[i].done = true
        steps[blockID] = list
        save()
    }

    func planBlocks(on day: Date) -> [Block] {
        // Any block that overlaps the day (an 11 PM–1 AM block shows on both days).
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return planBlocks.filter { $0.start < dayEnd && $0.end > dayStart }
    }

    // MARK: Overrides (Done / Start next)

    func finish(blockID: String, at date: Date) {
        var o = overrides[blockID] ?? BlockOverride()
        if let p = o.pausedAt { o.pausedTotal = (o.pausedTotal ?? 0) + max(0, date.timeIntervalSince(p)); o.pausedAt = nil }
        o.end = date
        overrides[blockID] = o
        save()
    }

    /// Start button: the timer runs from now for the block's planned length, then shows overtime until Done.
    func start(blockID: String, at date: Date) {
        overrides[blockID] = BlockOverride(start: date, end: nil, started: true)
        save()
    }

    /// v20 Pause / Resume from the Live Activity (your own planned blocks only).
    func pause(blockID: String, at date: Date) {
        var o = overrides[blockID] ?? BlockOverride()
        guard o.pausedAt == nil else { return }
        o.pausedAt = date
        overrides[blockID] = o
        save()
    }

    func resume(blockID: String, at date: Date) {
        guard var o = overrides[blockID], let p = o.pausedAt else { return }
        o.pausedTotal = (o.pausedTotal ?? 0) + max(0, date.timeIntervalSince(p))
        o.pausedAt = nil
        overrides[blockID] = o
        save()
    }

    func isPaused(_ blockID: String) -> Bool { overrides[blockID]?.pausedAt != nil }

    // MARK: Persistence

    private func pruneOld() {
        // Keep two years of your tasks so the Calendar tab can look back at any past day.
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -730, to: .now) else { return }
        let before = planBlocks.count
        let overridesBefore = overrides.count
        planBlocks.removeAll { $0.end < cutoff }
        // Calendar-event overrides carry the event start in their id; plan ones are cleaned with their block.
        let liveIDs = Set(planBlocks.map(\.id))
        overrides = overrides.filter { key, _ in
            key.hasPrefix("plan-") ? liveIDs.contains(key) : true
        }
        steps = steps.filter { key, _ in
            key.hasPrefix("plan-") ? liveIDs.contains(key) : true
        }
        categoryOverrides = categoryOverrides.filter { key, _ in
            key.hasPrefix("plan-") ? liveIDs.contains(key) : true
        }
        extraCategories = extraCategories.filter { key, _ in
            key.hasPrefix("plan-") ? liveIDs.contains(key) : true
        }
        // Calendar overrides ("cal-<event>-<timestamp>") older than 2 years go; never clear everything.
        let calCutoff = cutoff.timeIntervalSince1970
        overrides = overrides.filter { key, _ in
            guard key.hasPrefix("cal-"), let ts = key.split(separator: "-").last.flatMap({ Double($0) }) else { return true }
            return ts > calCutoff
        }
        if planBlocks.count != before || overrides.count != overridesBefore { save() }
    }

    /// True when the file couldn't be read or decoded: saving is off so it is never overwritten.
    private var loadBlocked = false

    func retryLoadIfNeeded() { if loadBlocked { load() } }
    func reloadFromDisk() { load() }   // after a restore

    private func load() {
        let snap: Snapshot
        switch SafeFile.load(Snapshot.self, from: fileURL) {
        case .loaded(let s): snap = s; loadBlocked = false
        case .missing: loadBlocked = false; return
        case .unavailable, .unreadable: loadBlocked = true; return
        }
        planBlocks = snap.planBlocks
        overrides = snap.overrides
        steps = snap.steps ?? [:]
        categoryOverrides = snap.categoryOverrides ?? [:]
        extraCategories = snap.extraCategories ?? [:]
    }

    private func save() {
        guard !loadBlocked else { return }
        let snap = Snapshot(planBlocks: planBlocks, overrides: overrides, steps: steps,
                            categoryOverrides: categoryOverrides, extraCategories: extraCategories)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
