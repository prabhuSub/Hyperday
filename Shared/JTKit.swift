import SwiftUI
import UIKit

// v58 JTKit: JobTrail's components, rebuilt in SwiftUI. Screens are composed from these so the
// whole app (and the widgets) share one vocabulary: section heads, cards with heads, status dots
// with halos, pills, meters with bars, badges, empty boxes, grain.

// MARK: - Status dot with halo (JobTrail .row .st)

/// 8pt dot; running gets a dark-green 4pt halo and pulses, waiting gets an amber halo.
struct JTStatusDot: View {
    var status: HDStatus
    var size: CGFloat = 8
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var halo: Color? {
        switch status {
        case .running: return Color(UIColor(hd: 0x172015))
        case .waiting: return HDTone.amberBG
        case .failed: return HDTone.dangerBG
        default: return nil
        }
    }

    var body: some View {
        let live = animated && !reduce && (status == .running || status == .waiting)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { ctx in
            let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let k = live ? (1 - cos(p * 2 * .pi)) / 2 : 0
            ZStack {
                if let halo { Circle().fill(halo).frame(width: size + 8, height: size + 8).scaleEffect(1 + 0.15 * k) }
                Circle().fill(status.color).frame(width: size, height: size)
                    .opacity(status == .running ? 1 - 0.65 * k : 1)
                    .shadow(color: status == .running ? HDTone.green.opacity(0.6 * (1 - k)) : .clear, radius: 3)
            }
            .frame(width: size + 8, height: size + 8)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Section head (JobTrail .section-head)

struct JTSectionHead<Trailing: View>: View {
    let title: String
    var sub: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, sub: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.sub = sub; self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title.uppercased())
                .font(.mono(12, .semibold)).kerning(1)
                .foregroundStyle(HDTone.faintDark)
            if let sub { Text(sub).font(.geist(size: 12)).foregroundStyle(HDTone.faintDark) }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

extension JTSectionHead where Trailing == EmptyView {
    init(_ title: String, sub: String? = nil) { self.title = title; self.sub = sub; self.trailing = { EmptyView() } }
}

// MARK: - Pill (JobTrail .pill / .cpill)

enum JTPillKind { case busy, idle, running, done, failed, plain, closed }

struct JTPill: View {
    let text: String
    var kind: JTPillKind = .plain
    var body: some View {
        let (fg, bg, stroke): (Color, Color, Color) = {
            switch kind {
            case .busy: return (HDTone.amber, HDTone.amberBG, HDTone.amberBG)
            case .idle, .running: return (HDTone.green, HDTone.greenBG, Color(UIColor(hd: 0x1D2B22)))
            case .done: return (HDTone.blue, HDTone.blueBG, Color(UIColor(hd: 0x1C2C3A)))
            case .failed: return (HDTone.danger, HDTone.dangerBG, Color(UIColor(hd: 0x3A1D1C)))
            case .plain: return (HDTone.dim, .clear, HDTone.lineDark)
            case .closed: return (HDTone.faintDark, .clear, HDTone.lineDark)
            }
        }()
        Text(text.uppercased())
            .font(.mono(10, .semibold)).kerning(0.6)
            .foregroundStyle(fg)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(stroke, lineWidth: 1))
    }
}

// MARK: - Badge (JobTrail topbar .badge.working)

struct JTBadge: View {
    let text: String
    var working: Bool
    var body: some View {
        HStack(spacing: 7) {
            PulseDot(color: working ? HDTone.green : HDTone.faintDark, size: 6, live: working)
            Text(text.uppercased()).font(.mono(10, .semibold)).kerning(0.8)
        }
        .foregroundStyle(working ? HDTone.green : HDTone.dim)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(working ? HDTone.greenBG : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(working ? Color(UIColor(hd: 0x1D2B22)) : HDTone.lineDark, lineWidth: 1))
        .animation(HDEase.standard(0.4), value: working)
    }
}

// MARK: - Meter (JobTrail .meter: caps key, value, bar)

struct JTMeter: View {
    let key: String
    let value: String
    var fraction: Double? = nil
    var color: Color = HDTone.amber
    var valueColor: Color = HDTone.textHi
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased()).font(.mono(10, .semibold)).kerning(0.8).foregroundStyle(HDTone.faintDark)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.geist(size: 18, weight: .medium)).monospacedDigit()
                .foregroundStyle(valueColor).lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let fraction { JTGrowBar(value: fraction, color: color).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A 4pt bar that grows from 0 when it appears and glides to new values (600ms entry easing).
struct JTGrowBar: View {
    var value: Double
    var color: Color = HDTone.amber
    var height: CGFloat = 4
    @State private var shown = false
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(HDTone.hover)
                Capsule().fill(color)
                    .frame(width: shown ? max(height, g.size.width * min(max(value, 0), 1)) : 0)
            }
        }
        .frame(height: height)
        .animation(HDEase.entry(0.6), value: value)
        .onAppear { withAnimation(HDEase.entry(0.9).delay(0.15)) { shown = true } }
        .accessibilityHidden(true)
    }
}

// MARK: - Card with head (JobTrail .chat / .fleet-card)

enum JTCardState { case normal, glow, hot, down }

struct JTCard<Content: View>: View {
    var state: JTCardState = .normal
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(state == .down ? Color(UIColor(hd: 0x120A0A)) : HDTone.surface))
            .clipShape(shape)
            .overlay(shape.strokeBorder(state == .down ? Color(UIColor(hd: 0x3A1D1C)) : HDTone.lineDark, lineWidth: 1))
            .hdGlow(radius: 16, active: state == .glow, hot: state == .hot)
    }
}

/// Card head row: icon/dot, title, pill, meta on the right, hover-line underneath.
struct JTCardHead<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 10) {
            leading()
            Text(title).font(.geist(size: 14, weight: .semibold)).foregroundStyle(HDTone.textHi).lineLimit(1)
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(HDTone.hover).frame(height: 1) }
    }
}

// MARK: - Empty box (JobTrail .empty)

struct JTEmpty: View {
    let title: String
    var text: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.geist(size: 14, weight: .semibold)).foregroundStyle(HDTone.soft)
            if let text { Text(text).font(.geist(size: 13)).foregroundStyle(HDTone.faintDark).multilineTextAlignment(.center) }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(HDTone.lineDark, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

// MARK: - Grain (JobTrail body:before noise at 2.5%)

struct JTGrain: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: 7)
            let n = Int(size.width * size.height / 30)
            for _ in 0..<n {
                let x = CGFloat(rng.next() % 10_000) / 10_000 * size.width
                let y = CGFloat(rng.next() % 10_000) / 10_000 * size.height
                let a = Double(rng.next() % 100) / 100
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(a)))
            }
        }
        .opacity(0.025 * 2.4)   // dots are sparse; this lands near JobTrail's 2.5% overall
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Staggered entry (cards arrive one after another)

private struct Stagger: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 4)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                if reduce { shown = true; return }
                withAnimation(HDEase.entry(0.6).delay(Double(min(index, 10)) * 0.06)) { shown = true }
            }
    }
}

/// Pressable card: shrinks a touch while pressed (standard easing).
struct JTPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.03 : 0)
            .animation(HDEase.standard(0.25), value: configuration.isPressed)
    }
}

extension View {
    func jtStagger(_ index: Int) -> some View { modifier(Stagger(index: index)) }
}

// MARK: - Reveal (charts draw in from an edge)

private struct Reveal: ViewModifier {
    let anchor: UnitPoint
    let horizontal: Bool
    let delay: Double
    let duration: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .mask {
                Rectangle()
                    .scaleEffect(x: horizontal ? (shown ? 1 : 0.001) : 1, y: horizontal ? 1 : (shown ? 1 : 0.001), anchor: anchor)
            }
            .onAppear {
                guard !shown else { return }
                if reduce { shown = true } else { withAnimation(HDEase.entry(duration).delay(delay)) { shown = true } }
            }
    }
}

extension View {
    /// Draws in from the leading edge (lines) or grows up from the bottom (columns).
    func jtReveal(horizontal: Bool = true, from anchor: UnitPoint = .leading, delay: Double = 0.15, duration: Double = 1.0) -> some View {
        modifier(Reveal(anchor: anchor, horizontal: horizontal, delay: delay, duration: duration))
    }
}
