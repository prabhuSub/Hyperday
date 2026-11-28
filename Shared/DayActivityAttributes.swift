import ActivityKit
import Foundation

/// Where a block came from. Drives the source icon on the card.
enum BlockSource: String, Codable, Hashable {
    case calendar   // iOS Calendar (incl. the Tesla calendar)
    case plan       // added in Hyperday
    case free       // gap between blocks
}

/// What the card's single button does.
enum BlockAction: String, Codable, Hashable {
    case done       // finish the current block early
    case startNext  // in a free gap: start the next block now
    case checkStep  // current block has steps: check the next unchecked one
}

/// One block on the journey track (positions as 0…1 of the day window, color as hex).
struct TrackSeg: Codable, Hashable {
    var s: Double
    var e: Double
    var hex: String
}

/// v65: one live job on a Mac, for the Live Activity board.
struct MacJob: Codable, Hashable {
    var label: String
    var since: Date
    var waiting: Bool
}

/// v61: one Mac from JobTrail (MacBook Pro / Mac mini), as the Live Activity shows it.
struct MacLive: Codable, Hashable {
    var id: String? = nil     // JobTrail machine id ("local" / "remote"), v64
    var name: String          // "MacBook Pro"
    var desktop: Bool         // Mac mini → desktop glyph
    var online: Bool
    var running: Int
    var waiting: Int
    var gpu: Int?             // %
    var mem: Int?             // % used (v63)
    var top: String?          // label of the newest running (else waiting) job
    var topSince: Date?       // when it started: the card counts up from here by itself
    var topWaiting: Bool?
    // v65: the "day done" board
    var battery: Int?         // % (MacBook only)
    var charging: Bool?
    var gpuHist: [Int]?       // last ~20 GPU readings, oldest first
    var jobs: [MacJob]?       // up to 3 live jobs, running first
    // v75 vitals (JobTrail's jtvitals): CPU %, chip °C (average), fastest fan rpm, when it went offline
    var cpu: Int? = nil
    var temp: Int? = nil
    var fan: Int? = nil
    var downSince: Date? = nil

    /// Green running, amber waiting, red offline, grey idle.
    var statusRaw: String { !online ? "failed" : running > 0 ? "running" : waiting > 0 ? "waiting" : "idle" }

    /// v75: something you should act on — battery under 20% and not charging, or the Mac mini gone for 3+ minutes
    /// (it has no battery, so that means power or network loss). nil when all is well.
    func alert(now: Date = .now) -> String? {
        if online, let b = battery, b < 20, charging != true { return "\(desktop ? "Mac mini" : "MacBook") battery \(b)% · plug it in" }
        if !online, desktop, let d = downSince, now.timeIntervalSince(d) >= 180 { return "Mac mini lost power or network · \(Int(now.timeIntervalSince(d) / 60)) min" }
        return nil
    }
}

extension Array where Element == MacLive {
    /// v75: the first alert across the Macs (for the warning row on the Live Activity).
    func alert(now: Date = .now) -> String? { lazy.compactMap { $0.alert(now: now) }.first }
}

struct DayActivityAttributes: ActivityAttributes {
    /// Everything the Lock Screen card and Dynamic Island render.
    /// Kept small: ActivityKit caps the payload at 4 KB.
    struct ContentState: Codable, Hashable {
        var label: String            // "Next · Lunch at 12:30 PM"
        var title: String            // "Deep Work — Launch plan" / "Free until 12:30 PM"
        var also: String?            // "also: Standup · 10:00 AM–10:15 AM"
        var source: BlockSource
        var segments: [Double]       // 0...1 fill per block in the day bar
        var dayProgress: Double      // 0...1 for the Island ring
        var currentEnd: Date?        // drives the countdown in the expanded Island
        var actionBlockID: String?
        var action: BlockAction?
        var stepsDone: Int?          // set when the current block has steps
        var stepsTotal: Int?
        var accentHex: String?       // live block's category color, e.g. "#30D158"
        var alsoIsStep: Bool?        // true when the second line is the next step (drawn as a grey pill)
        var freeStart: Date?         // free time: when the gap began (bar fills from here…
        var nextStart: Date?         // …to here, the next block's start)
        var nextTitle: String?       // free time: "Standup"
        var overSince: Date?         // started block past its planned end: counts up from here
        var iconName: String?        // category icon of the live block ("deepwork")
        // Day Close (v9): after your close time the card becomes "Day closed".
        var closed: Bool?
        var doneCount: Int?
        var totalCount: Int?
        var tomorrowFirst: Date?
        var tomorrowTitle: String?
        var leaveBy: Date?
        var bedBy: Date?
        var reviewCount: Int?        // unfinished blocks still to review (0 after "Close the day")
        // Drive card (#9): while your car is connected.
        var driving: Bool?
        var driveSince: Date?
        var arriveAt: Date?
        var spareMinutes: Int?       // minutes before the next block starts (negative = late)
        // v20: last-5-minutes heads-up (shown when the card goes stale at headsUpAt), pause, today score.
        var headsUpAt: Date?
        var headsUp: String?         // "Next: Standup 3:00 PM · Room 3B"
        var paused: Bool?
        var pausedLeft: Double?      // seconds left when paused (timer frozen)
        var focusMinutes: Int?       // Work + Deep Work so far today
        var canPause: Bool?          // your own planned block is running
        // v21: when the content really changes. The card can also go stale earlier on purpose
        // (heads-up, or the Island switching from "20h" to a live timer), which isn't "out of date".
        var boundaryAt: Date?
        // v23: the end-of-block band ("Standup in 4:59 · Room 3B") in the next block's color.
        var headsNextTitle: String?
        var headsNextStart: Date?
        var headsNextPlace: String?
        var headsNextHex: String?
        // v24 journey card: today's blocks as colored segments on one track, plus the next block's look.
        var track: [TrackSeg]?
        var trackFrom: Date?
        var trackTo: Date?
        var nextHex: String?
        var nextIcon: String?
        // v24 C (free time) "Later" capsule, and D (day closed) focus by hour 6 AM–10 PM.
        var laterTitle: String?
        var laterStart: Date?
        var laterHex: String?
        var nextEnd: Date?           // C: capsule widths follow real durations
        var laterEnd: Date?
        var focusByHour: [Double]?   // minutes of focus in each hour
        // v16: start of the live block, so the Island ring fills across this block.
        var currentStart: Date?
        // v61: your Macs from JobTrail (MacBook Pro, Mac mini).
        var macs: [MacLive]?
        var macsUpdated: Date?       // v68: when JobTrail was last read (shown next to ↻)
    }

    var dayStart: Date
}
