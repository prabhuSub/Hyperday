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

    static let bg = dyn(0xFFFFFF, 0x111112)
    static let section = dyn(0xF4F4F4, 0x18181A)
    static let card = dyn(0xFFFFFF, 0x1E1E20)
    static let border = dyn(0xE0E0E0, 0x2E2E31)
    static let text = dyn(0x171A20, 0xF4F4F4)
    static let muted = dyn(0x5C5E62, 0xA2A3A5)
    static let faint = dyn(0xA2A3A5, 0x5C5E62)
    static let navActive = dyn(0xEEEEEE, 0x2A2A2D)
    static let blue = Color(UIColor(rgb: 0x3E6AE1))
    static let red = Color(UIColor(rgb: 0xE31937))
}

enum Appearance: String, CaseIterable, Hashable {
    case system, light, dark

    var label: String { rawValue.capitalized }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Header: HYPERDAY | Section              [theme]

struct HeaderBar: View {
    let section: String
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    private var current: Appearance { Appearance(rawValue: appearance) ?? .system }

    var body: some View {
        HStack(spacing: 10) {
            Text("HYPERDAY")
                .font(.system(size: 14, weight: .heavy))
                .kerning(5)
                .foregroundStyle(Theme.text)
            Rectangle().fill(Theme.border).frame(width: 1, height: 16)
            Text(section)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                // System → Light → Dark → System
                let now = Appearance(rawValue: appearance) ?? .system
                appearance = (now == .system ? Appearance.light : now == .light ? .dark : .system).rawValue
            } label: {
                HDIcon(current == .system ? "auto" : current == .light ? "sun" : "moon", size: 17)
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
            .font(.system(size: 10, weight: .bold))
            .kerning(1.4)
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
        acc + Text(String(ch)).font(.system(size: (ch.isNumber || ch == "—") ? size : size * 0.5, weight: .heavy))
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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
        }
    }
}

// MARK: - Buttons (Hire Me / Download CV)

struct PrimaryButtonStyle: ButtonStyle {
    var width: CGFloat? = nil   // nil = full width
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: width ?? .infinity)
            .frame(height: 40)
            .background(Capsule().fill(Theme.blue))   // v24: pill buttons
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var width: CGFloat? = nil   // nil = full width
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: width ?? .infinity)
            .frame(height: 40)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Card

struct CardBox: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))   // v24: rounder
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? (color ?? Theme.text) : Theme.text)
            // v34: Apple-style tinted capsules. Selected = the category's colour at 15%, others = system fill.
            .background(Capsule().fill(selected ? (color ?? Theme.text).opacity(color == nil ? 0.10 : 0.16)
                                                : Color(UIColor.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }
}

/// v27: the + button's blue Liquid Glass (iOS 26+); a solid blue circle on iOS 18–25.
struct BlueGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(Theme.blue).interactive(), in: Circle())
        } else {
            content
                .background(Circle().fill(Theme.blue))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
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
            Circle().fill(color).frame(width: 28, height: 28)
                .overlay(HDIcon(icon, size: 15).foregroundStyle(.white))
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
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
                    withAnimation(.snappy(duration: 0.2)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(on ? Theme.bg : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(on ? Theme.text : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
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

    private var detail: String {
        var parts: [String] = []
        parts.append(block.start.shortTime)   // v24: time moves into the subtitle
        parts.append(block.source == .calendar ? (block.calendarName ?? "Calendar") : "My plan")
        parts.append(block.end.timeIntervalSince(block.start).hoursMinutes)
        if !steps.isEmpty { parts.append("\(steps.filter(\.done).count)/\(steps.count) steps") }
        if block.declined { parts.append("Declined") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let isNow = showNow && block.contains(now)
        let done = block.end <= now

        HStack(spacing: 12) {
            // v24: the block's icon on a dot of its category color.
            Circle()
                .fill(color.opacity(done ? 0.35 : 1))
                .frame(width: 30, height: 30)
                .overlay(HDIcon(icon ?? "event", size: 16).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: 15, weight: isNow ? .semibold : .regular))
                    .foregroundStyle(done ? Theme.faint : Theme.text)
                    .strikethrough(block.declined)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(done ? Theme.faint : Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let pill {
                RowPillView(pill: pill, now: now)
            } else if block.source == .calendar && !isNow {
                // Calendar events are read-only in Hyperday (can't be moved or deleted here).
                HDIcon("event", size: 14)
                    .foregroundStyle(Theme.faint)
                    .accessibilityLabel("Calendar event")
            }
            if isNow && pill == nil {
                Text("NOW")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(pill?.isLive == true ? DayLiveStyle.doneGreen.opacity(0.07) : .clear)
        .contentShape(Rectangle())
    }
}

// MARK: - v17 appearance button (next to the profile circle)

/// Same grey circle as the profile. Tap cycles System → Light → Dark; the icon shows the current mode.
struct AppearanceButton: View {
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    private var current: Appearance { Appearance(rawValue: appearance) ?? .system }

    var body: some View {
        Button {
            appearance = (current == .system ? Appearance.light : current == .light ? .dark : .system).rawValue
        } label: {
            HDIcon(current == .system ? "auto" : current == .light ? "sun" : "moon", size: 16)
                .foregroundStyle(Theme.text)
                .frame(width: 32, height: 32)   // no background: just the icon
                .contentShape(Circle())
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

    var body: some View {
        switch pill {
        case .live(let end):
            HStack(spacing: 5) {
                Circle().fill(DayLiveStyle.doneGreen).frame(width: 6, height: 6)
                Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                    .monospacedDigit()
                Text("left")
            }
            .modifier(PillShape(fill: DayLiveStyle.doneGreen.opacity(0.15), text: Color(red: 0.11, green: 0.48, blue: 0.21)))
        case .over(let since):
            HStack(spacing: 0) {
                Text("+")
                Text(timerInterval: since...since.addingTimeInterval(24 * 3600), countsDown: false)
                    .monospacedDigit()
                Text(" over")
            }
            .modifier(PillShape(fill: Color(red: 1, green: 0.84, blue: 0.04).opacity(0.25), text: Color(red: 0.54, green: 0.43, blue: 0)))
        case .upcoming(let start):
            Text("in \(start.timeIntervalSince(now).hoursMinutes)")
                .monospacedDigit()
                .modifier(PillShape(fill: .clear, text: Theme.muted, stroke: Theme.border))
        case .done:
            Text("✓ Done").modifier(PillShape(fill: Theme.border.opacity(0.6), text: Theme.muted))
        case .ended:
            Text("Ended").modifier(PillShape(fill: Theme.border.opacity(0.6), text: Theme.faint))
        }
    }
}

private struct PillShape: ViewModifier {
    let fill: Color
    let text: Color
    var stroke: Color? = nil
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(stroke ?? .clear, lineWidth: 1))
    }
}

/// The live timer on the Today card (ticks every second via Text(timerInterval:)).
struct LiveTimerPill: View {
    let range: ClosedRange<Date>
    let down: Bool
    var prefix: String = ""
    let fill: Color
    let text: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(text).frame(width: 7, height: 7)
            HStack(spacing: 0) {
                if !prefix.isEmpty { Text(prefix) }
                Text(timerInterval: range, countsDown: down).monospacedDigit()
            }
        }
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(text)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(fill))
    }
}

// MARK: - Floating tab bubble

/// v35: switches for whole sections of the app.
enum Features {
    /// The Car tab, its Settings page, background reads and car widgets. Off while Prabhu reviews it.
    static let car = false
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, calendar, car, stats, settings, add
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .today: return "today"
        case .calendar: return "calendar"
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
    @State private var tab: AppTab = .today
    @State private var adding: AddMode?
    @Environment(\.scenePhase) private var scenePhase

    enum AddMode: String, Identifiable { case block, words, scan; var id: String { rawValue } }

    var body: some View {
        // v35: Apple's own tab bar (Liquid Glass on iOS 26), SF Symbols, blue when selected.
        // The + is a search-role tab, so iOS draws it as its own glass circle beside the bar.
        // Tapping it never shows a page: we jump back and open Add block.
        TabView(selection: $tab) {
            Tab("Today", systemImage: "clock", value: AppTab.today) {
                TabRoot(title: "Today") { TodayView().tabFade(tab == .today) }
            }
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                TabRoot(title: "Calendar") { CalendarTabView().tabFade(tab == .calendar) }
            }
            if Features.car {
                Tab("Car", systemImage: "car", value: AppTab.car) {
                    TabRoot(title: "Car") { CarView().tabFade(tab == .car) }
                }
            }
            Tab("Stats", systemImage: "chart.bar", value: AppTab.stats) {
                TabRoot(title: "Stats") { StatsView().tabFade(tab == .stats) }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                TabRoot(title: "Settings") { SettingsView().tabFade(tab == .settings) }
            }
            Tab("Add", systemImage: "plus", value: AppTab.add, role: .search) {
                Color.clear
            }
        }
        .tint(Theme.blue)
        .onChange(of: tab) { old, new in
            guard new == .add else { return }
            tab = old == .add ? .today : old
            adding = .block
        }
        .onReceive(NotificationCenter.default.publisher(for: CalendarJump.notification)) { _ in
            tab = .calendar
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCarTab)) { _ in if Features.car { tab = .car } }
        .sheet(item: $adding) { mode in
            switch mode {
            case .block: QuickAddSheet().presentationDetents([.large])
            case .words: PlanWithWordsSheet().presentationDetents([.large])
            case .scan: ScanSheet().presentationDetents([.large])
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
            .offset(y: shown ? 0 : 6)
            .onChange(of: active) { _, isActive in
                guard isActive else { return }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { shown = false }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) { shown = true }
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
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = startOffset }
                                return
                            }
                            let target = startOffset + v.predictedEndTranslation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
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
                Text(a.title).font(.system(size: 11, weight: .semibold))
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = 0 }
        startOffset = 0
    }
}


/// The round + (black in light mode, white in dark). Tap adds a block; press and hold blurs the screen
/// and shows Add block · Plan with words · Scan to blocks (our own menu, so the blur is strong and consistent).
struct AddFab: View {
    let open: (RootView.AddMode) -> Void
    @State private var menu = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if menu {
                ZStack {
                    // Glossy glass: a full-strength frosted blur, a light white wash,
                    // and a sheen from the top-left so it reads as glass, not fog.
                    // v23: the whole glass effect at 80% (20% less), same look.
                    Rectangle().fill(.thinMaterial).opacity(0.8)
                    Color.white.opacity(0.12)   // v32: flat wash, the gloss gradient is gone
                }
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                VStack(spacing: 0) {
                    item("Add block", "add", .block)
                    if AIPlanner.isAvailable {
                        Divider()
                        item("Plan with words", "siri", .words)
                    }
                    Divider()
                    item("Scan to blocks", "calendar-scan", .scan)
                }
                .frame(width: 240)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
                .padding(.trailing, 20)
                .padding(.bottom, 72 + 72)
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
            // v27: Liquid Glass tinted blue (Apple's rule for the main floating action), thick white plus.
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(menu ? 45 : 0))
                .frame(width: 58, height: 58)
                .modifier(BlueGlassCircle())
                .contentShape(Circle())
                .onTapGesture { menu ? close() : open(.block) }
                .onLongPressGesture(minimumDuration: 0.35) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { menu = true }
                }
                .accessibilityLabel("Add block")
                .accessibilityHint("Press and hold for Plan with words or Scan to blocks")
                .accessibilityAction(named: "More ways to add") { menu = true }
                .padding(.trailing, 20)
                .padding(.bottom, 72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func item(_ title: String, _ icon: String, _ mode: RootView.AddMode) -> some View {
        Button {
            close()
            open(mode)
        } label: {
            HStack {
                Text(title).font(.system(size: 16))
                Spacer()
                HDIcon(icon, size: 20)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func close() { withAnimation(.easeOut(duration: 0.2)) { menu = false } }
}


/// v14: each tab gets Apple's large title (like the TV app) that shrinks into the bar as you scroll,
/// with your profile circle at the top right.
struct TabRoot<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            content()
                .background(Theme.section)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    // The HYPERDAY wordmark stays top-left, above the large title.
                    ToolbarItem(placement: .topBarLeading) {
                        Text("HYPERDAY")
                            .font(.system(size: 14, weight: .heavy))
                            .kerning(5)
                            .foregroundStyle(Theme.text)
                            .fixedSize()
                            .accessibilityAddTraits(.isHeader)
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
    static let openCarTab = Notification.Name("hyperday.openCarTab")   // car widgets → Car tab
}
