import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DayLiveWidgetBundle: WidgetBundle {
    var body: some Widget {
        DayLiveActivityWidget()
        HyperdayTodayWidget()
        HyperdayNowWidget()
        HyperdayDayWidget()
        HyperdayCircleWidget()
        HyperdayHeatWidget()
        HyperdayCalendarWidget()
        // CarWidgetsBundle().body   // v35: the big car widgets stay off with the Car tab
        HyperdayCarBatteryWidget()        // v38: small car widgets (A + inline J1)
        HyperdayCarBatteryLockWidget()    // v38: I
        HyperdayCarListWidget()           // v38: M
    }
}

struct DayLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayActivityAttributes.self) { context in
            // Lock Screen / banner
            ActivityFamilyCard(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(DayLiveStyle.cardTint.opacity(DayLiveStyle.glassOpacity))
                .activitySystemActionForegroundColor(.white)
                // Day closed: tapping the card opens the day review (set here, on the whole activity view;
                // a widgetURL inside the card left the expanded Dynamic Island blank).
                .widgetURL(context.state.closed == true && (context.state.reviewCount ?? 0) > 0 ? URL(string: "hyperday://close") : nil)
        } dynamicIsland: { context in
            let live = context.state.selfSwitched(isStale: context.isStale)
            let st = live.state
            return DynamicIsland {
                // Same layout as the Lock Screen card: [mark] ······ 1:26:10 left on top (beside the camera),
                // then title + category icon, then bar + button.
                // v24: long-press shows the same "day as a journey" card as the Lock Screen.
                DynamicIslandExpandedRegion(.bottom) {
                    if st.closed == true {
                        DayClosedCard(state: st, compact: true)
                    } else if st.driving == true {
                        DriveCard(state: st)
                    } else {
                        LockScreenCard(state: st, isStale: live.isStale, inIsland: true)
                    }
                }
            } compactLeading: {
                if st.closed == true {
                    ClosedCheck()                                   // v34 option 1: no more clock
                } else if st.driving == true {
                    SourceIcon(source: st.source, size: 22,
                               tint: st.source == .free ? nil : st.accentColor,
                               iconName: st.driving == true ? "car" : st.iconName)   // v30: your car's outline while driving
                } else {
                    IslandRingIcon(state: st, size: 22)
                }
            } compactTrailing: {
                if st.closed == true {
                    Text("\(st.doneCount ?? 0)/\(st.totalCount ?? 0)")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(DayLiveStyle.doneGreen)
                } else if st.driving == true {
                    DayRing(progress: st.dayProgress, accent: st.accentColor)
                        .frame(width: 20, height: 20)
                } else {
                    IslandTimer(state: st)
                }
            } minimal: {
                if st.closed == true { ClosedCheck() } else { IslandRingIcon(state: st, size: 20) }
            }
            .keylineTint(st.accentColor)
            .widgetURL(st.closed == true && (st.reviewCount ?? 0) > 0 ? URL(string: "hyperday://close") : nil)
        }
        .supplementalActivityFamilies([.small])   // Apple Watch Smart Stack (watchOS 11 / iOS 18)
    }
}


/// v34 (Island option 1): day closed = a green check in a tinted capsule, beside "4/8".
struct ClosedCheck: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(DayLiveStyle.doneGreen)
            .frame(width: 30, height: 22)
            .background(Capsule().fill(DayLiveStyle.doneGreen.opacity(0.24)))
    }
}
