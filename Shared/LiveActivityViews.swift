import AppIntents
import SwiftUI
import WidgetKit

/// Shared by the widget extension (real Live Activity) and the app (preview card).
enum DayLiveStyle {
    static let accent = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)      // #34c759
    static let cardTint = Color(red: 40 / 255, green: 44 / 255, blue: 66 / 255)
    static let glassOpacity = 0.42
    static let calendarBlue = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
    static let planGreen = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)
    static let stepYellow = Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)   // #FFD60A
    static let doneGreen = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)     // #30D158
}

extension Color {
    /// "#30D158" -> Color
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

extension DayActivityAttributes.ContentState {
    /// v28: without a push server the app can't always wake at the exact minute a block starts, so the
    /// card switches itself. In free time the card goes stale at the next block's start; when iOS redraws
    /// it then, draw the next block as running (it carries the next block's title, end, color and icon).
    func selfSwitched(isStale: Bool, now: Date = .now) -> (state: Self, isStale: Bool) {
        guard isStale, closed != true, driving != true, paused != true,
              source == .free, let start = nextStart, start <= now, let end = nextEnd, end > now
        else { return (self, isStale) }
        var s = self
        s.title = nextTitle ?? "Next"
        s.source = .plan
        s.accentHex = nextHex
        s.iconName = nextIcon
        s.currentStart = start
        s.currentEnd = end
        s.freeStart = nil
        s.nextStart = nil
        s.nextTitle = nil
        s.overSince = nil
        s.action = nil          // the buttons need the real block id; they come back at the next refresh
        s.actionBlockID = nil
        s.canPause = nil
        s.headsUp = nil
        s.headsUpAt = nil
        if let later = laterTitle, let ls = laterStart {
            s.label = "Next · \(later) at \(ls.formatted(date: .omitted, time: .shortened))"
            s.nextHex = laterHex
        } else {
            s.label = "Nothing else today"
            s.nextHex = nil
        }
        s.laterTitle = nil
        return (s, false)
    }

    /// Category color of the live block (bar + icon); green when nothing is live.
    var accentColor: Color { accentHex.map { Color(hex: $0) } ?? DayLiveStyle.accent }
}

// MARK: - Lock Screen card

struct LockScreenCard: View {
    let state: DayActivityAttributes.ContentState
    var isStale: Bool = false
    var inIsland = false   // v24: same card in the expanded Dynamic Island (no outer padding, no edge ticks)

    /// v20: the card goes stale 5 minutes before the end; iOS redraws it in heads-up yellow.
    private var headsUp: Bool {
        isStale && state.headsUp != nil && state.paused != true && (state.headsUpAt.map { Date.now >= $0 } ?? true)
    }

    /// Really out of date (the content should have changed), not just an early planned redraw.
    private var outOfDate: Bool { isStale && (state.boundaryAt.map { Date.now >= $0 } ?? true) }

    /// "4/7 done · 3h 10m focus"
    private var score: String? {
        guard let total = state.totalCount, total > 0 else { return nil }
        var t = "\(state.doneCount ?? 0)/\(total) done"
        if let f = state.focusMinutes, f > 0 { t += " · " + (f >= 60 ? "\(f / 60)h \(f % 60)m" : "\(f)m") + " active" }
        return t
    }

    /// Bar tint: yellow in the last 5 minutes, grey while paused.
    private var barState: DayActivityAttributes.ContentState {
        var s = state
        if state.paused == true { s.accentHex = "#8E8E93" } else if headsUp { s.accentHex = "#FFD60A" }
        return s
    }

    /// "Next · Standup at 10:30 PM" -> "Next: Standup 10:30 PM" (fits the top row)
    private var nextText: String {
        if outOfDate { return "Out of date · tap to refresh" }
        return state.label
            .replacingOccurrences(of: "Next · ", with: "Next: ")
            .replacingOccurrences(of: " at ", with: " ")
    }

    /// "Standup 10:30 AM" from the label "Next · Standup at 10:30 AM".
    private var nextParts: (title: String, time: String)? {
        guard state.label.hasPrefix("Next · "), let r = state.label.range(of: " at ", options: .backwards) else { return nil }
        let title = state.label[state.label.index(state.label.startIndex, offsetBy: 7)..<r.lowerBound]
        return (String(title), String(state.label[r.upperBound...]))
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(white: 0.45).opacity(0.55), in: Capsule())
    }

    /// v13: under the title. Step → [step pill][Next 3:00 pill]; overlap → "also:" text;
    /// otherwise → [Next: Title · 3:00 PM] pill. Free time keeps its own line.
    @ViewBuilder
    private var secondLine: some View {
        if state.alsoIsStep == true, let also = state.also {
            HStack(spacing: 6) {
                pill(also)
                if let n = nextParts { pill("Next \(n.time)").fixedSize() }
            }
        } else if let also = state.also, state.source == .free || also.hasPrefix("also:") {
            Text(also)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        } else if let n = nextParts {
            pill("Next: \(n.title) · \(n.time)")
        } else if let also = state.also {
            Text(also)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    /// v24: the color of what's on now (green in free time, yellow in overtime / last 5 min, grey paused).
    private var nowColor: Color {
        if state.paused == true { return Color(white: 0.75) }
        if state.overSince != nil || headsUp { return DayLiveStyle.stepYellow }
        if state.source == .free { return DayLiveStyle.doneGreen }
        return state.accentColor
    }

    private var endText: String? {
        let d = state.currentEnd ?? state.nextStart
        return d.map { $0.formatted(date: .omitted, time: .shortened) }
    }

    @ViewBuilder
    private var bottomLeft: some View {
        if state.paused == true {
            pill("Paused · the end moves later")
        } else if headsUp, let title = state.headsNextTitle, let start = state.headsNextStart {
            HeadsUpBand(title: title, start: start, place: state.headsNextPlace,
                        color: state.headsNextHex.map { Color(hex: $0) } ?? DayLiveStyle.stepYellow)
        } else if state.alsoIsStep == true, let also = state.also {
            pill(also)
        } else if let also = state.also, also.hasPrefix("also:") {
            Text(also).font(.system(size: 13)).opacity(0.8).lineLimit(1)
        } else if let n = nextParts {
            HStack(spacing: 8) {
                let col = state.nextHex.map { Color(hex: $0) } ?? Color(white: 0.5)
                Circle().fill(col).frame(width: 24, height: 24)
                    .overlay(HDIcon(state.nextIcon ?? "event", size: 14).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Next: \(n.title)").font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(score.map { "\(n.time) · \($0)" } ?? n.time)
                        .contentTransition(.numericText())
                        .font(.system(size: 11.5, weight: .medium)).opacity(0.65).lineLimit(1)
                }
            }
        } else if let score {
            Text(score).contentTransition(.numericText()).font(.system(size: 13, weight: .semibold)).opacity(0.75)
        }
    }

    /// v28: each state is its own layout, exactly as mocked in v24.
    ///   B · last 5 minutes → Now → Next flight card.  C · free time → Now / Next / Later capsules.  A · otherwise.
    var body: some View {
        Group {
            if headsUp, let next = state.headsNextTitle, let nextStart = state.headsNextStart {
                NowNextStrip(title: state.title, start: state.currentStart, end: state.currentEnd,
                             next: next, nextStart: nextStart, color: state.accentColor, icon: state.iconName,
                             big: inIsland ? 19 : 24)
            } else if state.source == .free, state.nextStart != nil {
                PhasesStrip(state: state, inIsland: inIsland)
            } else {
                journey
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, inIsland ? 4 : 14)   // v26: the same gap on every side (concentric)
        .padding(.vertical, inIsland ? 2 : 14)
        .background { if !inIsland { EdgeTicks(state: state, headsUp: headsUp) } }   // v23: ticks around the card
    }

    /// v24 A · "day as a journey" card (Uber / delivery style), in Hyperday's colors.
    private var journey: some View {
        VStack(alignment: .leading, spacing: inIsland ? 6 : 8) {
            // 1 · What's on + time left ·························· ends at
            HStack(spacing: 7) {
                AppMark(size: 18)
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(-1)
                Text("·").font(.system(size: 15, weight: .semibold)).opacity(0.6)
                TimerLabel(state: state, size: 15)
                    .fixedSize()
                Spacer(minLength: 6)
                if outOfDate && !headsUp && state.paused != true {
                    Text("Out of date").font(.system(size: 12, weight: .semibold)).opacity(0.7)
                } else if let endText {
                    Text(endText).font(.system(size: 13, weight: .semibold)).opacity(0.8).fixedSize()
                }
            }
            .foregroundStyle(nowColor)

            // 2 · The day as a track, a white knob at now
            JourneyTrack(state: state, knob: nowColor)
                .frame(height: 22)

            // 3 · Next ······ Pause · Done
            HStack(spacing: 10) {
                bottomLeft
                Spacer(minLength: 4)
                PauseButton(state: state)
                BlockActionButton(state: state)
            }
        }
    }
}

/// v24 B · last 5 minutes, as mocked: "Now  Deep work ——◉—— Standup  Next",
/// start time · "Ends in 4:59" · next start underneath.
struct NowNextStrip: View {
    let title: String
    let start: Date?
    let end: Date?
    let next: String
    let nextStart: Date
    let color: Color
    var icon: String? = nil
    var big: CGFloat = 24

    /// "7:30" like the mockup (no AM/PM, it fits under a narrow capsule).
    private func t(_ d: Date?) -> String { d.map { $0.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()) } ?? "" }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text("Now")
                Spacer()
                Text("Next")
            }
            .font(.system(size: 12, weight: .semibold))
            .opacity(0.6)
            HStack(spacing: 10) {
                Text(title).font(.system(size: big, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                ZStack {
                    Capsule().fill(Color.white.opacity(0.15)).frame(height: 5)
                    if let s = start, let e = end, e > s {
                        ProgressView(timerInterval: s...e, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .progressViewStyle(.linear).tint(color)
                    }
                    Circle().fill(color).frame(width: 22, height: 22)
                        .overlay(HDIcon(icon ?? "event", size: 12).foregroundStyle(.white))
                }
                .frame(minWidth: 44)
                Text(next).font(.system(size: big, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            }
            HStack {
                Text(t(start))
                Spacer()
                if let e = end, e > Date.now {
                    HStack(spacing: 3) {
                        Text("Ends in")
                        Text(timerInterval: Date.now...e, countsDown: true).monospacedDigit().fixedSize()
                    }
                    .foregroundStyle(color)
                }
                Spacer()
                Text(t(nextStart))
            }
            .font(.system(size: 14, weight: .bold))
        }
    }
}

/// v24 C · free time: Now (free, white knob) / Next / Later as colored capsules, times underneath.
/// Fixed proportions so every capsule shows; the countdown lives in the top row only.
struct PhasesStrip: View {
    let state: DayActivityAttributes.ContentState
    var inIsland = false

    private func t(_ d: Date?) -> String { d.map { $0.formatted(date: .omitted, time: .shortened) } ?? "" }

    var body: some View {
        let next = state.label.hasPrefix("Next · ")
            ? String(state.label.dropFirst(7).split(separator: " at ").first ?? "") : "Next"
        let nextCol = state.nextHex.map { Color(hex: $0) } ?? Color(white: 0.5)
        let fr = widths()
        VStack(spacing: 8) {
            // v31: plain HStack with fixed widths from a nominal card width. GeometryReader left the Island blank
            // (0 width on the first pass) and a custom Layout drew only the first capsule. Widths still follow real time.
            let total: CGFloat = inIsland ? 318 : 316
            let gap: CGFloat = 6
            let usable = total - gap * CGFloat(fr.count - 1)
            HStack(alignment: .top, spacing: gap) {
                phase("Now · Free", DayLiveStyle.doneGreen, nil, knob: true, left: state.nextStart).frame(width: usable * fr[0], alignment: .leading)
                phase(next, nextCol, t(state.nextStart)).frame(width: usable * fr[1], alignment: .leading)
                if fr.count > 2, let later = state.laterTitle {
                    phase(later, state.laterHex.map { Color(hex: $0) } ?? Color(white: 0.5), t(state.laterStart))
                        .frame(width: usable * fr[2], alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if state.action != nil {
                HStack { Spacer(); BlockActionButton(state: state) }
            }
        }
    }

    /// Capsule widths follow real time: free left vs the next block vs the later one,
    /// each at least 22% so its label fits. 5 free minutes before a 1-hour meeting → a short Free capsule.
    private func widths() -> [CGFloat] {
        let now = Date.now
        let free = max(60, (state.nextStart ?? now).timeIntervalSince(now))
        let next = max(60, (state.nextEnd ?? state.nextStart?.addingTimeInterval(1800) ?? now).timeIntervalSince(state.nextStart ?? now))
        var parts = [free, next]
        if state.laterTitle != nil {
            parts.append(max(60, (state.laterEnd ?? state.laterStart?.addingTimeInterval(1800) ?? now).timeIntervalSince(state.laterStart ?? now)))
        }
        let minShare = 0.22
        let total = parts.reduce(0, +)
        var shares = parts.map { max($0 / total, minShare) }
        let sum = shares.reduce(0, +)
        shares = shares.map { $0 / sum }
        return shares.map { CGFloat($0) }
    }

    /// v24 mockup: name above, capsule, time under ("57:04 left" for Now, start time for the others).
    private func phase(_ label: String, _ col: Color, _ time: String?, knob: Bool = false, left: Date? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).opacity(0.75).lineLimit(1)
            Capsule()
                .fill(LinearGradient(colors: [col, col.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 26)   // v34: thick like the mockup, in the Island too
                .overlay(alignment: .leading) {
                    if knob { Circle().fill(.white).frame(width: 20, height: 20).padding(.leading, 3) }
                }
            if let left, left > Date.now {
                HStack(spacing: 3) {
                    Text(timerInterval: Date.now...left, countsDown: true).monospacedDigit().fixedSize()   // keeps its seconds
                    Text("left").fixedSize()
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, weight: .bold)).lineLimit(1)
            } else {
                Text(time ?? "").font(.system(size: 12, weight: .bold)).lineLimit(1)
            }
        }
    }
}

/// v24: today's blocks as colored segments on one track, with a white knob at now.
/// The knob's spot is worked out each time iOS draws the card.
struct JourneyTrack: View {
    let state: DayActivityAttributes.ContentState
    var knob: Color = .white

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h: CGFloat = 8, y = (g.size.height - h) / 2
            let segs = state.track ?? []
            let p: Double = {
                guard let a = state.trackFrom, let b = state.trackTo, b > a else { return 0 }
                return min(max(Date.now.timeIntervalSince(a) / b.timeIntervalSince(a), 0), 1)
            }()
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(width: w, height: h).offset(y: y)
                ForEach(Array(segs.enumerated()), id: \.offset) { _, sg in
                    let x0 = w * CGFloat(sg.s), x1 = w * CGFloat(sg.e)
                    Capsule().fill(Color(hex: sg.hex).opacity(sg.e <= p ? 0.55 : 1))
                        .frame(width: max(4, x1 - x0 - 2), height: h)
                        .offset(x: x0, y: y)
                }
                Capsule().fill(Color.white)
                    .frame(width: 22, height: g.size.height)
                    .overlay(Capsule().fill(knob).frame(width: 8, height: 8))
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .offset(x: min(max(w * CGFloat(p) - 11, 0), w - 22))
            }
        }
    }
}

/// v23 #5: clock-like ticks around the card's edge, lit up to how far this block (or free gap) has run.
/// A Live Activity can't animate a custom shape on its own, so the lit count is worked out each time
/// iOS draws the card: on every update, tap and background refresh, and at the heads-up redraw.
struct EdgeTicks: View {
    let state: DayActivityAttributes.ContentState
    var headsUp = false
    var count = 72
    var radius: CGFloat = 22

    private var progress: Double? {
        let now = Date.now
        if state.closed == true || state.driving == true || state.source == .free { return nil }
        if state.overSince != nil { return 1 }
        if let end = state.currentEnd, let start = state.currentStart, end > start {
            if state.paused == true, let left = state.pausedLeft {
                return 1 - left / end.timeIntervalSince(start)
            }
            return now.timeIntervalSince(start) / end.timeIntervalSince(start)
        }
        return nil   // free time / nothing on: no ticks at all
    }

    /// Lit ticks are green while a task or meeting runs (yellow once it's over time, grey when paused).
    private var color: Color {
        if state.paused == true { return Color(white: 0.6) }
        if state.overSince != nil { return DayLiveStyle.stepYellow }
        return DayLiveStyle.doneGreen
    }

    var body: some View {
        if let p = progress {
            let lit = Int((min(max(p, 0), 1) * Double(count)).rounded())
            Canvas { ctx, size in
                for i in 0..<count {
                    let (pt, n) = Self.point(Double(i) / Double(count), in: size, r: radius, inset: 3)
                    var path = Path()
                    path.move(to: pt)
                    path.addLine(to: CGPoint(x: pt.x + n.dx * 5, y: pt.y + n.dy * 5))
                    ctx.stroke(path, with: .color(i < lit ? color : Color.white.opacity(0.13)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Point at fraction `t` of the way round a rounded rect (clockwise from top centre), plus the inward normal.
    static func point(_ t: Double, in size: CGSize, r: CGFloat, inset: CGFloat) -> (CGPoint, CGVector) {
        let w = size.width - inset * 2, h = size.height - inset * 2
        let rr = min(r - inset, min(w, h) / 2)
        let sw = w - 2 * rr, sh = h - 2 * rr, arc = CGFloat.pi / 2 * rr
        let total = 2 * sw + 2 * sh + 4 * arc
        var d = CGFloat(t) * total + sw / 2          // start at top centre
        d = d.truncatingRemainder(dividingBy: total)
        let x0 = inset, y0 = inset
        func corner(_ cx: CGFloat, _ cy: CGFloat, _ a0: CGFloat, _ s: CGFloat) -> (CGPoint, CGVector) {
            let a = a0 + s / rr
            return (CGPoint(x: cx + rr * cos(a), y: cy + rr * sin(a)), CGVector(dx: -cos(a), dy: -sin(a)))
        }
        if d < sw { return (CGPoint(x: x0 + rr + d, y: y0), CGVector(dx: 0, dy: 1)) }; d -= sw
        if d < arc { return corner(x0 + w - rr, y0 + rr, -.pi / 2, d) }; d -= arc
        if d < sh { return (CGPoint(x: x0 + w, y: y0 + rr + d), CGVector(dx: -1, dy: 0)) }; d -= sh
        if d < arc { return corner(x0 + w - rr, y0 + h - rr, 0, d) }; d -= arc
        if d < sw { return (CGPoint(x: x0 + w - rr - d, y: y0 + h), CGVector(dx: 0, dy: -1)) }; d -= sw
        if d < arc { return corner(x0 + rr, y0 + h - rr, .pi / 2, d) }; d -= arc
        if d < sh { return (CGPoint(x: x0, y: y0 + h - rr - d), CGVector(dx: 1, dy: 0)) }; d -= sh
        return corner(x0 + rr, y0 + rr, .pi, d)
    }
}

/// v23 #4: "Standup in 4:59 · Room 3B" on a band in the next block's color (last 5 minutes).
struct HeadsUpBand: View {
    let title: String
    let start: Date
    let place: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            if start > Date.now {
                Text("in")
                Text(timerInterval: Date.now...start, countsDown: true).monospacedDigit().fixedSize()
            } else {
                Text("now")
            }
            Spacer(minLength: 4)
            if let place { Text(place).lineLimit(1).opacity(0.85) }
        }
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Small Hyperday app icon (asset "HyperdayMark"), like the Tesla logo on Tesla's card.
struct AppMark: View {
    var size: CGFloat = 20

    var body: some View {
        Image("HyperdayMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityLabel("Hyperday")
    }
}

// MARK: - Pieces

struct SourceIcon: View {
    let source: BlockSource
    var size: CGFloat = 40
    var tint: Color? = nil   // category color; overrides the source color
    var iconName: String? = nil   // category icon; overrides the source icon

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint ?? background)
            .frame(width: size, height: size)
            .overlay(
                HDIcon(iconName ?? symbol, size: size * 0.56)
                    .foregroundStyle(.white)
            )
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch source {
        case .calendar: return "event"
        case .plan:     return "edit"
        case .free:     return "free"
        }
    }

    private var background: Color {
        switch source {
        case .calendar: return DayLiveStyle.calendarBlue
        case .plan:     return DayLiveStyle.planGreen
        case .free:     return .white.opacity(0.22)
        }
    }

    private var label: String {
        switch source {
        case .calendar: return "Calendar event"
        case .plan:     return "My plan"
        case .free:     return "Free time"
        }
    }
}

struct SegmentBar: View {
    let segments: [Double]
    var accent: Color = DayLiveStyle.accent
    var height: CGFloat = 5

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(.white.opacity(0.28))
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(accent)
                                .frame(width: geo.size.width * min(max(value, 0), 1))
                        }
                    }
                    .frame(height: height)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DayRing: View {
    let progress: Double
    var accent: Color = DayLiveStyle.accent

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.22), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1.5)
        .accessibilityLabel("Day \(Int(progress * 100)) percent complete")
    }
}

struct TimeLeft: View {
    let end: Date?
    var accent: Color = DayLiveStyle.accent

    var body: some View {
        if let end, end > Date.now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .monospacedDigit()
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
        }
    }
}

/// The big title. In free time it's a green "Free" pill.
struct CardTitle: View {
    let state: DayActivityAttributes.ContentState
    var size: CGFloat = 23

    var body: some View {
        if state.source == .free && state.nextStart != nil {
            Text(state.title)
                .font(.system(size: size * 0.8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, size * 0.55)
                .padding(.vertical, size * 0.14)
                .background(DayLiveStyle.doneGreen, in: Capsule())
        } else {
            Text(state.title)
                .font(.system(size: size, weight: .bold))
                .lineLimit(1)
        }
    }
}

/// "1:26:10 left" · "+4:12 over" · "1:40:05 until Standup". Ticks on its own on the Lock Screen.
struct TimerLabel: View {
    let state: DayActivityAttributes.ContentState
    var size: CGFloat = 14

    private func unit(_ s: String) -> some View {
        Text(s).font(.system(size: size * 0.6, weight: .bold)).kerning(0.6).opacity(0.85).lineLimit(1)
    }

    /// 1930 s -> "32:10", 4210 s -> "1:10:10"
    static func clock(_ t: Double) -> String {
        let s = Int(t.rounded()), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Live timer text stretches to fill its box, so size the box with an invisible sample
    /// ("8:88:88" or "88:88") in the same font, and lay the timer over it.
    private func timer(_ range: ClosedRange<Date>, down: Bool) -> some View {
        let long = abs(range.upperBound.timeIntervalSince(range.lowerBound)) >= 3600 || !down
        return Text(long ? "8:88:88" : "88:88")
            .hidden()
            .overlay(alignment: .leading) {
                Text(timerInterval: range, countsDown: down)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
    }

    var body: some View {
        Group {
            // v23: big number, small unit ("47:12 LEFT").
            if state.paused == true, let left = state.pausedLeft {
                // v20: frozen while paused.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Self.clock(left))
                    unit("PAUSED")
                }
            } else if let over = state.overSince {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("+")
                    timer(over...over.addingTimeInterval(24 * 3600), down: false)
                    unit(" OVER")
                }
            } else if let end = state.currentEnd, end > Date.now {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    timer(Date.now...end, down: true)
                    unit("LEFT")
                }
            } else if let next = state.nextStart, next > Date.now {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    timer(Date.now...next, down: true)
                    // Just "free": the next block's name is already on the line below. A long name here
                    // made the fixed-size top row wider than the card and pushed it off both edges.
                    unit("LEFT")   // title already says "Free"
                }
            }
        }
        .font(.system(size: size, weight: .semibold).monospacedDigit())   // v26: modest, not heavy
        .lineLimit(1)
    }
}

/// The bar under the title: steps or day segments while a block is on, one filling bar in free time,
/// a full yellow bar in overtime.
struct DayBar: View {
    let state: DayActivityAttributes.ContentState
    var height: CGFloat = 6

    var body: some View {
        if state.overSince != nil {
            Capsule().fill(DayLiveStyle.stepYellow).frame(height: height).frame(maxWidth: .infinity)
        } else if let from = state.freeStart, let to = state.nextStart, from < to {
            ProgressView(timerInterval: from...to, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(maxWidth: .infinity)
        } else {
            SegmentBar(segments: state.segments, accent: state.accentColor, height: height)
        }
    }
}

/// v20: one round icon button. Pause ⏸ while your own block runs, Play ▶ while paused.
/// Same button both ways, so iOS morphs the symbol (pause → play) instead of swapping views.
struct PauseButton: View {
    let state: DayActivityAttributes.ContentState

    var body: some View {
        if state.canPause == true, let id = state.actionBlockID {
            let paused = state.paused == true
            Button(intent: PauseBlockIntent(blockID: id, pause: !paused)) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(paused ? .black : .white)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .frame(width: 34, height: 34)
                    // Paused: yellow so Resume stands out; running: quiet grey.
                    .background(paused ? DayLiveStyle.stepYellow : Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(paused ? "Resume" : "Pause")
        }
    }
}

struct BlockActionButton: View {
    let state: DayActivityAttributes.ContentState

    var body: some View {
        if let id = state.actionBlockID, let action = state.action {
            Button(intent: BlockActionIntent(blockID: id, action: action)) {
                // Done is always green, Step is yellow, "Start now" in free time stays grey.
                let fill: Color = action == .done ? DayLiveStyle.doneGreen
                    : action == .checkStep ? DayLiveStyle.stepYellow : Color.white.opacity(0.22)
                let ink: Color = action == .checkStep ? .black : .white
                HStack(spacing: 5) {
                    HDIcon(buttonSymbol(action), size: 15)
                        .foregroundStyle(action == .checkStep ? Color(white: 0.3) : Color.white)
                    Text(buttonTitle(action))
                        .foregroundStyle(ink)
                }
                    .font(.system(size: 14, weight: action == .startNext ? .semibold : .bold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    private func buttonTitle(_ action: BlockAction) -> String {
        switch action {
        case .done:      return "Done"
        case .startNext: return "Start now"
        case .checkStep: return "Step \((state.stepsDone ?? 0) + 1)/\(state.stepsTotal ?? 0)"
        }
    }

    private func buttonSymbol(_ action: BlockAction) -> String {
        switch action {
        case .done:      return "done"
        case .startNext: return "start"
        case .checkStep: return "step-done"
        }
    }
}

/// Apple Watch Smart Stack (and CarPlay) version of the card: [mark] 26:10 · Next 10:30, title, bar + button.
struct WatchCard: View {
    let state: DayActivityAttributes.ContentState
    var isStale: Bool = false

    private var nextTime: String? {
        let outOfDate = isStale && (state.boundaryAt.map { Date.now >= $0 } ?? true)
        guard !outOfDate, state.paused != true, let r = state.label.range(of: " at ") else { return nil }
        return "Next " + state.label[r.upperBound...]
    }

    /// Grey bar while paused (same as the iPhone card).
    private var watchBar: DayActivityAttributes.ContentState {
        var s = state
        if state.paused == true { s.accentHex = "#8E8E93" }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                AppMark(size: 14)
                TimerLabel(state: state, size: 13)
                    .foregroundStyle(state.paused == true ? Color(white: 0.75) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if let nextTime {
                    Text(nextTime)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Text(state.title)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            HStack(spacing: 6) {
                JourneyTrack(state: state, knob: state.paused == true ? Color(white: 0.6) : state.accentColor)   // v24 journey
                    .frame(height: 14)
                PauseButton(state: state)
                    .scaleEffect(0.85)
                BlockActionButton(state: state)
                    .scaleEffect(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// Picks the iPhone Lock Screen card or the compact Watch card.
struct ActivityFamilyCard: View {
    @Environment(\.activityFamily) private var family
    let state: DayActivityAttributes.ContentState
    var isStale: Bool = false

    var body: some View {
        let live = self.state.selfSwitched(isStale: self.isStale)
        let state = live.state, isStale = live.isStale
        if state.closed == true {
            DayClosedCard(state: state, compact: family == .small)
        } else if state.driving == true && family != .small {
            DriveCard(state: state)
        } else {
            switch family {
            case .small: WatchCard(state: state, isStale: isStale)
            default: LockScreenCard(state: state, isStale: isStale)
            }
        }
    }
}

// MARK: - Day Close (v9)

/// After your close time: done today, a Review link, and tomorrow's pre-flight.
struct DayClosedCard: View {
    let state: DayActivityAttributes.ContentState
    var compact = false   // Dynamic Island / Watch

    private var done: Int { state.doneCount ?? 0 }
    private var total: Int { max(state.totalCount ?? 0, done) }

    private func time(_ d: Date?) -> String {
        d.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"
    }

    private func reviewLink(_ n: Int, _ url: URL) -> some View {
        Link(destination: url) {
            Text("Review \(n)")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.white.opacity(0.2), in: Capsule())
        }
    }

    /// "3h" over "10m focus": big digits, small "focus" (v24 D).
    private var focusText: some View {
        let m = state.focusMinutes ?? 0
        let big = compact ? 22.0 : 32.0
        func n(_ s: String) -> Text { Text(s).font(.system(size: big, weight: .heavy)) }
        func u(_ s: String) -> Text { Text(s).font(.system(size: big * 0.45, weight: .heavy)) }
        return Group {
            if compact {
                m >= 60 ? n("\(m / 60)h \(m % 60)m") + u(" active") : n("\(m)m") + u(" active")
            } else if m >= 60 {
                n("\(m / 60)h \(m % 60)m") + u(" active")       // v34: one line, like the mockup
            } else {
                n("\(m)m") + u(" active")
            }
        }
        .foregroundStyle(DayLiveStyle.doneGreen)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// "Next: Standup 3:00 PM" (tomorrow's first block).
    private var nextLine: String? {
        guard let first = state.tomorrowFirst else { return nil }
        return "Next: " + (state.tomorrowTitle.map { "\($0) " } ?? "") + time(first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            HStack(alignment: .bottom, spacing: 10) {
                focusText
                Spacer(minLength: 4)
                if let hours = state.focusByHour, hours.contains(where: { $0 > 0 }) {
                    HStack(alignment: .bottom, spacing: compact ? 3 : 4) {
                        ForEach(hours.indices, id: \.self) { i in
                            Capsule()
                                .fill(hours[i] >= 15 ? DayLiveStyle.doneGreen : Color.white.opacity(0.22))
                                .frame(width: compact ? 4 : 7,
                                       height: max(compact ? 4 : 7, CGFloat(min(hours[i], 60) / 60) * (compact ? 24 : 40)))
                        }
                    }
                }
            }
            HStack {
                Text("\(done)/\(total) done")
                Spacer(minLength: 6)
                if let nextLine { Text(nextLine).lineLimit(1) }
            }
            .font(.system(size: 13, weight: .semibold))
            .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 16)
        .padding(.vertical, compact ? 4 : 14)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: compact ? 14 : 16, weight: .heavy).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Drive card (#9)

struct DriveCard: View {
    let state: DayActivityAttributes.ContentState

    var body: some View {
        let spare = state.spareMinutes
        let late = (spare ?? 0) < 0
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                AppMark(size: 20)
                if let a = state.arriveAt {
                    Text("Arrive \(a.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 16, weight: .heavy))
                } else {
                    Text("Driving").font(.system(size: 16, weight: .heavy))
                }
                Spacer(minLength: 4)
                if let since = state.driveSince {
                    HStack(spacing: 3) {
                        Text("Driving ·")
                        Text(timerInterval: since...since.addingTimeInterval(6 * 3600), countsDown: false)
                            .monospacedDigit()
                            .frame(width: 56, alignment: .leading)   // fits 1:02:03
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.system(size: 21, weight: .bold)).lineLimit(1)
                    if let spare {
                        Text(late ? "\(-spare) min late" : "\(spare) min to spare")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(late ? Color(red: 1, green: 0.27, blue: 0.23) : DayLiveStyle.doneGreen)
                    }
                }
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DayLiveStyle.calendarBlue)
                    .frame(width: 44, height: 44)
                    .overlay(HDIcon("car", size: 34).foregroundStyle(.white))   // v30: your own car's outline
            }
            if let since = state.driveSince, let a = state.arriveAt, a > since {
                ProgressView(timerInterval: since...a, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(DayLiveStyle.calendarBlue)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}


// MARK: - v16 compact Dynamic Island: block ring around the icon + live timer

/// Which timer the compact Island shows.
enum IslandPhase {
    case running(ClosedRange<Date>)   // counts down to the block's end
    case over(Date)                   // counts up from the planned end (yellow)
    case free(ClosedRange<Date>)      // counts down to the next block
    case upNext(Date)                 // nothing running, next block later: "in 8:05"
    case paused(Double)               // v20: frozen, seconds left
    case idle

    init(_ s: DayActivityAttributes.ContentState, now: Date = .now) {
        if s.paused == true, let left = s.pausedLeft {
            self = .paused(left)
        } else if let over = s.overSince {
            self = .over(over)
        } else if let end = s.currentEnd, end > now {
            self = .running((s.currentStart.map { min($0, now) } ?? now)...end)
        } else if let next = s.nextStart, next > now {
            if let free = s.freeStart, free < next { self = .free(min(free, now)...next) }
            else { self = .upNext(next) }
        } else {
            self = .idle
        }
    }
}

/// Left side: the block's icon inside a ring that fills as this block runs.
struct IslandRingIcon: View {
    let state: DayActivityAttributes.ContentState
    var size: CGFloat = 24

    private static let overYellow = Color(red: 1, green: 0.84, blue: 0.04)

    /// v23: the block's icon in a soft capsule of its color (the timer beside it uses the same color).
    /// Free time = a solid green F (kept from v22). Minimal view = this capsule alone.
    var body: some View {
        let phase = IslandPhase(state)
        let col = color(phase)
        Group {
            switch phase {
            case .free:
                Circle().fill(DayLiveStyle.doneGreen)
                    .overlay(Text("F").font(.system(size: size * 0.5, weight: .black)).foregroundStyle(.white))
                    .frame(width: size, height: size)
            default:
                Capsule().fill(col.opacity(0.24))
                    .overlay(HDIcon(state.iconName ?? "event", size: size * 0.55).foregroundStyle(col))
                    .frame(width: size * 1.36, height: size)   // v26: concentric with the Island end
            }
        }
    }

    private func color(_ phase: IslandPhase) -> Color {
        switch phase {
        case .over: return Self.overYellow
        case .free: return DayLiveStyle.doneGreen
        case .upNext, .idle, .paused: return Color(white: 0.7)
        default: return state.accentColor
        }
    }
}

/// Right side: the live timer, sized with a hidden sample so it never jumps or truncates.
struct IslandTimer: View {
    let state: DayActivityAttributes.ContentState

    var body: some View {
        let phase = IslandPhase(state)
        Group {
            switch phase {
            case .running(let r):
                sized(r, down: true).foregroundStyle(state.accentColor)
            case .free(let r):
                if let c = Self.coarse(until: r.upperBound) {
                    Self.bigSmall(c).foregroundStyle(DayLiveStyle.doneGreen)
                } else {
                    sized(Date.now...max(Date.now, r.upperBound), down: true).foregroundStyle(DayLiveStyle.doneGreen)
                }
            case .over(let since):
                HStack(spacing: 0) {
                    Text("+")
                    sized(since...since.addingTimeInterval(24 * 3600), down: false)
                }
                .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04))
            case .upNext(let next):
                HStack(spacing: 3) {
                    Text("in")
                    if let c = Self.coarse(until: next) { Self.bigSmall(c) } else { sized(Date.now...max(Date.now, next), down: true) }
                }
                .foregroundStyle(.white.opacity(0.85))
            case .paused(let left):
                Text(TimerLabel.clock(left)).foregroundStyle(Color(white: 0.7))
            case .idle:
                DayRing(progress: state.dayProgress, accent: state.accentColor).frame(width: 20, height: 20)
            }
        }
        .font(.system(size: 14, weight: .semibold).monospacedDigit())   // v26: small and tight to the camera
    }

    /// "1d 4h" → big digits, small letters (v23 #3).
    static func bigSmall(_ s: String) -> Text {
        s.reduce(Text("")) { acc, ch in
            acc + Text(String(ch)).font(.system(size: ch.isNumber ? 14 : 9, weight: .semibold))
        }
    }

    /// v21: an hour or more away → "2h" … "23h", then "1d" / "1d 4h". Hours round UP, so it never
    /// claims less time than there is. Under an hour → nil (use the live mm:ss timer).
    static func coarse(until date: Date, now: Date = .now) -> String? {
        let secs = date.timeIntervalSince(now)
        guard secs >= 3600 else { return nil }
        // Rounded DOWN with "+": stays true even if iOS doesn't redraw for a while ("2h+" at 2h59 … 2h00).
        let hours = Int(secs / 3600)
        if hours < 24 { return "\(hours)h+" }
        let d = hours / 24, h = hours % 24
        return h == 0 ? "\(d)d+" : "\(d)d \(h)h+"
    }

    /// Minutes:seconds only (1:18:20 shows as 78:20), so the Island stays as narrow as Apple's own timers.
    /// The box is sized with a hidden "88:88" (or "888:88" past 100 minutes) so it never jumps.
    private func sized(_ range: ClosedRange<Date>, down: Bool) -> some View {
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        let sample = down && span >= 6000 ? "888:88" : "88:88"   // overtime is capped at 1h, so "88:88" fits
        return Text(sample).hidden()
            .overlay(alignment: .trailing) {
                Text(timerInterval: range, pauseTime: nil, countsDown: down, showsHours: false)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
    }
}
