import Foundation
import UserNotifications

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
        let look = text.contains("battery") ? NotifIcon.battery() : NotifIcon.power()
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: NotifIcon.apply(look, to: c, thread: "macalerts"), trigger: nil))
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
