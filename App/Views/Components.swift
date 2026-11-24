import SwiftUI
import UIKit

// MARK: - Theme (from prabhusubramanian.com, light + dark)

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

enum Theme {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }

    // JobTrail palette (amber-on-black). Dark = JobTrail's exact tokens; light is a
    // derived counterpart that keeps the amber identity and stays WCAG AA.
    /// v70: side margin of every tab's content, the same as the bottom navigation bar's.
    static let edge: CGFloat = 14
    static let bg = dyn(0xFFFFFF, 0x000000)         // JobTrail --bg
    static let section = dyn(0xF4F5F6, 0x000000)
    static let card = dyn(0xFFFFFF, 0x181818)       // --surface
    static let border = dyn(0xDCDDE0, 0x313131)     // --line
    static let text = dyn(0x171A20, 0xFFFFFF)       // --text
    static let muted = dyn(0x5C5E62, 0x9B9B9B)      // --dim
    static let faint = dyn(0xA2A3A5, 0x686868)      // --faint
    static let navActive = dyn(0xEEEEEE, 0x272727)  // --hover
    // Signature accent. Was blue; now JobTrail amber (--accent #e9a23b). Light is a
    // darkened amber so accent text clears AA on white (#e9a23b fails on white).
    static let blue = dyn(0xB06F00, 0xE9A23B)       // --accent
    static let red = dyn(0xC8102E, 0xDB6B67)        // --danger
    static let green = dyn(0x3E7A2E, 0x7AA36A)      // --success
    static let cyan = dyn(0x2F6FA8, 0x6EA8D9)       // --blue (done state)
    static let raised = dyn(0xF4F5F6, 0x1F1F1F)     // --raised
    static let hover = dyn(0xEEEEEE, 0x272727)      // --hover
    static let soft = dyn(0x3A3C40, 0xD1D1D1)       // --soft
    static let amberBG = dyn(0xFBEFD9, 0x2E220F)    // --accent-bg
    static let greenBG = dyn(0xE6F0E1, 0x141F18)    // --success-bg
    static let dangerBG = dyn(0xF8E2E1, 0x2A1514)   // --danger-bg
}

/// v60: two modes only, Dark and Light (an old saved "system" reads as Dark).
enum Appearance: String, CaseIterable, Hashable {
    case dark, light

    var label: String { rawValue.capitalized }

    var scheme: ColorScheme? { self == .light ? .light : .dark }
}

// MARK: - Header: HYPERDAY | Section              [theme]

struct HeaderBar: View {
    let section: String
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    private var current: Appearance { Appearance(rawValue: appearance) ?? .dark }

    var body: some View {
        HStack(spacing: 10) {
            Text("HYPERDAY")
                .font(.hdMono(size: 13, weight: .semibold))
                .kerning(2.4)
                .foregroundStyle(Theme.text)
            Rectangle().fill(Theme.border).frame(width: 1, height: 16)
            Text(section)
                .font(.hd(size: 14))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                                appearance = (current == .dark ? Appearance.light : .dark).rawValue   // v60: Dark ↔ Light
            } label: {
                HDIcon(current == .light ? "sun" : "moon", size: 17)
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Appearance: \(current.label). Tap to change.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

// MARK: - Text pieces

/// Tiny uppercase letter-spaced label (LOCATION / CURRENT ROLE on the site).
struct Caps: View {
    let text: String
    var color: Color = Theme.muted
    init(_ text: String, color: Color = Theme.muted) { self.text = text; self.color = color }

    var body: some View {
        Text(text.uppercased())
            .font(.hdMono(size: 11, weight: .medium))   // v57: JobTrail label (Geist Mono, tracked caps)
            .kerning(1.1)
            .foregroundStyle(color)
    }
}

struct InfoItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var color: Color? = nil   // v24: big number in this color
}

/// "3h 10m" → big digits, small letters (v24 card language).
func bigSmallText(_ s: String, size: CGFloat) -> Text {
    s.reduce(Text("")) { acc, ch in
        // v57: stats in Geist Mono (JobTrail), small unit letters.
        acc + Text(String(ch)).font((ch.isNumber || ch == "—" || ch == "/") ? .hdMono(size: size * 0.92, weight: .semibold)
                                                                          : .hdMono(size: size * 0.46, weight: .medium))
    }
}

/// Row of label/value pairs over thin dividers (the site's About panel).
struct InfoRow: View {
    let items: [InfoItem]

    var body: some View {
        // v24: stat tiles — big colored number, small unit, caps label.
        HStack(alignment: .top, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    bigSmallText(item.value, size: 24)
                        .foregroundStyle(item.color ?? Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Caps(item.label)
                        .lineLimit(1)                 // v37: one line in every tile ("MEETINGS LEFT" wrapped)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Chamfer(cut: 12).fill(Theme.card))
                .overlay(Chamfer(cut: 12).strokeBorder(Theme.border, lineWidth: 1))
                .animation(HDEase.standard(0.6), value: item.value)
                .hdBlurIn()
            }
        }
    }
}

// MARK: - Buttons (Hire Me / Download CV)

struct PrimaryButtonStyle: ButtonStyle {
    var width: CGFloat? = nil   // nil = full width
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hd(size: 14, weight: .semibold))
            .foregroundStyle(Color.black)                    // v57: black on JobTrail amber (AA)
            .frame(maxWidth: width ?? .infinity)
            .frame(height: 40)
            .background(Chamfer(cut: 7).fill(Theme.blue))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(HDEase.standard(0.25), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var width: CGFloat? = nil   // nil = full width
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hd(size: 14, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: width ?? .infinity)
            .frame(height: 40)
            .background(Chamfer(cut: 7).fill(configuration.isPressed ? Theme.hover : Theme.raised))
            .overlay(Chamfer(cut: 7).strokeBorder(Theme.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(HDEase.standard(0.25), value: configuration.isPressed)
    }
}

/// v56: page background with faint canvas dots.
struct DotPage: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()   // v57: JobTrail pages are flat black
    }
}

// MARK: - Card

struct CardBox: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Chamfer(cut: 12).fill(Theme.card))   // v55: chamfered panels
            .clipShape(Chamfer(cut: 12))
            .overlay(Chamfer(cut: 12).strokeBorder(Theme.border, lineWidth: 1))   // v57: 1px #313131
    }
}

extension View {
    func cardBox(padding: CGFloat = 16) -> some View { modifier(CardBox(padding: padding)) }
}

// MARK: - Chips (the site's skill pills)

struct Chip: View {
    let title: String
    var color: Color? = nil
    var selected: Bool = false
    var icon: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                if let icon {
                    HDIcon(icon, size: 15).foregroundStyle(selected ? (color ?? Theme.text) : Theme.muted)
                }
                Text(title)
                    .font(.hd(size: 15, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Theme.text : Theme.muted)
            // v57: JobTrail pills: surface + 1px line; selected = hover fill + amber line.
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Theme.hover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Theme.blue.opacity(0.55) : Theme.border, lineWidth: 1))
            .animation(HDEase.standard(), value: selected)
        }
        .buttonStyle(.plain)
    }
}

/// v27: the + button's blue Liquid Glass (iOS 26+); a solid blue circle on iOS 18–25.
struct BlueGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(Theme.blue).interactive(), in: Chamfer(cut: 14))   // v57: amber
        } else {
            content
                .background(Chamfer(cut: 14).fill(Theme.blue))
                .shadow(color: HDTone.amber.opacity(0.25), radius: 14)
        }
    }
}

/// v27 Settings section header: the section's icon on a colored dot, then the title.
struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    init(_ title: String, icon: String, color: Color) {
        self.title = title; self.icon = icon; self.color = color
    }

    var body: some View {
        HStack(spacing: 10) {
            HDIcon(icon, size: 22).foregroundStyle(color)   // v47: solid icon, no circle
            Text(title).font(.hd(size: 15, weight: .bold)).foregroundStyle(Theme.text)
        }
        .padding(.bottom, 2)
    }
}

/// Wraps chips onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "Auto · Deep Work" + every category. nil selection = automatic (rules).
struct CategoryChips: View {
    @Binding var selection: String?
    let autoName: String
    @ObservedObject private var store = CategoryStore.shared

    var body: some View {
        FlowLayout(spacing: 8) {
            Chip(title: "Auto · \(autoName)", selected: selection == nil) { selection = nil }
            ForEach(store.categories) { c in
                Chip(title: c.name, color: c.color, selected: selection == c.id) { selection = c.id }
            }
        }
    }
}

// MARK: - Pill toggle (the site's nav: active item gets a gray fill)

struct PillNav<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        // v27: one capsule track, the chosen option filled dark (the video's pill language).
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(HDEase.standard(0.3)) { selection = option }
                } label: {
                    // v57: JobTrail range control: mono labels, selected = hover fill.
                    Text(label(option).uppercased())
                        .font(.hdMono(size: 11, weight: .medium))
                        .kerning(0.8)
                        .foregroundStyle(on ? Theme.text : Theme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.hover : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.navActive, lineWidth: 1))
    }
}

// MARK: - Block row (timeline, calendar)

struct BlockRow: View {
    let block: Block
    let now: Date
    let color: Color
    var steps: [Step] = []
    var showNow = true
    var icon: String? = nil
    var pill: RowPill? = nil   // Today: live timer / in 2h 07m / ✓ Done / Ended
    var above: FlowState? = nil   // v57: connector line into this row's icon (Today)
    var below: FlowState? = nil   // and out of it

    private var detail: String {
        var parts: [String] = []
        parts.append(block.start.shortTime)   // v24: time moves into the subtitle
        parts.append(block.source == .calendar ? (block.calendarName ?? "Calendar") : "My plan")
        parts.append(block.end.timeIntervalSince(block.start).hoursMinutes)
        if !steps.isEmpty { parts.append("\(steps.filter(\.done).count)/\(steps.count) steps") }
        if block.declined { parts.append("Declined") }
        let n = PhotoStore.shared.names(for: block.id).count
        if n > 0 { parts.append(n == 1 ? "1 photo" : "\(n) photos") }   // v36
        return parts.joined(separator: " · ")
    }

    /// v60: what a row's pulse graph pops up.
    private func pulseInfo(_ st: HDStatus) -> JTPulseInfo {
        var items = [
            JTKV(key: "Time", value: "\(block.start.shortTime) – \(block.end.shortTime)"),
            JTKV(key: "Length", value: block.end.timeIntervalSince(block.start).hoursMinutes),
            JTKV(key: "Source", value: block.source == .calendar ? (block.calendarName ?? "Calendar") : "My plan"),
        ]
        if !steps.isEmpty {
            items.append(JTKV(key: "Steps", value: "\(steps.filter(\.done).count)/\(steps.count)", color: HDTone.amber))
            if let nextStep = steps.first(where: { !$0.done }) { items.append(JTKV(key: "Next step", value: nextStep.title)) }
        }
        return JTPulseInfo(title: block.title, status: st, items: items, range: block.start...block.end)
    }

    /// v57 status: green = running, amber = waiting, blue = done, red = failed (over time / declined).
    private func status(isNow: Bool, done: Bool) -> HDStatus {
        if block.declined { return .failed }
        if let pill {
            switch pill {
            case .live: return .running
            case .over: return .failed
            case .upcoming: return .waiting
            case .done, .ended: return .done
            }
        }
        return isNow ? .running : done ? .done : .waiting
    }

    var body: some View {
        let isNow = showNow && block.contains(now)
        let done = block.end <= now
        let st = status(isNow: isNow, done: done)

        HStack(spacing: 12) {
            // v57: JobTrail job tile: the icon on a raised tile, ringed by its status.
            HDIcon(icon ?? "event", size: 18)
                .foregroundStyle(color.opacity(done ? 0.45 : 1))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
                .overlay { StatusRing(status: st) }
                .overlay(alignment: .top) {
                    if let above { FlowLine(state: above).frame(width: 2, height: 13).offset(y: -13) }
                }
                .overlay(alignment: .bottom) {
                    if let below { FlowLine(state: below).frame(width: 2, height: 13).offset(y: 13) }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title)
                    .font(.hd(size: 15, weight: isNow ? .semibold : .medium))
                    .foregroundStyle(done ? Theme.muted : Theme.text)
                    .strikethrough(block.declined)
                    .lineLimit(1)
                Text(detail)
                    .font(.hdMono(size: 11))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let first = PhotoStore.shared.names(for: block.id).first {
                PhotoThumb(name: first, width: 30, radius: 6)   // v36: the photo, small
            }
            if st == .running || (st == .failed && !block.declined) {
                JTPulseButton(info: pulseInfo(st)).frame(width: 40, height: 18)   // v59 graph · v60 tap for details
            }
            if let pill {
                RowPillView(pill: pill, now: now)
            } else if isNow {
                StatusTag(text: "Now", status: .running)
            } else if block.source == .calendar {
                // Calendar events are read-only in Hyperday (can't be moved or deleted here).
                HDIcon("event", size: 14)
                    .foregroundStyle(Theme.faint)
                    .accessibilityLabel("Calendar event")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(pill?.isLive == true ? Theme.greenBG.opacity(0.55) : .clear)
        .contentShape(Rectangle())
    }
}

/// v57: the ring around a row's icon tile. Running sweeps green, waiting is a dashed amber line,
/// done is blue, failed is red.
struct StatusRing: View {
    let status: HDStatus
    var radius: CGFloat = 9

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch status {
        case .running:
            SweepRing(radius: radius)
        case .waiting:
            shape.strokeBorder(Color(UIColor(rgb: 0x6B5223)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        case .done:
            shape.strokeBorder(Color(UIColor(rgb: 0x2B4257)), lineWidth: 1)
        case .failed:
            shape.fill(HDTone.danger.opacity(0.06)).overlay(shape.strokeBorder(Color(UIColor(rgb: 0x5A2A28)), lineWidth: 1))
        case .idle:
            shape.strokeBorder(Theme.navActive, lineWidth: 1)
        }
    }
}

// MARK: - v17 appearance button (next to the profile circle)

/// v60: tap switches Dark ↔ Light; the icon shows the current mode.
struct AppearanceButton: View {
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    private var current: Appearance { Appearance(rawValue: appearance) ?? .dark }

    var body: some View {
        Button {
            appearance = (current == .dark ? Appearance.light : .dark).rawValue   // v60: Dark ↔ Light
        } label: {
            HDIcon(current == .light ? "sun" : "moon", size: 15)
                .foregroundStyle(Theme.soft)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))   // v59: JobTrail square button
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.navActive, lineWidth: 1))
                .rotationEffect(.degrees(current == .dark ? 0 : 180))
                .animation(HDEase.standard(0.5), value: appearance)
                .frame(width: 44, height: 44)   // v52: 44 pt tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: appearance)
        .accessibilityLabel("Appearance: \(current.label). Tap to change.")
    }
}

// MARK: - v16 timer pills

enum RowPill {
    case live(Date)       // counts down to this end
    case over(Date)       // counts up from the planned end
    case upcoming(Date)   // "in 2h 07m"
    case done
    case ended

    var isLive: Bool {
        switch self { case .live, .over: return true; default: return false }
    }
}

struct RowPillView: View {
    let pill: RowPill
    let now: Date

    // v57: JobTrail status pills: Geist Mono on the status tint.
    var body: some View {
        switch pill {
        case .live(let end):
            HStack(spacing: 5) {
                PulseDot(color: HDTone.green, size: 5)
                Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                    .monospacedDigit()
                Text("left")
            }
            .modifier(PillShape(status: .running))
            .hdShimmer(true, color: HDTone.green)   // v59: the live pill shimmers
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .over(let since):
            HStack(spacing: 0) {
                Text("+")
                Text(timerInterval: since...since.addingTimeInterval(24 * 3600), countsDown: false)
                    .monospacedDigit()
                Text(" over")
            }
            .modifier(PillShape(status: .failed))
        case .upcoming(let start):
            HStack(spacing: 4) {
                TiltingHourglass(size: 9)
                Text("in \(start.timeIntervalSince(now).hoursMinutes)").monospacedDigit()
            }
            .modifier(PillShape(status: .waiting))
        case .done:
            Text("✓ Done").modifier(PillShape(status: .done))
        case .ended:
            Text("Ended").modifier(PillShape(status: .idle))
        }
    }
}

private struct PillShape: ViewModifier {
    let status: HDStatus
    func body(content: Content) -> some View {
        content
            .font(.hdMono(size: 11, weight: .semibold))
            .foregroundStyle(status == .idle ? Theme.faint : status.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(status.background))
    }
}

/// The live timer on the Today card (ticks every second via Text(timerInterval:)).
struct LiveTimerPill: View {
    let range: ClosedRange<Date>
    let down: Bool
    var prefix: String = ""
    let status: HDStatus

    var body: some View {
        HStack(spacing: 6) {
            PulseDot(color: status.color, size: 6)   // v57: live dot pulses
            HStack(spacing: 0) {
                if !prefix.isEmpty { Text(prefix) }
                Text(timerInterval: range, countsDown: down)
            }
        }
        .font(.hdMono(size: 13, weight: .semibold))
        .foregroundStyle(status.color)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(status.background))
    }
}

// MARK: - Floating tab bubble

/// v35: switches for whole sections of the app.
enum Features {
    /// The Car tab, its Settings page, background reads and car widgets. Off while Prabhu reviews it.
    static let car = true   // v39: back on (was off in v35–v38)
    /// v38: the small car widgets. Keeps car reads on (when the app opens or refreshes in the background,
    /// never waking the car) even while the Car tab is off.
    static let carWidgets = true
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, calendar, jobtrail, car, stats, settings, add
    var id: String { rawValue }
    var title: String { self == .jobtrail ? "JobTrail" : rawValue.capitalized }
    var icon: String {
        switch self {
        case .today: return "today"
        case .calendar: return "calendar"
        case .jobtrail: return "event"
        case .car: return "car"
        case .stats: return "stats"
        case .settings: return "settings"
        case .add: return "add"
        }
    }
}

/// Apple's native tab bar: on iOS 26+ it is the Liquid Glass bar with the press-and-drag lens
/// and it shrinks when you scroll down.
struct RootView: View {
    // v52: `-hdStartTab stats` (simulator launch argument) opens a tab directly, for screenshots/audits.
    @State private var tab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "hdStartTab") ?? "") ?? .today
    @State private var adding: AddMode?
    @State private var calDay = Calendar.current.component(.day, from: .now)
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var activity: LiveActivityManager

    enum AddMode: String, Identifiable { case block, words, photo; var id: String { rawValue } }

    var body: some View {
        // v35: Apple's own tab bar (Liquid Glass on iOS 26), SF Symbols (Calendar shows today's date),
        // blue when selected.
        TabView(selection: $tab) {
            Tab("Today", systemImage: "clock", value: AppTab.today) {
                TabRoot(title: "Today") { TodayView().tabFade(tab == .today) }
            }
            Tab(value: AppTab.calendar) {
                TabRoot(title: "Calendar") { CalendarTabView().tabFade(tab == .calendar) }
            } label: {
                Label { Text("Calendar") } icon: { Image("hd-tab-cal-\(calDay)").renderingMode(.template) }   // today's date
            }
            // v61: JobTrail, your Macs' live jobs (the web app, unchanged, inside Hyperday).
            Tab(value: AppTab.jobtrail) {
                JobTrailTabView()
            } label: {
                Label("JobTrail", systemImage: "waveform.path.ecg")
            }
            if Features.car {
                Tab(value: AppTab.car) {
                    TabRoot(title: "Car") { CarView().tabFade(tab == .car) }
                } label: {
                    Label { Text("Car") } icon: { Image("hd-tab-car-front").renderingMode(.template) }   // v41: front view of your car
                }
            }
            Tab("Stats", systemImage: "chart.bar", value: AppTab.stats) {
                TabRoot(title: "Stats") { StatsView().tabFade(tab == .stats) }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                TabRoot(title: "Settings") { SettingsView().tabFade(tab == .settings) }
            }
        }
        .tint(Theme.blue)
        .scrollContentBackground(.hidden)   // v58: forms and lists sit on JobTrail black
        // The Calendar tab shows today's date: redraw at midnight and whenever the app comes back.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            calDay = Calendar.current.component(.day, from: .now)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { calDay = Calendar.current.component(.day, from: .now) }
        }
        // v59: JobTrail switcher replaces the system tab bar (same tabs, same order).
        .overlay(alignment: .bottom) {
            JTTabBar(tab: $tab, calDay: calDay, live: activity.isRunning)
        }
        // v35b: + is a floating button again (not a tab). Tap = Add block, hold = Apple's menu.
        .overlay(alignment: .bottomTrailing) { if tab != .jobtrail { AddFab { adding = $0 } } }   // v61: not over JobTrail
        .onReceive(NotificationCenter.default.publisher(for: CalendarJump.notification)) { _ in
            tab = .calendar
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCarTab)) { _ in if Features.car { tab = .car } }
        .onReceive(NotificationCenter.default.publisher(for: .openJobTrailTab)) { _ in tab = .jobtrail }
        .sheet(item: $adding) { mode in
            switch mode {
            case .block: QuickAddSheet().presentationDetents([.large])
            case .words: PlanWithWordsSheet().presentationDetents([.large])
            case .photo: PhotoTaskSheet().presentationDetents([.large])   // v36: replaces Scan to blocks
            }
        }
    }
}



// MARK: - v18 tab switch: quick crossfade

/// When a tab becomes active, its content fades in over 0.2s and rises 6pt.
private struct TabFade: ViewModifier {
    let active: Bool
    @State private var shown = true

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 4)      // v57: JobTrail pop
            .offset(y: shown ? 0 : 6)
            .onChange(of: active) { _, isActive in
                guard isActive else { return }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { shown = false }
                DispatchQueue.main.async {
                    withAnimation(HDEase.entry(0.45)) { shown = true }
                }
            }
    }
}

extension View {
    func tabFade(_ active: Bool) -> some View { modifier(TabFade(active: active)) }
}

// MARK: - Swipe row (Today list lives in a ScrollView, where .swipeActions isn't available)

struct SwipeAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
}

struct SwipeRow<Content: View>: View {
    var leading: [SwipeAction] = []
    var trailing: [SwipeAction] = []
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    private let width: CGFloat = 80

    private var maxLeft: CGFloat { CGFloat(leading.count) * width }
    private var maxRight: CGFloat { CGFloat(trailing.count) * width }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(leading) { button($0) }
                Spacer(minLength: 0)
                ForEach(trailing) { button($0) }
            }
            content()
                .background(Theme.card)
                .overlay {
                    if offset != 0 {
                        Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                    }
                }
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            offset = min(max(startOffset + v.translation.width, -maxRight), maxLeft)
                        }
                        .onEnded { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else {
                                withAnimation(HDEase.standard(0.4)) { offset = startOffset }
                                return
                            }
                            let target = startOffset + v.predictedEndTranslation.width
                            withAnimation(HDEase.standard(0.4)) {
                                if target < -width / 2 && maxRight > 0 { offset = -maxRight }
                                else if target > width / 2 && maxLeft > 0 { offset = maxLeft }
                                else { offset = 0 }
                            }
                            startOffset = offset
                        }
                )
        }
        .clipped()
    }

    private func button(_ a: SwipeAction) -> some View {
        Button {
            close()
            a.action()
        } label: {
            VStack(spacing: 4) {
                HDIcon(a.icon, size: 20)
                Text(a.title).font(.hd(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(a.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a.title)
    }

    private func close() {
        withAnimation(HDEase.standard(0.4)) { offset = 0 }
        startOffset = 0
    }
}


/// The round + (black in light mode, white in dark). Tap adds a block; press and hold blurs the screen
/// and shows Add block · Plan with words · Scan to blocks (our own menu, so the blur is strong and consistent).
struct AddFab: View {
    let open: (RootView.AddMode) -> Void

    /// v35b: Apple's own pattern: Menu with a primary action. Tap = Add block; touch and hold = the system
    /// menu (Add block · Plan with words · Photo task), same as before but drawn by iOS.
    var body: some View {
        Menu {
            Button { open(.block) } label: { Label("Add block", systemImage: "plus") }
            if AIPlanner.isAvailable {
                Button { open(.words) } label: { Label("Plan with words", systemImage: "waveform") }
            }
            Button { open(.photo) } label: { Label("Photo task", systemImage: "camera") }
        } label: {
            PlusMark(weight: 3.2)   // v55: drawn, so it's exactly centred
                .fill(.black)       // v57: black on amber
                .frame(width: 24, height: 24)
                .frame(width: 58, height: 58)
                .modifier(BlueGlassCircle())
                .hdGlow(radius: 16, active: false, hot: true)   // v58: the + breathes amber
                .contentShape(Chamfer(cut: 14))
        } primaryAction: {
            open(.block)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Add block")
        .accessibilityHint("Touch and hold for Plan with words or Photo task")
        .padding(.trailing, 20)
        .padding(.bottom, 72)   // above the tab bar, in thumb reach
    }
}


/// v14: each tab gets Apple's large title (like the TV app) that shrinks into the bar as you scroll,
/// with your profile circle at the top right.
struct TabRoot<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var showProfile = false
    @EnvironmentObject private var activity: LiveActivityManager

    var body: some View {
        NavigationStack {
            content()
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 64) }   // v59: room for the JobTrail switcher
                .toolbar(.hidden, for: .tabBar)
                .background(DotPage())
                .overlay { JTGrain().ignoresSafeArea() }   // v58: JobTrail film grain
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    // The HYPERDAY wordmark stays top-left, above the large title.
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 10) {
                            Text("HYPERDAY")
                                .font(.hdMono(size: 13, weight: .semibold))   // v57: JobTrail mono wordmark
                                .kerning(2.4)
                                .foregroundStyle(Theme.text)
                                .fixedSize()
                                .accessibilityAddTraits(.isHeader)
                            // v58: JobTrail topbar badge: LIVE pulses green while the Live Activity runs.
                            JTBadge(text: activity.isRunning ? "Live" : "Idle", working: activity.isRunning)
                                .fixedSize()
                        }
                    }
                    .noGlass()
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            AppearanceButton()
                            ProfileButton { showProfile = true }
                        }
                    }
                    .noGlass()
                }
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet().presentationDetents([.large])
        }
    }
}


extension ToolbarContent {
    /// iOS 26 puts a Liquid Glass bubble behind toolbar items; our wordmark and avatar sit bare.
    @ToolbarContentBuilder
    func noGlass() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}


extension Notification.Name {
    static let openCarTab = Notification.Name("hyperday.openCarTab")
    static let openJobTrailTab = Notification.Name("hyperday.openJobTrailTab")   // Macs widgets → JobTrail tab   // car widgets → Car tab
}


// MARK: - v59 JobTrail switcher (bottom navigation)

/// JobTrail's `.switcher`: a dark rounded track, the chosen tab gets the hover fill, which slides between
/// tabs with the standard easing. Mono labels, amber icon when selected, a live dot on Today while the
/// Live Activity runs.
struct JTTabBar: View {
    @Binding var tab: AppTab
    let calDay: Int
    var live: Bool
    @Namespace private var ns
    @ObservedObject private var jobtrail = JobTrailLive.shared
    private var macsBusy: Bool { jobtrail.runningTotal > 0 }

    private var tabs: [AppTab] { [.today, .calendar, .jobtrail] + (Features.car ? [.car] : []) + [.stats, .settings] }

    @ViewBuilder
    private func icon(_ t: AppTab, on: Bool) -> some View {
        switch t {
        case .calendar: Image("hd-tab-cal-\(calDay)").renderingMode(.template).resizable().scaledToFit()
        case .car: Image("hd-tab-car-front").renderingMode(.template).resizable().scaledToFit()
        case .today: Image(systemName: "clock").resizable().scaledToFit().fontWeight(.medium)
        case .jobtrail: JTECGShape().stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))   // JobTrail's pulse
        case .stats: Image(systemName: "chart.bar").resizable().scaledToFit().fontWeight(.medium)
        default: Image(systemName: "gearshape").resizable().scaledToFit().fontWeight(.medium)
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { t in
                let on = tab == t
                Button {
                    withAnimation(HDEase.standard(0.45)) { tab = t }
                    // v60: every tap also brings that page back to the top.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        NotificationCenter.default.post(name: .jtScrollTop, object: t.rawValue)
                    }
                } label: {
                    VStack(spacing: 4) {
                        icon(t, on: on)
                            .frame(width: 19, height: 19)
                            .foregroundStyle(on ? HDTone.amber : HDTone.dim)
                            .scaleEffect(on ? 1.08 : 1)
                            .shadow(color: on ? HDTone.amber.opacity(0.5) : .clear, radius: 6)
                        Text(t.title.uppercased())
                            .font(.mono(9, .semibold)).kerning(0.4)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .foregroundStyle(on ? HDTone.textHi : HDTone.faintDark)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(HDTone.hover)
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(HDTone.amber.opacity(0.3), lineWidth: 1))
                                .matchedGeometryEffect(id: "jt-tab", in: ns)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if t == .today && live {
                            JTStatusDot(status: .running, size: 5).offset(x: -8, y: 2)
                        }
                        if t == .jobtrail && macsBusy {
                            JTStatusDot(status: .running, size: 5).offset(x: -6, y: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(JTPressStyle())
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(HDTone.surface.opacity(0.94)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(HDTone.hover, lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 18, y: 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        .sensoryFeedback(.selection, trigger: tab)
    }
}
