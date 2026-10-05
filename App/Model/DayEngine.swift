import Foundation

/// Pure logic: blocks + overrides + "now" -> what the card shows. No iOS APIs, easy to unit-test.
struct DaySnapshot {
    var all: [Block]          // every block today, overrides applied, sorted
    var current: Block?       // main title
    var also: Block?          // overlapping block ("also:" line)
    var next: Block?
    var lanes: [Block]        // non-overlapping blocks = segments in the bar
    var segments: [Double]
    var dayProgress: Double
    var currentSteps: [Step] = []   // checklist of the current block (drives the bar when non-empty)
    var accentHex: String?          // category color of the current block (set by LiveActivityManager)
    var iconName: String?           // category icon of the current block (set by LiveActivityManager)
    var overtime = false            // current block was started and is past its planned end
    var startedAt: Date?            // current block was started by tapping Start
    var freeStart: Date?            // no block now: when the free time began

    /// Next moment the card's content changes. Used as staleDate + background refresh time.
    var nextBoundary: Date? {
        if overtime, let c = current {
            return [c.end.addingTimeInterval(DayEngine.maxOvertime), next?.start].compactMap { $0 }.min()
        }
        return [current?.end, also?.end, next?.start].compactMap { $0 }.min()
    }

    var hasAnythingLeft: Bool { current != nil || next != nil }

    func contentState() -> DayActivityAttributes.ContentState {
        let label = next.map { "Next · \($0.title) at \($0.start.shortTime)" }
            ?? (all.isEmpty ? "Add a block in Hyperday" : "Nothing else today")

        var title = all.isEmpty ? "Nothing planned" : "Day complete"
        var source = BlockSource.free
        var actionID: String?
        var action: BlockAction?

        var bar = segments
        var stepsDone: Int?
        var stepsTotal: Int?
        var nextStepLine: String?

        var extraLine: String?
        if let c = current {
            title = c.title
            source = c.source
            actionID = c.id
            action = .done
            if overtime {
                extraLine = "Planned until \(c.end.shortTime)"
            } else if let s = startedAt {
                extraLine = "Started \(s.shortTime) · ends \(c.end.shortTime)"
            }
            if !currentSteps.isEmpty && !overtime {
                // Steps rule: the bar becomes this block's checklist; the button checks the next step.
                let done = currentSteps.filter(\.done).count
                bar = currentSteps.map { $0.done ? 1 : 0 }
                stepsDone = done
                stepsTotal = currentSteps.count
                if let nextStep = currentSteps.first(where: { !$0.done }) {
                    action = .checkStep
                    nextStepLine = "→ \(nextStep.title)"
                } else {
                    nextStepLine = "All \(currentSteps.count) steps done"
                }
            }
        } else if let n = next {
            title = "Free"   // no button in free time; the next block starts on its own
            let whereText = n.source == .calendar ? (n.calendarName ?? "Calendar") : "My plan"
            extraLine = "Next: \(n.title) \(n.start.shortTime) · \(whereText)"
        }

        return .init(
            label: label,
            title: title,
            // Overlap wins the second line; otherwise show the next step.
            also: also.map { "also: \($0.title) · \($0.start.shortTime)–\($0.end.shortTime)" } ?? nextStepLine ?? extraLine,
            source: source,
            segments: bar,
            dayProgress: dayProgress,
            currentEnd: overtime ? nil : current?.end,
            actionBlockID: actionID,
            action: action,
            stepsDone: stepsDone,
            stepsTotal: stepsTotal,
            accentHex: current == nil ? nil : accentHex,
            alsoIsStep: also == nil && nextStepLine != nil,
            freeStart: current == nil && next != nil ? freeStart : nil,
            nextStart: current == nil ? next?.start : nil,
            nextTitle: current == nil ? next?.title : nil,
            overSince: overtime ? current?.end : nil,
            iconName: current == nil ? nil : iconName,
            currentStart: current?.start
        )
    }
}

enum DayEngine {
    /// A started block keeps showing as overtime for at most this long after its planned end.
    static let maxOvertime: TimeInterval = 3600

    static func snapshot(
        of raw: [Block],
        overrides: [String: BlockOverride],
        steps: [String: [Step]] = [:],
        now: Date
    ) -> DaySnapshot {
        let blocks = apply(overrides, to: raw, now: now).sorted {
            $0.start == $1.start ? $0.duration > $1.duration : $0.start < $1.start
        }

        // Overlap rule ("show both"): the block that started first is the title, the other is "also:".
        let active = blocks.filter { $0.contains(now) }
        var current = active.first
        let also = active.dropFirst().first
        let next = blocks.first { $0.start > now }

        // Overtime: you tapped Start, the planned length is up, and you haven't tapped Done yet.
        var overtime = false
        if current == nil {
            let candidate = blocks.last(where: { b in
                guard let o = overrides[b.id], o.started == true, o.end == nil else { return false }
                return b.end <= now && now < b.end.addingTimeInterval(maxOvertime)
            })
            if let c = candidate, next.map({ now < $0.start }) ?? true {
                current = c
                overtime = true
            }
        }
        let startedAt = current.flatMap { overrides[$0.id]?.started == true ? $0.start : nil }

        // Free time starts when the last block before now ended (or 6 AM if nothing yet today).
        let dayStart = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: now)
            ?? Calendar.current.startOfDay(for: now).addingTimeInterval(6 * 3600)   // 6 AM even on DST days
        let lastEnd = blocks.filter { $0.end <= now }.map(\.end).max()
        let freeStart = min(lastEnd ?? min(dayStart, now), now)

        // Bar segments: greedy non-overlapping lanes, so overlaps don't double up.
        var lanes: [Block] = []
        for b in blocks {
            if let last = lanes.last, b.start < last.end { continue }
            lanes.append(b)
        }

        var dayProgress = 0.0
        if let first = blocks.first?.start, let last = blocks.map(\.end).max(), last > first {
            dayProgress = clamp(now.timeIntervalSince(first) / last.timeIntervalSince(first))
        }

        return DaySnapshot(
            all: blocks,
            current: current,
            also: also,
            next: next,
            lanes: lanes,
            segments: lanes.map { progress(of: $0, at: now) },
            dayProgress: dayProgress,
            currentSteps: current.map { steps[$0.id] ?? [] } ?? [],
            overtime: overtime,
            startedAt: startedAt,
            freeStart: freeStart
        )
    }

    static func apply(_ overrides: [String: BlockOverride], to blocks: [Block], now: Date = .now) -> [Block] {
        blocks.compactMap { original in
            var b = original
            if let o = overrides[b.id] {
                if o.started == true, let s = o.start {
                    // Timer runs from the tap for the planned length.
                    b.start = s
                    b.end = s.addingTimeInterval(original.duration)
                } else if let s = o.start {
                    b.start = min(b.start, s)
                }
                // Pause: the end moves later by every paused minute (including the one running now).
                let paused = (o.pausedTotal ?? 0) + (o.pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
                if paused > 0 { b.end = b.end.addingTimeInterval(paused) }
                if let e = o.end { b.end = min(b.end, e) }
            }
            return b.end > b.start ? b : nil
        }
    }

    static func progress(of b: Block, at now: Date) -> Double {
        if now >= b.end { return 1 }
        if now <= b.start { return 0 }
        return clamp(now.timeIntervalSince(b.start) / b.duration)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
