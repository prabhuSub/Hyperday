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

struct DayActivityAttributes: ActivityAttributes {
    /// Everything the Lock Screen card and Dynamic Island render.
    /// Kept small: ActivityKit caps the payload at 4 KB.
    struct ContentState: Codable, Hashable {
        var label: String            // "Next · Lunch at 12:30 PM"
        var title: String            // "Deep Work — ORBIT AI" / "Free until 12:30 PM"
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
        // v16: start of the live block, so the Island ring fills across this block.
        var currentStart: Date?
    }

    var dayStart: Date
}
