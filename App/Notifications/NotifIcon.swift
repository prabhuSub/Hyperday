import UIKit
import UserNotifications

/// v82: each notification gets its own picture: red battery / no-power for Mac alerts, the meeting's kind in its
/// calendar colour, a green chart for the weekly recap.
enum NotifIcon {
    struct Look {
        let symbol: String     // SF Symbol
        let tint: UIColor
        let sender: String     // shown as the name above the text
    }

    static func battery() -> Look { Look(symbol: "battery.25percent", tint: .hdRed, sender: "Mac alert") }
    static func power() -> Look { Look(symbol: "bolt.slash.fill", tint: .hdRed, sender: "Mac alert") }
    static func recap() -> Look { Look(symbol: "chart.bar.fill", tint: UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1), sender: "Weekly recap") }
    static func meeting(_ categoryID: String, hex: String, calendar: String?) -> Look {
        let s: String
        switch categoryID {
        case "meetings": s = "person.2.fill"
        case "work": s = "briefcase.fill"
        case "fitness": s = "figure.run"
        case "family": s = "house.fill"
        case "deepwork": s = "brain.head.profile"
        default: s = "calendar"
        }
        return Look(symbol: s, tint: UIColor(hexString: hex) ?? .systemBlue, sender: calendar ?? "Calendar")
    }

    /// Adds the look's picture to the notification (shown on the right). The big icon on the left is always the
    /// app icon: replacing it needs Communication Notifications, which free (personal) Apple teams can't sign.
    static func apply(_ look: Look, to content: UNMutableNotificationContent, thread: String) -> UNNotificationContent {
        content.threadIdentifier = thread
        guard let png = picture(look) else { return content }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(thread)-\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil,
              let a = try? UNNotificationAttachment(identifier: "pic", url: url, options: nil) else { return content }
        content.attachments = [a]
        return content
    }

    /// A 300 px rounded tile: the symbol in its colour on a dark ground with a soft tinted glow.
    static func picture(_ look: Look) -> Data? {
        let size = CGSize(width: 300, height: 300)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(white: 0.07, alpha: 1).setFill()
            UIBezierPath(rect: rect).fill()
            look.tint.withAlphaComponent(0.22).setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 40, dy: 40)).fill()
            let cfg = UIImage.SymbolConfiguration(pointSize: 140, weight: .semibold)
            guard let sym = UIImage(systemName: look.symbol, withConfiguration: cfg)?
                .withTintColor(look.tint, renderingMode: .alwaysOriginal) else { return }
            let box = rect.insetBy(dx: 70, dy: 70)
            let k = min(box.width / sym.size.width, box.height / sym.size.height)
            let w = sym.size.width * k, h = sym.size.height * k
            sym.draw(in: CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
        }
        return img.pngData()
    }
}

#if DEBUG
extension NotifIcon {
    static func test() {
        let items: [(String, String, Look)] = [
            ("MacBook battery 18%", "plug it in", battery()),
            ("Mac mini lost power or network", "12 min", power()),
            ("Standup in 5 min", "Room 3 · Work", meeting("meetings", hex: "#BF5AF2", calendar: "Work")),
            ("Hyperday", "Your week: 19h focused, 9-day streak. Tap to see your recap.", recap()),
        ]
        for (i, it) in items.enumerated() {
            let c = UNMutableNotificationContent()
            c.title = it.0; c.body = it.1; c.sound = .default
            let t = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(5 + i * 8), repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "hd-test-\(i)", content: apply(it.2, to: c, thread: "test\(i)"), trigger: t))
        }
    }
}
#endif

extension UIColor {
    static let hdRed = UIColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)
    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
