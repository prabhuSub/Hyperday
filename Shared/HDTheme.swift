import SwiftUI
import UIKit

// v55 "instrument" look (approved v54/v55 mockups): chamfered panels, hairline stainless surfaces,
// SF Mono readouts. Shared by the app, widgets and Live Activities. Original geometry only:
// no Tesla logos, wordmarks, fonts or vehicle silhouettes.

/// A rectangle with its four corners cut at 45°. iOS keeps its own outer shapes (cards, Island, widgets).
struct Chamfer: InsettableShape {
    var cut: CGFloat = 10
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = min(cut, r.width / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> Chamfer { var s = self; s.inset += amount; return s }
}

/// Brushed-stainless hairlines: thin horizontal lines every `spacing` points (lines, not a gradient).
struct Hairlines: Shape {
    var spacing: CGFloat = 4
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var y = rect.minY + 2
        while y < rect.maxY {
            p.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: 1))
            y += spacing
        }
        return p
    }
}

/// A plus drawn as two bars, so it sits exactly in the centre at any size (a text "+" doesn't).
struct PlusMark: Shape {
    var weight: CGFloat = 3.2
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height), c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addRect(CGRect(x: c.x - weight / 2, y: c.y - s / 2, width: weight, height: s))
        p.addRect(CGRect(x: c.x - s / 2, y: c.y - weight / 2, width: s, height: weight))
        return p
    }
}

/// Tokens (all text pairs checked ≥ 4.5:1, WCAG AA, light and dark).
enum HDTone {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hd: dark) : UIColor(hd: light) })
    }
    static let stage = dyn(0xE6E7E9, 0x1D1F22)
    static let hair = dyn(0xD8D9DC, 0x25282C)
    static let panel = dyn(0xF4F5F6, 0x17181B)
    static let line = dyn(0xDCDDE0, 0x2A2D31)
    static let alert = dyn(0xC8102E, 0xFF6B5E)
    static let warn = dyn(0x8A5A00, 0xFFB340)
    static let ok = dyn(0x16632A, 0x4CD964)
    static let accentText = dyn(0x2D52BD, 0x7FA2FF)
    /// Dark instrument panel used on the Now card, Live Activities and widgets in both modes.
    static let instrument = Color(UIColor(hd: 0x141518))
    static let instrumentHair = Color(UIColor(hd: 0x1C1E22))
    static let instrumentButton = Color(UIColor(hd: 0x25272B))
    static let instrumentMuted = Color(UIColor(hd: 0xA2A3A5))
}

extension UIColor {
    convenience init(hd rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// SF Mono for readouts and spaced caps (fixed size: widgets and Live Activities).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Spaced mono caps label ("ENDS 10:30").
struct MonoCaps: View {
    let text: String
    var size: CGFloat = 11
    var color: Color? = nil
    init(_ text: String, size: CGFloat = 11, color: Color? = nil) { self.text = text; self.size = size; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.mono(size, .medium)).kerning(size * 0.18).lineLimit(1)
            .foregroundStyle(color ?? .secondary)
    }
}

/// Instrument panel background: dark plate + hairlines (used inside widgets and the Now card).
struct InstrumentBackground: View {
    var body: some View {
        ZStack {
            HDTone.instrument
            Hairlines().fill(HDTone.instrumentHair)
        }
    }
}
