import SwiftUI

/// v32: Apple Timer–style duration picker. A ruler of fine ticks slides under a fixed marker;
/// drag it and the value snaps to `step` minutes with a light haptic. Flat colour, no gradients.
/// Used for Add block, Edit block and Extend.
struct DurationRuler: View {
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 5...720
    var step: Int = 5
    var tint: Color = Theme.blue

    private let perMinute: CGFloat = 8          // points per minute (v32b: wider for thicker ticks)
    @State private var dragStart: Int?
    @State private var live: CGFloat?           // un-snapped value while dragging, so the ruler glides

    var body: some View {
        let value = live ?? CGFloat(minutes)
        Canvas { ctx, size in
            let mid = size.width / 2
            let tickBottom = size.height - 14
            let half = Int(mid / perMinute) + 2
            let lo = max(range.lowerBound, Int(value) - half), hi = min(range.upperBound, Int(value) + half)
            guard lo <= hi else { return }
            for m in lo...hi {
                let x = mid + (CGFloat(m) - value) * perMinute
                guard x > -2, x < size.width + 2 else { continue }
                let fade = max(0.18, 1 - abs(x - mid) / mid * 0.85)
                let major = m % 5 == 0
                let tall: CGFloat = major ? 26 : 16
                let w: CGFloat = major ? 3.6 : 3    // v32b: thicker
                let r = CGRect(x: x - w / 2, y: tickBottom - tall, width: w, height: tall)
                ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(tint.opacity(major ? fade : fade * 0.7)))
                if m % 10 == 0 {
                    let label = ctx.resolve(Text(Self.short(m)).font(.system(size: 13, weight: .semibold))
                        .monospacedDigit().foregroundStyle(tint.opacity(fade)))
                    ctx.draw(label, at: CGPoint(x: x, y: 8), anchor: .center)
                }
            }
            var tri = Path()
            tri.move(to: CGPoint(x: mid, y: tickBottom + 3))
            tri.addLine(to: CGPoint(x: mid + 7, y: tickBottom + 12))
            tri.addLine(to: CGPoint(x: mid - 7, y: tickBottom + 12))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(tint))
        }
        .frame(height: 62)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { g in
                    let base = dragStart ?? minutes
                    if dragStart == nil { dragStart = minutes }
                    let raw = CGFloat(base) - g.translation.width / perMinute
                    let clamped = min(CGFloat(range.upperBound), max(CGFloat(range.lowerBound), raw))
                    live = clamped
                    let snapped = Int((clamped / CGFloat(step)).rounded()) * step
                    let v = min(range.upperBound, max(range.lowerBound, snapped))
                    if v != minutes { minutes = v }
                }
                .onEnded { _ in
                    dragStart = nil
                    withAnimation(.spring(duration: 0.25)) { live = nil }
                }
        )
        .sensoryFeedback(.selection, trigger: minutes)
        .accessibilityElement()
        .accessibilityLabel("Length")
        .accessibilityValue(Self.long(minutes))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: minutes = min(range.upperBound, minutes + step)
            case .decrement: minutes = max(range.lowerBound, minutes - step)
            @unknown default: break
            }
        }
    }

    /// Ruler labels: "50", "1h", "1h10".
    static func short(_ m: Int) -> String {
        if m < 60 { return "\(m)" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(m % 60)"
    }
    static func long(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r) min" }
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }
}

/// Big thin readout that sits beside the ruler: "45 min", "1h 30m".
struct DurationReadout: View {
    let minutes: Int
    var tint: Color = Theme.blue
    var body: some View {
        let h = minutes / 60, m = minutes % 60
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if h > 0 {
                Text("\(h)").font(.system(size: 40, weight: .light)).monospacedDigit()
                Text("h").font(.system(size: 16, weight: .semibold))
                if m > 0 {
                    Text(" \(m)").font(.system(size: 40, weight: .light)).monospacedDigit()
                    Text("m").font(.system(size: 16, weight: .semibold))
                }
            } else {
                Text("\(m)").font(.system(size: 40, weight: .light)).monospacedDigit()
                Text(" min").font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(tint)
        .contentTransition(.numericText())
        .animation(.snappy, value: minutes)
    }
}
