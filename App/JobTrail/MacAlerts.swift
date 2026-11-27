import Foundation

/// v76: Mac alerts are sent by the Pi with ntfy (within a minute, even with Hyperday closed). This switch is the same
/// one as HomeDeck › Settings › Alerts › Macs: it's stored on the Pi. Off until you turn it on.
/// The red line on the Live Activity comes from the Macs' own data (MacLive.alert) and needs no switch.
enum MacAlerts {
    static let key = "hdMacAlerts"
    private static let bases = ["http://100.110.37.100:4545", "http://192.168.1.184:4545", "http://prabhu-pi.local:4545"].compactMap(URL.init(string:))

    /// The Pi's current setting (nil if it can't be reached).
    static func remote() async -> Bool? {
        for b in bases {
            var r = URLRequest(url: b.appendingPathComponent("api/alerts")); r.timeoutInterval = 4
            if let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return j["macs"] as? Bool ?? false }
        }
        return nil
    }
    @discardableResult
    static func setRemote(_ on: Bool) async -> Bool {
        for b in bases {
            var r = URLRequest(url: b.appendingPathComponent("api/alerts")); r.httpMethod = "POST"; r.timeoutInterval = 6
            r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue("1", forHTTPHeaderField: "x-homedeck")
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["macs": on])
            if let (_, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 { return true }
        }
        return false
    }
}
