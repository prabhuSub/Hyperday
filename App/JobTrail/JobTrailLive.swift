import Foundation
import SwiftUI
import WidgetKit

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
        // v72: with a single address there's nothing to choose: skip the /health round trip.
        if host == nil { if JobTrailConfig.hosts.count == 1 { host = JobTrailConfig.hosts[0] } else { await findHost() } }
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
            if let u = pageURL { JobTrailWeb.shared.prepare(u) }   // v72: page ready before the tab is opened
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

    private var lastHistoryAt = Date.distantPast
    private var lastWidgetReload = Date.distantPast

    private func apply(_ json: [String: Any]) {
        // v64: one parser for the app and the widgets (JTStore); the snapshot is saved for the Macs widgets.
        // GPU history for the Live Activity graph: saved readings (≈4 min apart) + now, ~20 points.
        let saved = JTStore.load() ?? .empty
        macs = JTStore.macs(from: json).map { m in
            var m = m
            let hist = saved.series(m.id, gpu: true, hours: 1.5).map { Int($0) }.suffix(19)
            m.gpuHist = Array(hist) + [m.gpu ?? 0]
            return m
        }
        runningTotal = macs.reduce(0) { $0 + $1.running }
        lastUpdate = .now
        let prev = JTStore.load() ?? .empty
        let needHistory = Date.now.timeIntervalSince(lastHistoryAt) > 60
        let jobsChanged = Set(prev.live.map(\.id)) != Set((json["live"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        Task {
            var history: [[String: Any]]? = nil
            if needHistory, let h = host {
                history = await JTStore.get("/api/history?days=1", host: h, timeout: 8) as? [[String: Any]]
                if history != nil { lastHistoryAt = .now }
            }
            JTStore.save(JTStore.merge(prev: prev, state: json, history: history))
            // Widgets: right away when jobs start/finish, otherwise at most every 5 minutes (WidgetKit budget).
            if jobsChanged || Date.now.timeIntervalSince(lastWidgetReload) > 300 {
                lastWidgetReload = .now
                WidgetCenter.shared.reloadTimelines(ofKind: JTStore.kind)
                WidgetCenter.shared.reloadTimelines(ofKind: JTStore.lockKind)
            }
        }
        changed()
    }

    /// Refresh the Live Activity only when something you'd see changed (not on every GPU tick).
    private func changed() {
        let sig = macs.map { "\($0.name)|\($0.online)|\($0.running)|\($0.waiting)|\($0.top ?? "")|\(($0.gpu ?? 0) / 10)|\(($0.mem ?? 0) / 10)|\(($0.battery ?? 0) / 5)|\($0.charging ?? false)|\(($0.jobs ?? []).map(\.label))" }.joined(separator: ",")
        guard sig != lastSignature else { return }
        lastSignature = sig
        Task { await LiveActivityManager.shared.refresh() }
    }
}
