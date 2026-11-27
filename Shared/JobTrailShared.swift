import Foundation
import WidgetKit

// v64: JobTrail data shared by the app, the Live Activity and the Macs widgets.
// Both the app and the widget extension can read JobTrail themselves (over Tailscale, with the key
// from their Info.plist). Every read is kept in the App Group with a rolling GPU / memory history,
// so the widgets can draw graphs even when the Mac can't be reached for a while.

/// One JobTrail job (live or finished in the last 24 h).
struct JTJob: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var machine: String       // "local" / "remote"
    var state: String         // running / waiting / done / failed / ended
    var startedAt: Date
    var endedAt: Date?
    var cpu: Double?
}

/// GPU and memory (% used) per machine id at one moment.
struct JTSample: Codable, Hashable {
    var t: Date
    var gpu: [String: Int]
    var mem: [String: Int]
}

struct JTSnapshot: Codable, Equatable {
    var updated: Date
    var reachable: Bool
    var macs: [MacLive]
    var live: [JTJob]
    var recent: [JTJob]       // finished in the last 24 h (newest first)
    var samples: [JTSample]   // oldest first, ≤ 24 h

    static let empty = JTSnapshot(updated: .distantPast, reachable: false, macs: [], live: [], recent: [], samples: [])

    /// Live jobs (not services) on one Mac.
    func jobs(on id: String?) -> [JTJob] { live.filter { $0.machine == id } }

    /// GPU or MEM series for a Mac over the last `hours`.
    func series(_ id: String?, gpu: Bool, hours: Double, now: Date = .now) -> [Double] {
        guard let id else { return [] }
        let from = now.addingTimeInterval(-hours * 3600)
        return samples.filter { $0.t >= from }.compactMap { (gpu ? $0.gpu : $0.mem)[id].map(Double.init) }
    }

    /// Jobs started per hour for the last 24 h: [(done, failed, running)] oldest → newest.
    func hourly(now: Date = .now) -> [(done: Int, failed: Int, running: Int)] {
        let cal = Calendar.current
        let thisHour = cal.dateInterval(of: .hour, for: now)?.start ?? now
        var out = Array(repeating: (done: 0, failed: 0, running: 0), count: 24)
        for j in recent + live {
            let h = Int(thisHour.timeIntervalSince(cal.dateInterval(of: .hour, for: j.startedAt)?.start ?? j.startedAt) / 3600)
            guard h >= 0 && h < 24 else { continue }
            let i = 23 - h
            switch j.state {
            case "running", "waiting": out[i].running += 1
            case "failed": out[i].failed += 1
            default: out[i].done += 1
            }
        }
        return out
    }
}

enum JTStore {
    static let kind = "HyperdayMacs"
    static let lockKind = "HyperdayMacsLock"

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroup)?
            .appendingPathComponent("widget-jobtrail.json")
    }

    static func load() -> JTSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(JTSnapshot.self, from: data)
    }

    static func save(_ s: JTSnapshot) {
        guard let url else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        if let data = try? e.encode(s) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: Network (used by the widget extension; the app has its own loop in JobTrailLive)

    static var key: String { (Bundle.main.object(forInfoDictionaryKey: "JTKey") as? String ?? "").trimmingCharacters(in: .whitespaces) }
    static var hosts: [String] {
        (Bundle.main.object(forInfoDictionaryKey: "JTHosts") as? String ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func get(_ path: String, host: String, timeout: Double = 6) async -> Any? {
        guard let u = URL(string: "http://\(host):4791\(path)") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        req.setValue(key, forHTTPHeaderField: "x-jobtrail-key")
        guard let (data, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// One full read (state + 24 h history), merged into what's saved. Returns the saved snapshot.
    @discardableResult
    static func refresh(withHistory: Bool = true) async -> JTSnapshot {
        let prev = load() ?? .empty
        guard !key.isEmpty else { return prev }
        for h in hosts {
            guard let state = await get("/api/state", host: h) as? [String: Any] else { continue }
            let hist = withHistory ? await get("/api/history?days=1", host: h, timeout: 8) as? [[String: Any]] : nil
            let snap = merge(prev: prev, state: state, history: hist)
            save(snap)
            return snap
        }
        var s = prev
        s.reachable = false
        save(s)
        return s
    }

    // MARK: Parsing (shared by app + widget)

    static func job(_ j: [String: Any]) -> JTJob? {
        guard let started = j["startedAt"] as? Double else { return nil }
        return JTJob(id: j["id"] as? String ?? UUID().uuidString,
                     label: j["label"] as? String ?? "job",
                     machine: j["machine"] as? String ?? "local",
                     state: j["state"] as? String ?? "running",
                     startedAt: Date(timeIntervalSince1970: started / 1000),
                     endedAt: (j["endedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                     cpu: j["cpu"] as? Double)
    }

    static func macs(from state: [String: Any]) -> [MacLive] {
        let machines = state["machines"] as? [[String: Any]] ?? []
        let live = (state["live"] as? [[String: Any]] ?? []).filter { ($0["kind"] as? String ?? "job") == "job" }
        return machines.map { m in
            let id = m["id"] as? String ?? ""
            let jobs = live.filter { ($0["machine"] as? String) == id }
            let run = jobs.filter { ($0["state"] as? String) == "running" }
            let wait = jobs.filter { ($0["state"] as? String) == "waiting" }
            let newest = { (l: [[String: Any]]) in l.max { ($0["startedAt"] as? Double ?? 0) < ($1["startedAt"] as? Double ?? 0) } }
            let top = newest(run) ?? newest(wait)
            let byNew = { (l: [[String: Any]]) in l.sorted { ($0["startedAt"] as? Double ?? 0) > ($1["startedAt"] as? Double ?? 0) } }
            let list = (byNew(run) + byNew(wait)).prefix(3).compactMap { j -> MacJob? in
                guard let s = j["startedAt"] as? Double else { return nil }
                return MacJob(label: MacRowItem.short(j["label"] as? String ?? "job"),
                              since: Date(timeIntervalSince1970: s / 1000), waiting: (j["state"] as? String) == "waiting")
            }
            let vit = m["vitals"] as? [String: Any] ?? [:]
            return MacLive(
                id: id,
                name: m["name"] as? String ?? id,
                desktop: (m["device"] as? String) == "desktop",
                online: m["online"] as? Bool ?? false,
                running: run.count, waiting: wait.count,
                gpu: (m["gpu"] as? Double).map { Int($0.rounded()) },
                mem: (m["memFree"] as? Double).map { max(0, 100 - Int($0.rounded())) },
                top: top.flatMap { $0["label"] as? String },
                topSince: (top?["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                topWaiting: top.map { ($0["state"] as? String) == "waiting" },
                battery: (m["battery"] as? Double).map { Int($0.rounded()) },
                charging: m["charging"] as? Bool,
                gpuHist: nil,
                jobs: list.isEmpty ? nil : Array(list),
                cpu: vit["cpu"] as? Int, temp: vit["cpuT"] as? Int, fan: (vit["fans"] as? [Int])?.max(),
                downSince: (m["online"] as? Bool ?? false) ? nil : (m["lastOk"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) })
        }
    }

    static func merge(prev: JTSnapshot, state: [String: Any], history: [[String: Any]]?, now: Date = .now) -> JTSnapshot {
        let macs = macs(from: state)
        let live = (state["live"] as? [[String: Any]] ?? [])
            .filter { ($0["kind"] as? String ?? "job") == "job" }
            .compactMap(job)
            .sorted { $0.startedAt > $1.startedAt }
        var recent = prev.recent
        if let history {
            recent = history.filter { ($0["kind"] as? String ?? "job") == "job" }.compactMap(job)
        }
        recent = recent.filter { ($0.endedAt ?? $0.startedAt) > now.addingTimeInterval(-86_400) }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        // one sample per ~4 minutes, 24 h kept
        var samples = prev.samples.filter { $0.t > now.addingTimeInterval(-86_400) }
        if (samples.last?.t ?? .distantPast) < now.addingTimeInterval(-240) {
            var g: [String: Int] = [:], m: [String: Int] = [:]
            for mac in macs where mac.online {
                if let id = mac.id { g[id] = mac.gpu ?? 0; m[id] = mac.mem ?? 0 }
            }
            samples.append(JTSample(t: now, gpu: g, mem: m))
        }
        return JTSnapshot(updated: now, reachable: true, macs: macs, live: live, recent: Array(recent.prefix(400)), samples: samples)
    }
}
