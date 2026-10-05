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
    /// Category color of the live block (bar + icon); green when nothing is live.
    var accentColor: Color { accentHex.map { Color(hex: $0) } ?? DayLiveStyle.accent }
}

// MARK: - Lock Screen card

struct LockScreenCard: View {
    let state: DayActivityAttributes.ContentState
    var isStale: Bool = false

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
        if let f = state.focusMinutes, f > 0 { t += " · " + (f >= 60 ? "\(f / 60)h \(f % 60)m" : "\(f)m") + " focus" }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row (like Tesla's card): [app icon] 26:10 left ······ Next: Standup 10:30 PM
            HStack(spacing: 7) {
                AppMark(size: 20)
                TimerLabel(state: state, size: 16)
                    .foregroundStyle(headsUp ? DayLiveStyle.stepYellow : state.paused == true ? Color(white: 0.75) : .white)
                    .fixedSize()
                Spacer(minLength: 6)
                if outOfDate && !headsUp && state.paused != true {
                    Text(nextText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                } else if let score {
                    Text(score)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    CardTitle(state: state, size: 23)
                    if state.paused == true {
                        pill("Paused — the end moves later with it")
                    } else if headsUp, let h = state.headsUp {
                        Text(h)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DayLiveStyle.stepYellow)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(DayLiveStyle.stepYellow.opacity(0.2), in: Capsule())
                    } else {
                        secondLine
                    }
                }
                Spacer(minLength: 0)
                if FreeRing.applies(state) { FreeRing(state: state, size: 44) }
                else { SourceIcon(source: state.source, size: 44, tint: state.source == .free ? nil : state.accentColor, iconName: state.iconName) }
            }
            .padding(.top, 2)

            HStack(spacing: 12) {
                DayBar(state: barState, height: 6)
                PauseButton(state: state)
                BlockActionButton(state: state)   // Done / Step n/N are always yellow, never the category color
            }
            .padding(.top, 6)
        }
        .foregroundStyle(.white)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 13)
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
            if state.paused == true, let left = state.pausedLeft {
                // v20: frozen while paused.
                Text("Paused · \(Self.clock(left)) left")
            } else if let over = state.overSince {
                HStack(spacing: 0) {
                    Text("+")
                    timer(over...over.addingTimeInterval(24 * 3600), down: false)
                    Text(" over")
                }
            } else if let end = state.currentEnd, end > Date.now {
                HStack(spacing: 4) {
                    timer(Date.now...end, down: true)
                    Text("left")
                }
            } else if let next = state.nextStart, next > Date.now {
                HStack(spacing: 4) {
                    timer(Date.now...next, down: true)
                    // Just "free": the next block's name is already on the line below. A long name here
                    // made the fixed-size top row wider than the card and pushed it off both edges.
                    Text("free")
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: size, weight: .bold).monospacedDigit())
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
                    .frame(width: 36, height: 36)
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
                    .frame(height: 36)
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

/// v22: free time → a green ring that fills live as the gap runs out, with hours left inside
/// ("8h LEFT"); in the last hour, a live mm:ss. Replaces the clock tile.
struct FreeRing: View {
    let state: DayActivityAttributes.ContentState
    var size: CGFloat = 44

    static func applies(_ s: DayActivityAttributes.ContentState) -> Bool {
        s.source == .free && s.closed != true && s.freeStart != nil && s.nextStart != nil
    }

    var body: some View {
        if let from = state.freeStart, let to = state.nextStart, from < to {
            ZStack {
                ProgressView(timerInterval: from...to, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(DayLiveStyle.doneGreen)
                if let c = IslandTimer.coarse(until: to) {
                    VStack(spacing: -1) {
                        Text(c).font(.system(size: size * 0.27, weight: .heavy)).minimumScaleFactor(0.6)
                        Text("LEFT").font(.system(size: size * 0.16, weight: .bold)).opacity(0.8)
                    }
                    .lineLimit(1)
                    .foregroundStyle(DayLiveStyle.doneGreen)
                    .padding(.horizontal, size * 0.14)
                } else {
                    Text(timerInterval: Date.now...max(to, Date.now), countsDown: true)
                        .font(.system(size: size * 0.22, weight: .heavy).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DayLiveStyle.doneGreen)
                        .padding(.horizontal, size * 0.12)
                }
            }
            .frame(width: size, height: size)
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
                DayBar(state: watchBar, height: 4)
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

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 6) {
            if !compact {
                HStack(spacing: 7) {
                    AppMark(size: 20)
                    Text("Day closed").font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 4)
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            HStack(alignment: .center, spacing: 10) {
                (Text("\(done)").foregroundColor(DayLiveStyle.doneGreen) + Text(" of \(total) done"))
                    .font(.system(size: compact ? 19 : 22, weight: .heavy))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let n = state.reviewCount, n > 0, let url = URL(string: "hyperday://close") {
                    Link(destination: url) {
                        Text("Review \(n)")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Color.white.opacity(0.2), in: Capsule())
                    }
                } else {
                    HStack(spacing: 4) {
                        HDIcon("done", size: 13)
                        Text("Closed")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DayLiveStyle.doneGreen)
                }
            }
            if total > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<min(total, 16), id: \.self) { i in
                        Capsule()
                            .fill(i < done ? DayLiveStyle.doneGreen : DayLiveStyle.stepYellow)
                            .frame(height: 5)
                    }
                }
            }
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1).padding(.vertical, 1)
            if let first = state.tomorrowFirst {
                HStack(alignment: .top, spacing: 8) {
                    stat("Tomorrow", time(first), .white)
                    if state.leaveBy != nil { stat("Leave by", time(state.leaveBy), .white) }
                    stat("Bed by", time(state.bedBy),
                         (state.bedBy ?? .distantFuture) > .now ? DayLiveStyle.doneGreen : Color(red: 1, green: 0.27, blue: 0.23))
                }
                if !compact, let title = state.tomorrowTitle {
                    Text("First up: \(title)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            } else {
                Text("Nothing planned tomorrow")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 16)
        .padding(.vertical, compact ? 4 : 12)
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
                            .frame(width: 48, alignment: .leading)
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
                    .overlay(Image(systemName: "car.fill").font(.system(size: 20)).foregroundStyle(.white))
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

    var body: some View {
        let phase = IslandPhase(state)
        ZStack {
            switch phase {
            case .running(let r), .free(let r):
                ProgressView(timerInterval: r, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(ringColor(phase))
            case .over:
                Circle().stroke(Self.overYellow, lineWidth: 2.5)
            case .upNext, .idle, .paused:
                Circle().stroke(.white.opacity(0.22), lineWidth: 2.5)
            }
            glyph(phase)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private func glyph(_ phase: IslandPhase) -> some View {
        switch phase {
        case .free:
            Text("F").font(.system(size: size * 0.38, weight: .black)).foregroundStyle(ringColor(phase))
        case .upNext, .idle, .paused:
            HDIcon(state.iconName ?? "event", size: size * 0.48).foregroundStyle(.white.opacity(0.7))
        default:
            HDIcon(state.iconName ?? "edit", size: size * 0.48).foregroundStyle(ringColor(phase))
        }
    }

    private func ringColor(_ phase: IslandPhase) -> Color {
        switch phase {
        case .over: return Self.overYellow
        case .free: return DayLiveStyle.doneGreen
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
                    Text(c).foregroundStyle(DayLiveStyle.doneGreen)
                } else {
                    sized(Date.now...r.upperBound, down: true).foregroundStyle(DayLiveStyle.doneGreen)
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
                    if let c = Self.coarse(until: next) { Text(c) } else { sized(Date.now...next, down: true) }
                }
                .foregroundStyle(.white.opacity(0.85))
            case .paused(let left):
                Text(TimerLabel.clock(left)).foregroundStyle(Color(white: 0.7))
            case .idle:
                DayRing(progress: state.dayProgress, accent: state.accentColor).frame(width: 20, height: 20)
            }
        }
        .font(.system(size: 15, weight: .semibold).monospacedDigit())
    }

    /// v21: an hour or more away → "2h" … "23h", then "1d" / "1d 4h". Hours round UP, so it never
    /// claims less time than there is. Under an hour → nil (use the live mm:ss timer).
    static func coarse(until date: Date, now: Date = .now) -> String? {
        let secs = date.timeIntervalSince(now)
        guard secs >= 3600 else { return nil }
        let hours = Int((secs / 3600).rounded(.up))
        if hours < 24 { return "\(hours)h" }
        let d = hours / 24, h = hours % 24
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }

    /// Minutes:seconds only (1:18:20 shows as 78:20), so the Island stays as narrow as Apple's own timers.
    /// The box is sized with a hidden "88:88" (or "888:88" past 100 minutes) so it never jumps.
    private func sized(_ range: ClosedRange<Date>, down: Bool) -> some View {
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        let sample = down && span >= 6000 ? "888:88" : "88:88"
        return Text(sample).hidden()
            .overlay(alignment: .trailing) {
                Text(timerInterval: range, pauseTime: nil, countsDown: down, showsHours: false)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
    }
}
