import AppIntents
import SwiftUI
import WidgetKit

/// Shared by the widget extension (real Live Activity) and the app (preview card).
enum DayLiveStyle {
    // v57: JobTrail palette (green = running, amber = waiting, blue = done, red = failed).
    static let accent = HDTone.green
    static let cardTint = HDTone.surface
    static let glassOpacity = 0.9
    static let calendarBlue = HDTone.blue
    static let planGreen = HDTone.green
    static let stepYellow = HDTone.amber
    static let doneGreen = HDTone.green
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
        if state.paused == true { s.accentHex = "#686868" } else if headsUp { s.accentHex = "#E9A23B" }
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
            .font(.mono(12, .medium))   // v58: JobTrail pill
            .foregroundStyle(HDTone.soft)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(HDTone.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(HDTone.lineDark, lineWidth: 1))
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
                .font(.geist(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        } else if let n = nextParts {
            pill("Next: \(n.title) · \(n.time)")
        } else if let also = state.also {
            Text(also)
                .font(.geist(size: 13))
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
            Text(also).font(.geist(size: 13)).opacity(0.8).lineLimit(1)
        } else if let n = nextParts {
            HStack(spacing: 8) {
                let col = state.nextHex.map { Color(hex: $0) } ?? Color(white: 0.5)
                HDIcon(state.nextIcon ?? "event", size: 20).foregroundStyle(col)   // v47: solid icon, no circle
                VStack(alignment: .leading, spacing: 0) {
                    Text("Next: \(n.title)").font(.geist(size: 14, weight: .bold)).lineLimit(1)
                    Text(score.map { "\(n.time) · \($0)" } ?? n.time)
                        .contentTransition(.numericText())
                        .font(.geist(size: 11.5, weight: .medium)).opacity(0.65).lineLimit(1)
                }
            }
        } else if let score {
            Text(score).contentTransition(.numericText()).font(.geist(size: 13, weight: .semibold)).opacity(0.75)
        }
    }

    /// v28: each state is its own layout, exactly as mocked in v24.
    ///   B · last 5 minutes → Now → Next flight card.  C · free time → Now / Next / Later capsules.  A · otherwise.
    /// v61: your Macs from JobTrail are on the card.
    private var macs: [MacLive] { state.macs ?? [] }
    private var hasMacs: Bool { !macs.isEmpty }

    var body: some View {
        if !inIsland && isEmptyDay && hasMacs {
            JobTrailBoard(state: state, headline: state.title)   // v65: day done → the card becomes JobTrail
        } else if inIsland || isEmptyDay {
            legacyBody
        } else {
            jtCard   // v62: one JobTrail layout for every Lock Screen state
        }
    }

    /// The Dynamic Island (expanded) and the empty-day card keep their compact layouts.
    private var legacyBody: some View {
        VStack(alignment: .leading, spacing: inIsland ? 5 : 7) {
        Group {
            if headsUp, let next = state.headsNextTitle, let nextStart = state.headsNextStart {
                NowNextStrip(title: state.title, start: state.currentStart, end: state.currentEnd,
                             next: next, nextStart: nextStart, color: state.accentColor, icon: state.iconName,
                             big: inIsland ? 19 : 24)
            } else if state.source == .free, state.nextStart != nil {
                PhasesStrip(state: state, inIsland: inIsland)
            } else if isEmptyDay {
                emptyDay   // v52: nothing planned / nothing left: a check mark, not an empty timeline
            } else {
                journey
            }
        }
        if hasMacs && !inIsland {
            Rectangle().fill(HDTone.hover).frame(height: 1)
            MacRow(macs: macs)
        } else if hasMacs { MacStrip(macs: macs, compact: true) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, inIsland ? 4 : 14)
        .padding(.vertical, inIsland ? 2 : 12)
    }

    // MARK: v62 JobTrail Lock Screen card
    //  ● NOW · ENDS 11:02 AM                     3/7 DONE
    //  [icon] Deep work — ORBIT AI
    //  39:34 LEFT                           [⏸] [✓ Done]
    //  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ (moves by itself)
    //  NEXT  Standup · 11:05 AM
    //  ───────────────────────────────────────────────────
    //  ⌨ ● 3  S01_run2.sh   7:54:40 │ ▭ ● ~/ai/ltx-2    13:16

    private var jtStatus: HDStatus {
        if state.paused == true { return .idle }
        if state.overSince != nil { return .failed }
        if headsUp || state.source == .free { return .waiting }
        return state.currentEnd != nil ? .running : .waiting
    }

    private var jtHeader: String {
        if outOfDate && !headsUp && state.paused != true { return "Out of date · tap to refresh" }
        if state.paused == true { return "Paused" }
        if state.overSince != nil { return "Over time" }
        if state.source == .free, let n = state.nextStart { return "Free · until \(n.formatted(date: .omitted, time: .shortened))" }
        if headsUp { return "Wrapping up · ends \(endText ?? "")" }
        if let e = endText, state.currentEnd != nil { return "Now · ends \(e)" }
        return "Now"
    }

    private var jtTitle: String {
        state.source == .free ? (state.nextTitle.map { "Free until \($0)" } ?? state.title) : state.title
    }

    /// One line under the bar: the next step, the heads-up, or what's next.
    private var jtNext: (key: String, value: String, color: Color)? {
        if state.alsoIsStep == true, let step = state.also {
            let n = (state.stepsDone ?? 0) + 1, t = state.stepsTotal ?? 0
            return ("Step \(n)/\(t)", step, HDTone.amber)
        }
        if headsUp, let title = state.headsNextTitle, let start = state.headsNextStart {
            let place = state.headsNextPlace.map { " · \($0)" } ?? ""
            return ("Next", "\(title) · \(start.formatted(date: .omitted, time: .shortened))\(place)", HDTone.amber)
        }
        if state.source == .free, let later = state.laterTitle, let ls = state.laterStart {
            return ("Then", "\(later) · \(ls.formatted(date: .omitted, time: .shortened))", HDTone.soft)
        }
        if let n = nextParts { return ("Next", "\(n.title) · \(n.time)", HDTone.soft) }
        return nil
    }

    private var jtCard: some View {
        let st = jtStatus
        return VStack(alignment: .leading, spacing: hasMacs ? 5 : 6) {
            // header: status · when ······ score
            HStack(spacing: 6) {
                JTStatusDot(status: st, size: 6, animated: false)
                Text(jtHeader.uppercased())
                    .font(.mono(10, .semibold)).kerning(0.8)
                    .foregroundStyle(st == .idle ? HDTone.dim : st.color)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let d = state.doneCount, let t = state.totalCount, t > 0 {
                    Text("\(d)/\(t) DONE").font(.mono(10, .medium)).kerning(0.6).foregroundStyle(HDTone.faintDark)
                        .contentTransition(.numericText())
                }
            }
            // title
            HStack(spacing: 7) {
                HDIcon(state.source == .free ? (state.nextIcon ?? "event") : (state.iconName ?? "event"), size: 16)
                    .foregroundStyle(state.source == .free ? (state.nextHex.map { Color(hex: $0) } ?? HDTone.dim) : state.accentColor)
                Text(jtTitle)
                    .font(.geist(size: 16, weight: .semibold))
                    .foregroundStyle(HDTone.textHi)
                    .lineLimit(1)
            }
            // the clock + actions
            HStack(alignment: .center, spacing: 8) {
                jtClock(st)
                Spacer(minLength: 4)
                PauseButton(state: state, compact: hasMacs)
                BlockActionButton(state: state, compact: hasMacs)
            }
            jtBar(st)
            if let n = jtNext {
                HStack(spacing: 8) {
                    Text(n.key.uppercased()).font(.mono(9.5, .semibold)).kerning(0.8).foregroundStyle(HDTone.faintDark)
                    Text(n.value).font(.geist(size: 12.5, weight: .medium)).foregroundStyle(n.color).lineLimit(1)
                }
            }
            if hasMacs {
                Rectangle().fill(HDTone.hover).frame(height: 1)
                MacRow(macs: macs)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, hasMacs ? 7 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // v66: border on the card's real bounds
        .background {
            ContainerRelativeShape()
                .strokeBorder(st == .running || st == .failed ? st.color.opacity(0.45)
                              : (st == .waiting ? HDTone.amber.opacity(0.4) : HDTone.lineDark), lineWidth: 1)
        }
    }

    /// Big Geist Mono clock: counts down to the end (or the next start in free time), up when over, frozen when paused.
    @ViewBuilder
    private func jtClock(_ st: HDStatus) -> some View {
        let font = Font.mono(jtClockSize, .semibold)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                if state.paused == true {
                    Text(TimerLabel.clock(state.pausedLeft ?? 0))
                } else if let over = state.overSince {
                    Text("+") + Text(timerInterval: over...over.addingTimeInterval(24 * 3600), countsDown: false)
                } else if let end = state.currentEnd, end > Date.now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                } else if let next = state.nextStart, next > Date.now {
                    Text(timerInterval: Date.now...next, countsDown: true)
                } else {
                    Text("--:--")
                }
            }
            .font(font)
            .monospacedDigit()
            .foregroundStyle(st == .failed ? HDTone.danger : (st == .idle ? HDTone.dim : HDTone.textHi))
            .lineLimit(1)
            // Timer text stretches to fill its box: size the box with an invisible sample in the same font.
            .frame(width: jtClockWidth, alignment: .leading)
            Text(state.paused == true ? "PAUSED" : (state.overSince != nil ? "OVER" : "LEFT"))
                .font(.mono(10, .semibold)).kerning(0.8)
                .foregroundStyle(HDTone.faintDark)
        }
    }

    /// Width of "88:88" / "8:88:88" (+ sign when over) in Geist Mono 32 (0.6 em per glyph).
    private var jtClockWidth: CGFloat {
        let target = state.currentEnd ?? state.nextStart
        let long = state.overSince != nil || (target.map { $0.timeIntervalSinceNow >= 3600 } ?? false)
            || (state.pausedLeft ?? 0) >= 3600
        let chars: CGFloat = (long ? 7 : 5) + (state.overSince != nil ? 1 : 0)
        return chars * jtClockSize * 0.6 + 2
    }

    /// v63: a little smaller when the Macs (with their usage line) are on the card.
    private var jtClockSize: CGFloat { hasMacs ? 27 : 32 }

    /// 4 pt bar that moves by itself (timer-driven) in the status colour.
    @ViewBuilder
    private func jtBar(_ st: HDStatus) -> some View {
        Group {
            if state.overSince != nil || state.paused == true {
                Capsule().fill(st == .failed ? HDTone.danger : HDTone.dim).frame(height: 4)
            } else if let a = state.currentStart, let b = state.currentEnd, b > a, state.source != .free {
                ProgressView(timerInterval: a...b, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear).tint(st.color)
            } else if let a = state.freeStart, let b = state.nextStart, b > a {
                ProgressView(timerInterval: a...b, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear).tint(HDTone.amber)
            } else {
                Capsule().fill(HDTone.hover).frame(height: 4)
            }
        }
        .frame(height: 4)
    }

    /// Nothing running and nothing coming up (free, no next block, no timer).
    private var isEmptyDay: Bool {
        state.source == .free && state.nextStart == nil && state.currentEnd == nil && state.overSince == nil
    }

    private var emptyDay: some View {
        HStack(spacing: inIsland ? 10 : 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.geist(size: inIsland ? 30 : 38, weight: .semibold))
                .foregroundStyle(DayLiveStyle.doneGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.geist(size: inIsland ? 16 : 19, weight: .bold))
                    .lineLimit(1)
                Text(state.label)
                    .font(.geist(size: inIsland ? 12.5 : 14, weight: .medium))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, inIsland ? 4 : 6)
    }

    /// v33 A · a block is running: title · ends, big countdown + Pause/Done, a tick strip of this
    /// block (dimmed = gone, white marker = now), then Next. As tall as other apps' cards.
    private var blockDone: CGFloat {
        if state.overSince != nil { return 1 }
        guard let a = state.currentStart, let b = state.currentEnd, b > a else { return 0 }
        return CGFloat(min(1, max(0, Date.now.timeIntervalSince(a) / b.timeIntervalSince(a))))
    }

    /// v37: the long-press Island is short (iOS caps it), so it gets its own compact layout:
    /// title · timer · ends on one line, the strip, then Next + Pause + Done. Nothing cut off at the bottom.
    private var islandJourney: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HDIcon(state.iconName ?? "event", size: 17)
                Text(state.title).font(.geist(size: 14, weight: .semibold)).lineLimit(1).layoutPriority(-1)
                Text("·").font(.geist(size: 14, weight: .semibold)).opacity(0.6)
                TimerLabel(state: state, size: 15).layoutPriority(1)   // not .fixedSize(): that blanks the Island
                Spacer(minLength: 4)
                if let endText, state.currentEnd != nil {
                    Text(endText).font(.geist(size: 12, weight: .semibold)).opacity(0.75).lineLimit(1)
                }
            }
            .foregroundStyle(nowColor)
            ZStack(alignment: .topLeading) {
                TickStrip(tickHeight: 14).fill(nowColor.opacity(0.28))
                TickStrip(from: blockDone, tickHeight: 14).fill(nowColor)
                NowMarker(at: blockDone, top: 15).fill(.white)
            }
            .frame(height: 22)
            HStack(spacing: 10) {
                bottomLeft
                Spacer(minLength: 4)
                PauseButton(state: state)
                BlockActionButton(state: state)
            }
        }
    }

    @ViewBuilder
    private var journey: some View {
        if inIsland { islandJourney } else { lockJourney }
    }

    private var lockJourney: some View {
        let h: CGFloat = 26
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                HDIcon(state.iconName ?? "event", size: inIsland ? 17 : 20)
                Text(state.title)
                    .font(.geist(size: inIsland ? 14 : 15, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(-1)
                Spacer(minLength: 6)
                if outOfDate && !headsUp && state.paused != true {
                    Text("Out of date").font(.geist(size: 12, weight: .semibold)).opacity(0.7)
                } else if let endText {
                    Text((state.currentEnd != nil ? "ends \(endText)" : endText).uppercased())
                        .font(.mono(11, .medium)).kerning(1.5).opacity(0.8).lineLimit(1)   // v55
                }
            }
            .foregroundStyle(nowColor)

            HStack(alignment: .center, spacing: 10) {
                TimerLabel(state: state, size: hasMacs ? 28 : (inIsland ? 26 : 32))
                // v61: JobTrail pulse graph beside the timer
                JTPulseLine(status: state.overSince != nil ? .failed : (state.paused == true ? .idle : .running),
                            animated: false, boxed: false)
                    .frame(width: 44, height: 20)
                Spacer(minLength: 4)
                PauseButton(state: state)
                BlockActionButton(state: state)
            }

            if hasMacs {
                // v61: with the Macs below, the tick strip becomes a slim live bar (it moves by itself).
                if let a = state.currentStart, let b = state.currentEnd, b > a {
                    ProgressView(timerInterval: a...b, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.linear).tint(nowColor)
                } else {
                    Capsule().fill(nowColor).frame(height: 3)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    TickStrip(tickHeight: h).fill(nowColor.opacity(0.28))
                    TickStrip(from: blockDone, tickHeight: h).fill(nowColor)
                    NowMarker(at: blockDone, top: h + 2).fill(.white)
                }
                .frame(height: h + 10)
            }

            bottomLeft
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
                Text("NOW")
                Spacer()
                Text("NEXT")
            }
            .font(.mono(10, .semibold)).kerning(0.8)   // v58: JobTrail caps
            .foregroundStyle(HDTone.dim)
            HStack(spacing: 10) {
                Text(title).font(.geist(size: big, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                ZStack {
                    Capsule().fill(HDTone.hover).frame(height: 5)
                    if let s = start, let e = end, e > s {
                        ProgressView(timerInterval: s...e, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .progressViewStyle(.linear).tint(color)
                    }
                    HDIcon(icon ?? "event", size: 18).foregroundStyle(color)   // v47: solid icon, no circle
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
                .frame(minWidth: 44)
                Text(next).font(.geist(size: big, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            }
            HStack {
                Text(t(start))
                Spacer()
                if let e = end, e > Date.now {
                    HStack(spacing: 3) {
                        Text("Ends in")
                        Text(timerInterval: Date.now...e, countsDown: true).monospacedDigit().layoutPriority(1)
                    }
                    .foregroundStyle(color)
                }
                Spacer()
                Text(t(nextStart))
            }
            .font(.geist(size: 14, weight: .bold))
        }
    }
}

/// v24 C · free time: Now (free, white knob) / Next / Later as colored capsules, times underneath.
/// Fixed proportions so every capsule shows; the countdown lives in the top row only.
/// v32: Apple-timer-style ticks, drawn as one path. Every 5th tick is full height.
/// `from`/`to` pick the part of the strip to draw (0…1), so a dim copy + a bright copy show time gone vs left.
struct TickStrip: Shape {
    var from: CGFloat = 0
    var to: CGFloat = 1
    var tickHeight: CGFloat = 26
    func path(in r: CGRect) -> Path {
        var p = Path()
        let step: CGFloat = 7        // v33: 4 pt ticks, 3 pt gap
        guard r.width > step else { return p }
        let n = Int(r.width / step)
        for i in 0..<n {
            let x = CGFloat(i) * step
            let f = x / r.width
            guard f >= from && f < to else { continue }
            let tall = i % 5 == 0 ? tickHeight : tickHeight * 0.78
            p.addRoundedRect(in: CGRect(x: r.minX + x, y: r.minY + tickHeight - tall, width: 4, height: tall),
                             cornerSize: CGSize(width: 2, height: 2))
        }
        return p
    }
}

/// v32: small triangle under the tick strip at `at` (0…1) = now.
struct NowMarker: Shape {
    var at: CGFloat
    var top: CGFloat = 28
    func path(in r: CGRect) -> Path {
        let x = r.minX + r.width * min(1, max(0, at))
        var p = Path()
        p.move(to: CGPoint(x: x, y: r.minY + top))
        p.addLine(to: CGPoint(x: x + 5, y: r.minY + top + 7))
        p.addLine(to: CGPoint(x: x - 5, y: r.minY + top + 7))
        p.closeSubpath()
        return p
    }
}

struct PhasesStrip: View {
    let state: DayActivityAttributes.ContentState
    var inIsland = false

    private func t(_ d: Date?) -> String { d.map { $0.formatted(date: .omitted, time: .shortened) } ?? "" }

    /// v33: as tall as other apps' cards. Big countdown, one full-width strip (Free → Next → Later,
    /// sized by real time), Next underneath. Shapes fill the width on any phone: no measuring.
    var body: some View {
        let next = state.label.hasPrefix("Next · ")
            ? String(state.label.dropFirst(7).split(separator: " at ").first ?? "") : "Next"
        let nextCol = state.nextHex.map { Color(hex: $0) } ?? Color(white: 0.5)
        let laterCol = state.laterHex.map { Color(hex: $0) } ?? Color(white: 0.5)
        let fr = widths()
        let gap: CGFloat = 0.022
        let e0 = fr[0], e1 = fr.count > 2 ? fr[0] + fr[1] : 1
        let segs: [(CGFloat, CGFloat, Color)] = fr.count > 2
            ? [(0, e0 - gap / 2, DayLiveStyle.doneGreen), (e0 + gap / 2, e1 - gap / 2, nextCol), (e1 + gap / 2, 1, laterCol)]
            : [(0, e0 - gap / 2, DayLiveStyle.doneGreen), (e0 + gap / 2, 1, nextCol)]
        let now = freeDone() * (e0 - gap / 2)
        let h: CGFloat = inIsland ? 14 : 26
        let strip = ZStack(alignment: .topLeading) {
            ForEach(0..<segs.count, id: \.self) { i in
                TickStrip(from: segs[i].0, to: segs[i].1, tickHeight: h).fill(segs[i].2.opacity(0.28))
                TickStrip(from: max(segs[i].0, now), to: segs[i].1, tickHeight: h).fill(segs[i].2)
            }
            NowMarker(at: now, top: h + 1).fill(.white)
        }
        .frame(height: h + (inIsland ? 8 : 10))
        if inIsland {
            // v37: compact Island version: Free · timer · until, the strip, then Next + button.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    HDIcon("free", size: 17).foregroundStyle(DayLiveStyle.doneGreen)
                    Text("Free").font(.geist(size: 14, weight: .semibold)).foregroundStyle(DayLiveStyle.doneGreen)
                    Text("·").font(.geist(size: 14, weight: .semibold)).opacity(0.6)
                    TimerLabel(state: state, size: 15).layoutPriority(1)
                    Spacer(minLength: 4)
                    Text("until \(t(state.nextStart))").font(.geist(size: 12, weight: .semibold)).opacity(0.7).lineLimit(1)
                }
                strip
                HStack(spacing: 8) {
                    Circle().fill(nextCol).frame(width: 9, height: 9)
                    Text("Next: \(next)").font(.geist(size: 13, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 6)
                    BlockActionButton(state: state)
                }
            }
        } else {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                HDIcon("free", size: inIsland ? 17 : 20).foregroundStyle(DayLiveStyle.doneGreen)
                Text("Free time").font(.geist(size: inIsland ? 14 : 15, weight: .semibold))
                    .foregroundStyle(DayLiveStyle.doneGreen).lineLimit(1)
                Spacer(minLength: 6)
                Text("until \(t(state.nextStart))").font(.geist(size: 13, weight: .semibold)).opacity(0.7).lineLimit(1)
            }
            HStack(alignment: .center, spacing: 8) {
                TimerLabel(state: state, size: inIsland ? 26 : 32)
                Spacer(minLength: 4)
                BlockActionButton(state: state)
            }
            strip
            HStack(spacing: 8) {
                Circle().fill(nextCol).frame(width: 9, height: 9)
                Text("Next: \(next)").font(.geist(size: 13.5, weight: .bold)).lineLimit(1)
                Spacer(minLength: 6)
                if fr.count > 2, let later = state.laterTitle, !inIsland {
                    Text("then \(later)").font(.geist(size: 12.5, weight: .semibold)).opacity(0.6).lineLimit(1)
                        .layoutPriority(-1)
                }
            }
        }
        }
    }

    /// How much of the free gap is gone (0…1). Moves each time the card refreshes.
    private func freeDone() -> CGFloat {
        guard let from = state.freeStart, let to = state.nextStart, to > from else { return 0 }
        return CGFloat(min(1, max(0, Date.now.timeIntervalSince(from) / to.timeIntervalSince(from))))
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
                Text(timerInterval: Date.now...start, countsDown: true).monospacedDigit().layoutPriority(1)
            } else {
                Text("now")
            }
            Spacer(minLength: 4)
            if let place { Text(place).lineLimit(1).opacity(0.85) }
        }
        .font(.geist(size: 13, weight: .heavy))
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
                .font(.geist(size: 15, weight: .semibold))
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
                .font(.geist(size: size * 0.8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, size * 0.55)
                .padding(.vertical, size * 0.14)
                .background(DayLiveStyle.doneGreen, in: Capsule())
        } else {
            Text(state.title)
                .font(.geist(size: size, weight: .bold))
                .lineLimit(1)
        }
    }
}

/// "1:26:10 left" · "+4:12 over" · "1:40:05 until Standup". Ticks on its own on the Lock Screen.
struct TimerLabel: View {
    let state: DayActivityAttributes.ContentState
    var size: CGFloat = 14

    private func unit(_ s: String) -> some View {
        Text(s).font(.geist(size: size * 0.6, weight: .bold)).kerning(0.6).opacity(0.85).lineLimit(1)
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
        .font(.mono(size, .medium))   // v55: SF Mono readout
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
    var compact = false   // v63: 30 pt when the Macs share the card

    var body: some View {
        if state.canPause == true, let id = state.actionBlockID {
            let paused = state.paused == true
            Button(intent: PauseBlockIntent(blockID: id, pause: !paused)) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.geist(size: 14, weight: .bold))
                    .foregroundStyle(paused ? .black : HDTone.soft)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                    // v62 JobTrail: square hover button; paused = amber so Resume stands out.
                    .background(paused ? HDTone.amber : HDTone.hover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(paused ? Color.clear : HDTone.lineDark))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(paused ? "Resume" : "Pause")
        }
    }
}

struct BlockActionButton: View {
    let state: DayActivityAttributes.ContentState
    var compact = false

    var body: some View {
        if let id = state.actionBlockID, let action = state.action {
            Button(intent: BlockActionIntent(blockID: id, action: action)) {
                // v62 JobTrail pills: Done = success, Step = accent, Start now = neutral.
                let ink: Color = action == .done ? HDTone.green : action == .checkStep ? HDTone.amber : HDTone.soft
                let fill: Color = action == .done ? HDTone.greenBG : action == .checkStep ? HDTone.amberBG : HDTone.hover
                let line: Color = action == .done ? HDTone.green.opacity(0.45) : action == .checkStep ? HDTone.amber.opacity(0.45) : HDTone.lineDark
                HStack(spacing: 5) {
                    HDIcon(buttonSymbol(action), size: 14).foregroundStyle(ink)
                    Text(buttonTitle(action)).foregroundStyle(ink)
                }
                    .font(.geist(size: 13.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: compact ? 30 : 34)
                    .background(fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(line, lineWidth: 1))
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
                HDIcon(state.iconName ?? "event", size: 15)   // v47: solid icon instead of the app square
                TimerLabel(state: state, size: 13)
                    .foregroundStyle(state.paused == true ? Color(white: 0.75) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if let nextTime {
                    Text(nextTime)
                        .font(.geist(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Text(state.title)
                .font(.geist(size: 16, weight: .bold))
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
        if state.closed == true, family != .small, !(state.macs ?? []).isEmpty {
            JobTrailBoard(state: state, headline: "Day closed")   // v65: closed day → JobTrail board
        } else if state.closed == true {
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
                .font(.geist(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.white.opacity(0.2), in: Capsule())
        }
    }

    /// "3h" over "10m focus": big digits, small "focus" (v24 D).
    private var focusText: some View {
        let m = state.focusMinutes ?? 0
        let big = compact ? 22.0 : 32.0
        func n(_ s: String) -> Text { Text(s).font(.geist(size: big, weight: .heavy)) }
        func u(_ s: String) -> Text { Text(s).font(.geist(size: big * 0.45, weight: .heavy)) }
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
                    .layoutPriority(1)   // the hours keep their size; the bars take what's left
                Spacer(minLength: 4)
                if let hours = state.focusByHour, hours.contains(where: { $0 > 0 }) {
                    // v37: thick bars like the mockup (were 4 pt in the Island). Each is up to 10–12 pt wide
                    // and shares the space left of the hours, so many hours never push the text off.
                    let maxH: CGFloat = compact ? 30 : 44
                    HStack(alignment: .bottom, spacing: compact ? 3 : 4) {
                        ForEach(hours.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(hours[i] >= 15 ? DayLiveStyle.doneGreen : Color.white.opacity(0.22))
                                .frame(minWidth: 5, maxWidth: compact ? 10 : 12)
                                .frame(height: max(6, CGFloat(min(hours[i], 60) / 60) * maxH))
                        }
                    }
                    .frame(height: maxH, alignment: .bottom)
                }
            }
            HStack {
                Text("\(done)/\(total) done")
                Spacer(minLength: 6)
                if let nextLine { Text(nextLine).lineLimit(1) }
            }
            .font(.geist(size: 13, weight: .semibold))
            .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 16)
        .padding(.vertical, compact ? 4 : 14)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.geist(size: 9, weight: .heavy))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.mono(compact ? 14 : 16, .heavy))
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
                HDIcon("car", size: 26).foregroundStyle(DayLiveStyle.calendarBlue)   // v47
                if let a = state.arriveAt {
                    Text("Arrive \(a.formatted(date: .omitted, time: .shortened))")
                        .font(.geist(size: 16, weight: .heavy))
                } else {
                    Text("Driving").font(.geist(size: 16, weight: .heavy))
                }
                Spacer(minLength: 4)
                if let since = state.driveSince {
                    HStack(spacing: 3) {
                        Text("Driving ·")
                        Text(timerInterval: since...since.addingTimeInterval(6 * 3600), countsDown: false)
                            .monospacedDigit()
                            .frame(width: 56, alignment: .leading)   // fits 1:02:03
                    }
                    .font(.geist(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.geist(size: 21, weight: .bold)).lineLimit(1)
                    if let spare {
                        Text(late ? "\(-spare) min late" : "\(spare) min to spare")
                            .font(.geist(size: 13, weight: .bold))
                            .foregroundStyle(late ? HDTone.danger : DayLiveStyle.doneGreen)
                    }
                }
                Spacer(minLength: 0)
                HDIcon("car", size: 44).foregroundStyle(DayLiveStyle.calendarBlue)   // v47: your car, solid, no square
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

    private static let overYellow = HDTone.amber

    /// v23: the block's icon in a soft capsule of its color (the timer beside it uses the same color).
    /// Free time = a solid green F (kept from v22). Minimal view = this capsule alone.
    var body: some View {
        let phase = IslandPhase(state)
        let col = color(phase)
        Group {
            switch phase {
            case .free:
                HDIcon("free", size: size * 0.86).foregroundStyle(DayLiveStyle.doneGreen)   // v47: solid, no circle
                    .frame(width: size, height: size)
            default:
                HDIcon(state.iconName ?? "event", size: size * 0.86).foregroundStyle(col)   // v47: solid, no capsule
                    .frame(width: size * 1.36, height: size)
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
                .foregroundStyle(HDTone.amber)
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
        .font(.mono(14, .semibold))   // v26: small and tight to the camera
    }

    /// "1d 4h" → big digits, small letters (v23 #3).
    static func bigSmall(_ s: String) -> Text {
        s.reduce(Text("")) { acc, ch in
            acc + Text(String(ch)).font(.geist(size: ch.isNumber ? 14 : 9, weight: .semibold))
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


// MARK: - v61 Macs from JobTrail

/// The MacBook Pro and Mac mini side by side: status dot, newest job with a live elapsed clock
/// (it counts by itself, no updates needed), job counts and a GPU bar. Green running, amber waiting,
/// red offline, grey idle.
struct MacStrip: View {
    let macs: [MacLive]
    var compact = false
    var body: some View {
        HStack(spacing: 6) {
            ForEach(macs.prefix(2), id: \.name) { MacChip(mac: $0, compact: compact) }
        }
    }
}

struct MacChip: View {
    let mac: MacLive
    var compact = false

    private var status: HDStatus {
        switch mac.statusRaw {
        case "running": return .running
        case "waiting": return .waiting
        case "failed": return .failed
        default: return .idle
        }
    }
    private var short: String { mac.desktop ? "MINI" : "MBP" }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: mac.desktop ? "macmini" : "laptopcomputer")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(status == .idle ? HDTone.faintDark : status.color)
                JTStatusDot(status: status, size: 5, animated: false)
                if mac.running > 1 {
                    Text("\(mac.running)").font(.mono(9, .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 3).background(Capsule().fill(HDTone.green))
                }
                if mac.online, let top = mac.top {
                    Text(top)
                        .font(.mono(compact ? 9.5 : 10, .medium))
                        .foregroundStyle(HDTone.soft)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Spacer(minLength: 2)
                    if let since = mac.topSince, mac.topWaiting != true {
                        Text(timerInterval: since...since.addingTimeInterval(24 * 3600), countsDown: false)
                            .font(.mono(compact ? 9.5 : 10, .semibold))
                            .foregroundStyle(status.color)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48, alignment: .trailing)
                    } else {
                        Text("WAIT").font(.mono(9, .semibold)).foregroundStyle(HDTone.amber)
                    }
                } else {
                    Text("\(short) · \(mac.online ? "IDLE" : "OFFLINE")")
                        .font(.mono(9, .semibold)).kerning(0.5)
                        .foregroundStyle(mac.online ? HDTone.faintDark : HDTone.danger)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            // GPU as a hairline bar (amber), no text: keeps the card inside iOS's 160 pt
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(HDTone.hover)
                    Capsule().fill(HDTone.amber.opacity(0.85))
                        .frame(width: g.size.width * CGFloat(min(max(mac.gpu ?? 0, 0), 100)) / 100)
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(status == .running ? HDTone.green.opacity(0.4) : (status == .failed ? HDTone.danger.opacity(0.4) : HDTone.lineDark), lineWidth: 1))
    }
}


/// v62: the Macs as one quiet JobTrail row (no boxes): glyph · status · count · job · live clock, split by a hairline.
struct MacRow: View {
    let macs: [MacLive]
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(macs.prefix(2).enumerated()), id: \.offset) { i, m in
                if i > 0 { Rectangle().fill(HDTone.hover).frame(width: 1, height: 24) }
                MacRowItem(mac: m)
            }
        }
    }
}

/// v63: two tight lines per Mac. Line 1: glyph · status · count · job · live clock.
/// Line 2: GPU and memory as hairline meters with their numbers (JobTrail's machine meters).
struct MacRowItem: View {
    let mac: MacLive
    private var status: HDStatus {
        switch mac.statusRaw { case "running": .running; case "waiting": .waiting; case "failed": .failed; default: .idle }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: mac.desktop ? "macmini" : "laptopcomputer")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HDTone.dim)
                Circle().fill(status == .idle ? HDTone.faintDark : status.color).frame(width: 5, height: 5)
                if !mac.online {
                    Text("OFFLINE").font(.mono(9.5, .semibold)).kerning(0.6).foregroundStyle(HDTone.danger)
                    Spacer(minLength: 0)
                } else if let top = mac.top {
                    if mac.running > 1 {
                        Text("\(mac.running)×").font(.mono(9.5, .bold)).foregroundStyle(status.color).fixedSize()
                    }
                    Text(Self.short(top))
                        .font(.mono(10, .medium)).foregroundStyle(HDTone.soft)
                        .lineLimit(1).truncationMode(.middle)
                        .layoutPriority(-1)
                    Spacer(minLength: 2)
                    if let since = mac.topSince, mac.topWaiting != true {
                        Text(timerInterval: since...since.addingTimeInterval(7 * 24 * 3600), countsDown: false)
                            .font(.mono(10, .semibold)).foregroundStyle(status.color)
                            .monospacedDigit().multilineTextAlignment(.trailing)
                            .frame(width: 46, alignment: .trailing)
                    } else {
                        Text("WAIT").font(.mono(9, .semibold)).foregroundStyle(HDTone.amber)
                    }
                } else {
                    Text("IDLE").font(.mono(9.5, .semibold)).kerning(0.6).foregroundStyle(HDTone.faintDark)
                    Spacer(minLength: 0)
                }
            }
            if mac.online {
                HStack(spacing: 8) {
                    meter("GPU", mac.gpu, HDTone.amber)
                    meter("MEM", mac.mem, HDTone.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "GPU ▬▬▬▬── 98" : a hairline bar and the number; amber turns red above 90%.
    private func meter(_ key: String, _ value: Int?, _ color: Color) -> some View {
        let v = min(max(value ?? 0, 0), 100)
        let c = v >= 90 ? HDTone.danger : color
        return HStack(spacing: 4) {
            Text(key).font(.mono(8, .semibold)).foregroundStyle(HDTone.faintDark).fixedSize()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(HDTone.hover)
                    Capsule().fill(c).frame(width: max(2, g.size.width * CGFloat(v) / 100))
                }
            }
            .frame(height: 3)
            Text(value.map { "\($0)" } ?? "–").font(.mono(8.5, .semibold)).foregroundStyle(value == nil ? HDTone.faintDark : c)
                .monospacedDigit().frame(width: 16, alignment: .trailing)
        }
    }

    /// Short job names: "~/ai/ltx-2-mlx/.venv/bin/python render_s01.py" → "render_s01.py",
    /// "python3 train.py" → "train.py", "S01_run2.sh · S01.ok" → "S01_run2.sh".
    static func short(_ s: String) -> String {
        var main = (s.components(separatedBy: " · ").first ?? s).trimmingCharacters(in: .whitespaces)
        var prefix = ""
        if main.hasPrefix("watch:") {   // JobTrail watchers: "watch: ssh mini 'grep -q …'" → "watch · grep"
            prefix = "watch · "
            main = String(main.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if main.hasPrefix("ssh "), let q = main.firstIndex(where: { $0 == "'" || $0 == "\"" }) {
                main = String(main[main.index(after: q)...])
            }
        }
        let words = main.split(separator: " ").map(String.init).filter { !$0.hasPrefix("-") && !$0.contains("/dev/null") }
        func base(_ w: String) -> String {
            w.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")).split(separator: "/").last.map(String.init) ?? w
        }
        guard let first = words.first else { return prefix + base(main) }
        if base(first) == "ssh", words.count > 1 { return prefix + "ssh \(words[1])" }   // "ssh mini 'until …'" → "ssh mini"
        let interpreters: Set<String> = ["python", "python3", "bash", "sh", "zsh", "node", "bun", "uv", "env", "until", "while"]
        var i = 0
        while i < words.count - 1, interpreters.contains(base(words[i])) || (base(words[i]).hasPrefix("python") && words[i].contains("/")) { i += 1 }
        let pick = base(words[i])
        return prefix + (pick.isEmpty || pick == "-" ? base(first) : pick)
    }
}


// MARK: - v65 Day done → JobTrail board

/// When your day is complete (or closed), the Live Activity stops wasting space and becomes a JobTrail
/// board: both Macs with battery, a GPU graph, memory, and up to three jobs each with live clocks.
struct JobTrailBoard: View {
    let state: DayActivityAttributes.ContentState
    let headline: String

    private var macs: [MacLive] { Array((state.macs ?? []).prefix(2)) }

    var body: some View {
        let run = macs.reduce(0) { $0 + $1.running }, wait = macs.reduce(0) { $0 + $1.waiting }
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(HDTone.green)
                Text(headline.uppercased() + (state.totalCount.map { t in " · \(state.doneCount ?? 0)/\(t)" } ?? ""))
                    .font(.mono(9.5, .semibold)).kerning(0.8).foregroundStyle(HDTone.green).lineLimit(1)
                Spacer(minLength: 6)
                JTECGMark().frame(width: 12, height: 12)
                Text(run > 0 ? "\(run) RUNNING" + (wait > 0 ? " · \(wait) WAIT" : "") : "JOBTRAIL · IDLE")
                    .font(.mono(9.5, .semibold)).kerning(0.6)
                    .foregroundStyle(run > 0 ? HDTone.green : HDTone.faintDark).lineLimit(1)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(macs.enumerated()), id: \.offset) { i, m in
                    if i > 0 { Rectangle().fill(HDTone.hover).frame(width: 1) }
                    BoardColumn(mac: m)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // v66: border on the card's real bounds (not the content's), so iOS's 160 pt cut can't clip it
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ContainerRelativeShape().strokeBorder(run > 0 ? HDTone.green.opacity(0.4) : HDTone.lineDark, lineWidth: 1)
        }
    }
}

private struct BoardColumn: View {
    let mac: MacLive
    private var status: HDStatus {
        switch mac.statusRaw { case "running": .running; case "waiting": .waiting; case "failed": .failed; default: .idle }
    }
    private var batterySymbol: String {
        if mac.charging == true { return "battery.100.bolt" }
        let b = mac.battery ?? 0
        return b > 87 ? "battery.100" : b > 62 ? "battery.75" : b > 37 ? "battery.50" : b > 12 ? "battery.25" : "battery.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // name · battery (MacBook) / status
            HStack(spacing: 5) {
                Image(systemName: mac.desktop ? "macmini" : "laptopcomputer")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(HDTone.dim)
                Text(mac.desktop ? "Mac mini" : "MacBook Pro").font(.geist(size: 12.5, weight: .semibold))
                    .foregroundStyle(HDTone.textHi).lineLimit(1)
                Spacer(minLength: 2)
                if let b = mac.battery {
                    Image(systemName: batterySymbol).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(b <= 20 && mac.charging != true ? HDTone.danger : (mac.charging == true ? HDTone.green : HDTone.soft))
                    Text("\(b)%").font(.mono(9.5, .semibold)).monospacedDigit()
                        .foregroundStyle(b <= 20 && mac.charging != true ? HDTone.danger : HDTone.soft)
                } else {
                    JTStatusDot(status: status, size: 5, animated: false)
                }
            }
            if !mac.online {
                Text("OFFLINE").font(.mono(10, .semibold)).kerning(0.8).foregroundStyle(HDTone.danger)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            } else {
                // GPU graph with GPU / MEM numbers
                let hot = (mac.gpu ?? 0) >= 90
                HStack(spacing: 4) {
                    Text("GPU").font(.mono(8, .semibold)).foregroundStyle(HDTone.faintDark)
                    Text("\(mac.gpu ?? 0)").font(.mono(9.5, .semibold)).foregroundStyle(hot ? HDTone.danger : HDTone.amber)
                    Spacer(minLength: 2)
                    Text("MEM").font(.mono(8, .semibold)).foregroundStyle(HDTone.faintDark)
                    Text("\(mac.mem ?? 0)").font(.mono(9.5, .semibold)).foregroundStyle(HDTone.blue)
                }
                JTSpark(values: (mac.gpuHist ?? [mac.gpu ?? 0]).map(Double.init), color: hot ? HDTone.danger : HDTone.amber)
                    .frame(height: 13)
                    .padding(.bottom, 2)
                    .background(alignment: .bottom) { Rectangle().fill(HDTone.hover).frame(height: 1) }
                // jobs
                let jobs = mac.jobs ?? []
                if jobs.isEmpty {
                    Text("NO JOBS").font(.mono(9, .semibold)).kerning(0.6).foregroundStyle(HDTone.faintDark)
                }
                ForEach(Array(jobs.prefix(3).enumerated()), id: \.offset) { _, j in
                    HStack(spacing: 4) {   // v66: fixed 12 pt rows
                        Circle().fill(j.waiting ? HDTone.amber : HDTone.green).frame(width: 4, height: 4)
                        Text(j.label).font(.mono(9.5, .medium)).foregroundStyle(HDTone.soft)
                            .lineLimit(1).truncationMode(.middle).layoutPriority(-1)
                        Spacer(minLength: 2)
                        if j.waiting {
                            Text("WAIT").font(.mono(8.5, .semibold)).foregroundStyle(HDTone.amber)
                        } else {
                            Text(timerInterval: j.since...j.since.addingTimeInterval(7 * 86_400), countsDown: false)
                                .font(.mono(9.5, .semibold)).foregroundStyle(HDTone.green)
                                .monospacedDigit().multilineTextAlignment(.trailing)
                                .frame(width: Date.now.timeIntervalSince(j.since) >= 36_000 ? 54 : 46, alignment: .trailing)
                        }
                    }
                    .frame(height: 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
