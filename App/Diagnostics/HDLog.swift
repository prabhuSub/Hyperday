import Foundation
import os

/// v52 reliability logging. Two outputs:
/// 1. Unified log (Console.app, filter subsystem "com.prabhu.daylive") with signposts for Instruments.
/// 2. A small local file, Documents/diagnostics.jsonl (last ~1500 lines, never uploaded), so a 7-day run
///    can be checked afterwards with tools/diag_check.py. No titles or personal text are written.
enum HDLog {
    static let subsystem = "com.prabhu.daylive"
    static let live = Logger(subsystem: subsystem, category: "live")
    static let bg = Logger(subsystem: subsystem, category: "background")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    private static let queue = DispatchQueue(label: "hd.diag", qos: .utility)
    private static let maxLines = 1500
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("diagnostics.jsonl")
    }

    /// One event line: {"t": unix seconds, "ev": name, ...fields}. Fields must be non-personal.
    static func event(_ ev: String, _ fields: [String: Any] = [:]) {
        var obj = fields
        obj["t"] = Date.now.timeIntervalSince1970
        obj["ev"] = ev
        queue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                try? Data().write(to: url, options: [.completeFileProtectionUntilFirstUserAuthentication])
                var u = url; var rv = URLResourceValues(); rv.isExcludedFromBackup = true; try? u.setResourceValues(rv)
            }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            trimIfNeeded()
        }
    }

    private static var writes = 0
    private static func trimIfNeeded() {
        writes += 1
        guard writes % 100 == 0, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxLines else { return }
        try? (lines.suffix(maxLines).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
