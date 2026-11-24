import SwiftUI
import UIKit

// v55 "instrument" look (approved v54/v55 mockups): chamfered panels, hairline stainless surfaces,
// SF Mono readouts. Shared by the app, widgets and Live Activities. Original geometry only:
// no Tesla logos, wordmarks, fonts or vehicle silhouettes.

/// v57 JobTrail look: what used to be a 45° chamfer is now a soft continuous rounded card.
/// Kept under the old name so every panel in the app, widgets and Live Activities changes at once.
/// `cut` is read as the old chamfer size; the corner radius is `cut + 2` (12 → 14, JobTrail's card radius).
struct Chamfer: InsettableShape {
    var cut: CGFloat = 10
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, min(cut + 2 - inset, r.width / 2, r.height / 2))
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r)
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

/// v56 dot grid (like the design canvas): small round dots on a square grid.
struct DotGrid: Shape {
    var step: CGFloat = 22     // v57: JobTrail map grid (#1c1c1c dots every 22pt)
    var radius: CGFloat = 1
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var y = rect.minY + step / 2
        while y < rect.maxY {
            var x = rect.minX + step / 2
            while x < rect.maxX {
                p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += step
            }
            y += step
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

/// v57 tokens: JobTrail's palette. Dark values are JobTrail's exact tokens; light values are
/// derived counterparts kept for the Light appearance (amber darkened so text clears WCAG AA on white).
enum HDTone {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hd: dark) : UIColor(hd: light) })
    }
    // JobTrail raw palette (always dark).
    static let bg = Color(UIColor(hd: 0x000000))
    static let surface = Color(UIColor(hd: 0x181818))
    static let raised = Color(UIColor(hd: 0x1F1F1F))
    static let hover = Color(UIColor(hd: 0x272727))
    static let lineDark = Color(UIColor(hd: 0x313131))
    static let textHi = Color(UIColor(hd: 0xFFFFFF))
    static let soft = Color(UIColor(hd: 0xD1D1D1))
    static let dim = Color(UIColor(hd: 0x9B9B9B))
    static let faintDark = Color(UIColor(hd: 0x686868))
    static let amber = Color(UIColor(hd: 0xE9A23B))
    static let amberBG = Color(UIColor(hd: 0x2E220F))
    static let green = Color(UIColor(hd: 0x7AA36A))
    static let greenBG = Color(UIColor(hd: 0x141F18))
    static let blue = Color(UIColor(hd: 0x6EA8D9))
    static let blueBG = Color(UIColor(hd: 0x13202B))
    static let danger = Color(UIColor(hd: 0xDB6B67))
    static let dangerBG = Color(UIColor(hd: 0x2A1514))
    /// Status colours: green = running, amber = waiting, blue = done, red = failed.
    static let running = green, waiting = amber, done = blue, failed = danger

    // Adaptive tokens used across the app.
    static let stage = dyn(0xE6E7E9, 0x000000)
    static let hair = dyn(0xD8D9DC, 0x272727)
    static let panel = dyn(0xF4F5F6, 0x181818)
    static let line = dyn(0xDCDDE0, 0x313131)
    static let alert = dyn(0xC8102E, 0xDB6B67)
    static let warn = dyn(0x8A5A00, 0xE9A23B)
    static let ok = dyn(0x3E7A2E, 0x7AA36A)
    static let accentText = dyn(0x8A5A00, 0xE9A23B)
    /// Dark card used on the Now card, Live Activities and widgets in both modes (JobTrail surface).
    static let instrument = surface
    static let instrumentHair = hover
    static let instrumentDot = Color(UIColor(hd: 0x1C1C1C))
    /// Page dots are off in v57 (JobTrail pages are flat black); kept for callers.
    static let pageDot = Color.clear
    static let instrumentButton = hover
    static let instrumentMuted = dim
}

extension UIColor {
    convenience init(hd rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// Geist (UI). Bundled in the app and the widget extension (Shared/Fonts, UIAppFonts).
    static func geist(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Geist-" + HDFontWeight.name(weight), fixedSize: size)
    }
    /// Geist Mono (labels, times, stats). Fixed size: widgets and Live Activities.
    static func geistMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("GeistMono-" + HDFontWeight.name(weight), fixedSize: size)
    }
    /// Mono readouts (was SF Mono, now Geist Mono).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        geistMono(size: size, weight: weight)
    }
}

/// The four Geist weights we ship. Heavier SwiftUI weights map to Bold, lighter ones to Regular.
enum HDFontWeight {
    static func name(_ w: Font.Weight) -> String {
        switch w {
        case .medium: return "Medium"
        case .semibold: return "SemiBold"
        case .bold, .heavy, .black: return "Bold"
        default: return "Regular"
        }
    }
}

/// Small uppercase tracked Geist Mono label ("ENDS 10:30"), JobTrail's label style.
struct MonoCaps: View {
    let text: String
    var size: CGFloat = 11
    var color: Color? = nil
    init(_ text: String, size: CGFloat = 11, color: Color? = nil) { self.text = text; self.size = size; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.mono(size, .medium)).kerning(size * 0.08).lineLimit(1)
            .foregroundStyle(color ?? .secondary)
    }
}

/// Card background for widgets, Live Activities and the Now card: JobTrail's zone gradient
/// (#181818 → #0e0e0e), no dots or hairlines.
struct InstrumentBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(UIColor(hd: 0x181818)), Color(UIColor(hd: 0x0E0E0E))],
                       startPoint: .top, endPoint: .bottom)
    }
}
