import Foundation

/// One block of the day: a calendar event or something you planned in Hyperday.
struct Block: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var source: BlockSource
    var calendarName: String? = nil   // e.g. "Tesla" (calendar events only; used by category rules)
    var declined: Bool = false        // you declined this calendar invite
    var location: String? = nil       // calendar event location (Drive card uses it for the arrival time)

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func contains(_ date: Date) -> Bool { start <= date && date < end }
}

/// A checklist item inside a block. Checked steps fill the green bar on the Live Activity.
struct Step: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var done: Bool = false
}

/// Done / Start next never edits your calendar. It records an override instead.
struct BlockOverride: Codable, Hashable {
    var start: Date?
    var end: Date?
    /// Tapped Start: the block runs from `start` for its planned length (can be later than planned),
    /// and keeps going as overtime until Done.
    var started: Bool? = nil
    /// v20 Pause: while paused the block's end keeps moving later; on Resume the pause is banked.
    var pausedAt: Date? = nil
    var pausedTotal: TimeInterval? = nil
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

extension TimeInterval {
    /// 5400 -> "1h 30m"
    var hoursMinutes: String {
        let m = max(0, Int((self / 60).rounded()))
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r)m" }
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }
}


// MARK: - Data safety (v24)

/// Reads a save file without ever letting a bad read wipe it.
/// - no file → `.missing` (fresh install, fine to start empty and save)
/// - can't read yet (iPhone locked after reboot) → `.unavailable`: don't save, try again later
/// - read but can't decode (older/newer format) → a copy is kept as `name.bad-<time>.json`, `.unreadable`: don't save
enum SafeFile {
    enum Result<T> { case loaded(T), missing, unavailable, unreadable }

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> Result<T> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unavailable }
        do {
            return .loaded(try JSONDecoder().decode(T.self, from: data))
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let copy = url.deletingPathExtension().appendingPathExtension("bad-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: copy)
            return .unreadable
        }
    }
}

/// Fields added after v1 decode with their defaults, so an older file still loads.
extension Block {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        source = try c.decode(BlockSource.self, forKey: .source)
        calendarName = try c.decodeIfPresent(String.self, forKey: .calendarName)
        declined = try c.decodeIfPresent(Bool.self, forKey: .declined) ?? false
        location = try c.decodeIfPresent(String.self, forKey: .location)
    }
}
