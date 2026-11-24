import Foundation
import SwiftUI

/// v61: JobTrail, reached from Hyperday. The key and the MacBook's Tailscale address come from Info.plist
/// (deploy.sh reads them from ~/.jobtrail/token and `tailscale ip`; nothing is stored in the repo).
enum JobTrailConfig {
    static let key = (Bundle.main.object(forInfoDictionaryKey: "JTKey") as? String ?? "").trimmingCharacters(in: .whitespaces)
    static let hosts = (Bundle.main.object(forInfoDictionaryKey: "JTHosts") as? String ?? "")
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    static let port = 4791
    static var isConfigured: Bool { !key.isEmpty && !hosts.isEmpty }
}

/// Polls JobTrail's /api/state and keeps a small summary of each Mac for the Live Activity and the tab.
@MainActor
final class JobTrailLive: ObservableObject {
    static let shared = JobTrailLive()

    @Published private(set) var macs: [MacLive] = []
    @Published private(set) var host: String?
    @Published private(set) var reachable = false
    @Published private(set) var runningTotal = 0
    @Published private(set) var lastUpdate: Date?

    private var loop: Task<Void, Never>?
    private var lastSignature = ""

    /// Base page URL (with the key), once a host answered.
    var pageURL: URL? {
        host.flatMap { URL(string: "http://\($0):\(JobTrailConfig.port)/?k=\(JobTrailConfig.key)") }
    }

    /// Start polling (every 6 s) while the app is open. Safe to call repeatedly.
    func start() {
        guard JobTrailConfig.isConfigured, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil }

    /// One read. Also used by background refresh.
    func poll() async {
        guard JobTrailConfig.isConfigured else { return }
        if host == nil { await findHost() }
        guard let h = host, let url = URL(string: "http://\(h):\(JobTrailConfig.port)/api/state") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        req.setValue(JobTrailConfig.key, forHTTPHeaderField: "x-jobtrail-key")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
            apply(json)
            reachable = true
        } catch {
            reachable = false
            host = nil   // try every host again next time
            if !macs.isEmpty {
                macs = macs.map { var m = $0; m.online = false; m.running = 0; m.waiting = 0; m.top = nil; m.topSince = nil; return m }
                changed()
            }
        }
    }

    private func findHost() async {
        for h in JobTrailConfig.hosts {
            guard let u = URL(string: "http://\(h):\(JobTrailConfig.port)/health") else { continue }
            var req = URLRequest(url: u); req.timeoutInterval = 3
            if let (_, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 {
                host = h
                return
            }
        }
    }

    private func apply(_ json: [String: Any]) {
        let machines = json["machines"] as? [[String: Any]] ?? []
        let live = (json["live"] as? [[String: Any]] ?? []).filter { ($0["kind"] as? String ?? "job") == "job" }
        var out: [MacLive] = []
        for m in machines {
            let id = m["id"] as? String ?? ""
            let jobs = live.filter { ($0["machine"] as? String) == id }
            let run = jobs.filter { ($0["state"] as? String) == "running" }
            let wait = jobs.filter { ($0["state"] as? String) == "waiting" }
            let newest = { (list: [[String: Any]]) in list.max { ($0["startedAt"] as? Double ?? 0) < ($1["startedAt"] as? Double ?? 0) } }
            let top = newest(run) ?? newest(wait)
            let gpu = (m["gpu"] as? Double).map { Int($0.rounded()) }
            let mem = (m["memFree"] as? Double).map { max(0, 100 - Int($0.rounded())) }
            out.append(MacLive(
                name: m["name"] as? String ?? id,
                desktop: (m["device"] as? String) == "desktop",
                online: m["online"] as? Bool ?? false,
                running: run.count, waiting: wait.count, gpu: gpu, mem: mem,
                top: top.flatMap { $0["label"] as? String },
                topSince: (top?["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                topWaiting: top.map { ($0["state"] as? String) == "waiting" }))
        }
        macs = out
        runningTotal = out.reduce(0) { $0 + $1.running }
        lastUpdate = .now
        changed()
    }

    /// Refresh the Live Activity only when something you'd see changed (not on every GPU tick).
    private func changed() {
        let sig = macs.map { "\($0.name)|\($0.online)|\($0.running)|\($0.waiting)|\($0.top ?? "")|\(($0.gpu ?? 0) / 10)|\(($0.mem ?? 0) / 10)" }.joined(separator: ",")
        guard sig != lastSignature else { return }
        lastSignature = sig
        Task { await LiveActivityManager.shared.refresh() }
    }
}
