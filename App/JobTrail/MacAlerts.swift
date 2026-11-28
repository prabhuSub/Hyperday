import Foundation
import UserNotifications
import UIKit

/// v75: a notification when a Mac needs you — MacBook battery under 20 % and not charging, or the Mac mini gone for
/// 3+ minutes (power or network loss). Off until you turn it on (Settings › Live Activity › Mac alerts).
/// Checked whenever Hyperday reads JobTrail: while open, and when iOS wakes it in the background (iOS decides how
/// often — roughly every 15–60 min — so a background alert can be late). One notification per problem; it re-arms
/// once the problem clears.
enum MacAlerts {
    static let key = "hdMacAlerts"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }
    private static let sentKey = "hdMacAlertsSent"

    static func check(_ macs: [MacLive], now: Date = .now) {
        let d = UserDefaults.standard
        var sent = Set(d.stringArray(forKey: sentKey) ?? [])
        var active = Set<String>()
        for m in macs {
            guard let text = m.alert(now: now) else { continue }
            let id = "macalert.\(m.id ?? m.name).\(text.contains("battery") ? "battery" : "power")"
            active.insert(id)
            if enabled && !sent.contains(id) { post(id: id, text: text); sent.insert(id) }
        }
        sent.formIntersection(active)   // cleared problems can alert again next time
        d.set(Array(sent), forKey: sentKey)
    }

    private static func post(id: String, text: String) {
        let c = UNMutableNotificationContent()
        let parts = text.components(separatedBy: " · ")
        c.title = parts.first ?? text
        c.body = parts.dropFirst().joined(separator: " · ")
        c.sound = .default
        c.interruptionLevel = .active
        c.threadIdentifier = "macalerts"
        // v81: a picture of the problem (red battery / no power) next to the text, not just the app icon.
        if let a = picture(battery: text.contains("battery"), id: id) { c.attachments = [a] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// A 300 px dark tile with the SF Symbol for the problem, written to tmp and attached (iOS copies it).
    private static func picture(battery: Bool, id: String) -> UNNotificationAttachment? {
        let size = CGSize(width: 300, height: 300)
        let red = UIColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.07, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 66).fill()
            let cfg = UIImage.SymbolConfiguration(pointSize: 150, weight: .semibold)
            let name = battery ? "battery.25percent" : "bolt.slash.fill"
            guard let sym = UIImage(systemName: name, withConfiguration: cfg)?.withTintColor(red, renderingMode: .alwaysOriginal) else { return }
            let r = AVMakeRect(sym.size, in: CGRect(origin: .zero, size: size).insetBy(dx: 50, dy: 50))
            sym.draw(in: r)
        }
        guard let data = img.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id)-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "pic", url: url, options: nil)
    }

    private static func AVMakeRect(_ s: CGSize, in r: CGRect) -> CGRect {
        let k = min(r.width / s.width, r.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
