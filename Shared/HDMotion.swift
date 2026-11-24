import SwiftUI
import UIKit

// v57 JobTrail motion. One place for the easing curves and the looping effects, so the app,
// widgets and Live Activities move the same way. Every loop is driven by TimelineView (no state
// to get stuck), pauses when Reduce Motion is on, and draws a calm still frame instead.
// Widgets and Live Activities don't run loops (iOS renders them as snapshots): they get the still frame.

enum HDEase {
    /// Standard: cubic-bezier(.32,.72,0,1)
    static func standard(_ duration: Double = 0.35) -> Animation { .timingCurve(0.32, 0.72, 0, 1, duration: duration) }
    /// Entry: cubic-bezier(.23,1,.32,1)
    static func entry(_ duration: Double = 0.6) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
}

/// Green = running, amber = waiting, blue = done, red = failed.
enum HDStatus {
    case running, waiting, done, failed, idle
    var color: Color {
        switch self {
        case .running: return HDTone.green
        case .waiting: return HDTone.amber
        case .done: return HDTone.blue
        case .failed: return HDTone.danger
        case .idle: return HDTone.faintDark
        }
    }
    var background: Color {
        switch self {
        case .running: return HDTone.greenBG
        case .waiting: return HDTone.amberBG
        case .done: return HDTone.blueBG
        case .failed: return HDTone.dangerBG
        case .idle: return HDTone.hover
        }
    }
}

private func loopPhase(_ date: Date, period: Double, offset: Double = 0) -> Double {
    let t = date.timeIntervalSinceReferenceDate + offset
    return t.truncatingRemainder(dividingBy: period) / period
}

// MARK: - Live status dot (opacity 1 → 0.35 → 1, 1.6s)

struct PulseDot: View {
    var color: Color
    var size: CGFloat = 6
    var live: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live || reduce)) { ctx in
            let p = loopPhase(ctx.date, period: 1.6)
            let k = (1 - cos(p * 2 * .pi)) / 2            // ease-in-out 0 → 1 → 0
            Circle().fill(color)
                .frame(width: size, height: size)
                .opacity(live && !reduce ? 1 - 0.65 * k : 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Ripple rings (busy items): scale 1 → 2.3, opacity .7 → 0

struct RippleRings: View {
    var color: Color
    var size: CGFloat = 8
    var period: Double = 1.8
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce)) { ctx in
            ZStack {
                if !reduce {
                    ForEach(0..<2, id: \.self) { i in
                        let p = loopPhase(ctx.date, period: period, offset: Double(i) * period / 2)
                        let e = 1 - pow(1 - p, 3)
                        Circle().stroke(color, lineWidth: 1)
                            .frame(width: size, height: size)
                            .scaleEffect(1 + 1.3 * e)
                            .opacity(0.7 * (1 - p))
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Sweeping green ring (running items), 2.4s per turn

struct SweepRing: View {
    var radius: CGFloat = 12
    var color: Color = HDTone.green
    var lineWidth: CGFloat = 1.2
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce)) { ctx in
            let angle = reduce ? 0 : loopPhase(ctx.date, period: 2.4) * 360
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                shape.strokeBorder(color.opacity(0.28), lineWidth: 1)
                if !reduce {
                    shape.strokeBorder(
                        AngularGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.70),
                            .init(color: color, location: 0.88),
                            .init(color: Color(UIColor(hd: 0xCFEEC2)), location: 0.92),
                            .init(color: .clear, location: 0.96),
                            .init(color: .clear, location: 1),
                        ], center: .center, angle: .degrees(angle)),
                        lineWidth: lineWidth)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Flowing connector line (moving dashes)

enum FlowState {
    case running, waiting, writing, idle
    var color: Color {
        switch self {
        case .running: return HDTone.green
        case .waiting: return HDTone.amber
        case .writing: return HDTone.blue
        case .idle: return HDTone.lineDark
        }
    }
    /// JobTrail: run 1.1s, wait 3.5s, write 1s per 16pt of dash.
    var period: Double {
        switch self { case .running: return 1.1; case .waiting: return 3.5; case .writing: return 1.0; case .idle: return 0 }
    }
    var flowOpacity: Double {
        switch self { case .running: return 0.75; case .waiting: return 0.55; case .writing: return 0.7; case .idle: return 0 }
    }
    var base: Color {
        switch self {
        case .running: return Color(UIColor(hd: 0x2F4A33))
        case .waiting: return Color(UIColor(hd: 0x4A3A1E))
        case .writing: return Color(UIColor(hd: 0x2C3D4D))
        case .idle: return Color(UIColor(hd: 0x2A2A2A))
        }
    }
}

struct FlowLine: View {
    var state: FlowState
    var vertical: Bool = true
    var lineWidth: CGFloat = 1.6
    @Environment(\.accessibilityReduceMotion) private var reduce

    private func line(_ size: CGSize) -> Path {
        var p = Path()
        if vertical {
            p.move(to: CGPoint(x: size.width / 2, y: 0)); p.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        } else {
            p.move(to: CGPoint(x: 0, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        }
        return p
    }

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce || state == .idle)) { ctx in
                let phase = state == .idle || reduce ? 0 : -loopPhase(ctx.date, period: state.period) * 16
                ZStack {
                    line(g.size).stroke(state.base,
                                        style: StrokeStyle(lineWidth: 1.4, dash: state == .waiting ? [3, 4] : []))
                    if state != .idle {
                        line(g.size).stroke(state.color.opacity(state.flowOpacity),
                                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                                                               dash: [2, 14], dashPhase: phase))
                    }
                    // v59: a glowing pulse travels along the line (JobTrail map dots).
                    if state != .idle && !reduce {
                        let p = loopPhase(ctx.date, period: state.period * 1.6)
                        Circle().fill(state.color)
                            .frame(width: 4, height: 4)
                            .shadow(color: state.color, radius: 3)
                            .opacity(sin(p * .pi))
                            .position(x: vertical ? g.size.width / 2 : g.size.width * p,
                                      y: vertical ? g.size.height * p : g.size.height / 2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Modifiers

/// New items fade in from a 4px blur over 600ms (entry easing).
private struct BlurIn: ViewModifier {
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    init(enabled: Bool) { _shown = State(initialValue: !enabled) }
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 4)
            .onAppear {
                guard !shown else { return }
                if reduce { shown = true } else { withAnimation(HDEase.entry(0.6)) { shown = true } }
            }
    }
}

/// New rows briefly flash (#2a2a1a fading out over 1.6s).
private struct RowFlash: ViewModifier {
    @State private var lit: Bool
    init(enabled: Bool) { _lit = State(initialValue: enabled) }
    func body(content: Content) -> some View {
        content
            .background(Color(UIColor(hd: 0x2A2A1A)).opacity(lit ? 1 : 0))
            .onAppear {
                guard lit else { return }
                DispatchQueue.main.async { withAnimation(HDEase.entry(1.6)) { lit = false } }
            }
    }
}

/// Active card: amber border + soft amber glow. Hot card: the glow breathes (2.6s).
private struct CardGlow: ViewModifier {
    var radius: CGFloat
    var active: Bool
    var hot: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .overlay(shape.strokeBorder(active || hot ? HDTone.amber.opacity(0.55) : Color.clear, lineWidth: 1))
            .background {
                if hot && !reduce {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let k = (1 - cos(loopPhase(ctx.date, period: 2.6) * 2 * .pi)) / 2
                        shape.stroke(HDTone.amber.opacity(0.10 + 0.22 * k), lineWidth: 6)
                            .blur(radius: 8 + 6 * k)
                    }
                } else if active || hot {
                    shape.stroke(HDTone.amber.opacity(0.16), lineWidth: 6).blur(radius: 10)
                }
            }
    }
}

/// Things being written shimmer: a soft blue band sweeps across (1.8s).
private struct Shimmer: ViewModifier {
    var active: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduce {
                GeometryReader { g in
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let p = loopPhase(ctx.date, period: 1.8)
                        LinearGradient(colors: [.clear, color.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width)
                            .offset(x: (p * 2 - 1) * g.size.width)
                    }
                }
                .clipped()
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func hdBlurIn(_ enabled: Bool = true) -> some View { modifier(BlurIn(enabled: enabled)) }
    func hdRowFlash(_ enabled: Bool) -> some View { modifier(RowFlash(enabled: enabled)) }
    func hdGlow(radius: CGFloat = 16, active: Bool = true, hot: Bool = false) -> some View {
        modifier(CardGlow(radius: radius, active: active, hot: hot))
    }
    func hdShimmer(_ active: Bool = true, color: Color = HDTone.blue) -> some View {
        modifier(Shimmer(active: active, color: color))
    }
}

/// JobTrail status pill: tiny mono caps on the status tint ("RUNNING", "IN 12M").
struct StatusTag: View {
    let text: String
    var status: HDStatus
    var body: some View {
        Text(text.uppercased())
            .font(.mono(10, .semibold))
            .kerning(0.6)
            .foregroundStyle(status.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(status.background))
    }
}

// MARK: - More JobTrail motion (v57b)

/// Waiting items: the hourglass holds, then flips 180° (3s loop, standard easing). JobTrail `tilt`.
struct TiltingHourglass: View {
    var color: Color = HDTone.amber
    var size: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce)) { ctx in
            let p = reduce ? 0 : loopPhase(ctx.date, period: 3)
            // 0–40% hold, 40–60% turn, 60–100% hold (turned).
            let x = min(max((p - 0.4) / 0.2, 0), 1)
            let eased = 1 - pow(1 - x, 4)
            Image(systemName: "hourglass")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .rotationEffect(.degrees(180 * eased))
        }
        .accessibilityHidden(true)
    }
}

/// Busy icons turn slowly (JobTrail `spin`: 6s busy, 2.8s driving).
struct Spinning: ViewModifier {
    var period: Double
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active || reduce)) { ctx in
            content.rotationEffect(.degrees(active && !reduce ? loopPhase(ctx.date, period: period) * 360 : 0))
        }
    }
}

/// Typing cursor ▋ that blinks while something is being written.
struct BlinkCursor: View {
    var color: Color = HDTone.blue
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let on = reduce || Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Text("▋").font(.mono(12)).foregroundStyle(color).opacity(on ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}

/// JobTrail `.bar`: 4pt track, the fill glides to its new width (600ms, entry easing).
struct HDProgressBar: View {
    var value: Double          // 0…1
    var color: Color = HDTone.amber
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(HDTone.hover)
                Capsule().fill(color).frame(width: max(4, g.size.width * min(max(value, 0), 1)))
                    .animation(HDEase.entry(0.6), value: value)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

extension View {
    func hdSpin(period: Double = 6, active: Bool = true) -> some View { modifier(Spinning(period: period, active: active)) }
}
