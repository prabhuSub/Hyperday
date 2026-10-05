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
    }
}

struct DayLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayActivityAttributes.self) { context in
            // Lock Screen / banner
            ActivityFamilyCard(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(DayLiveStyle.cardTint.opacity(DayLiveStyle.glassOpacity))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Same layout as the Lock Screen card: [mark] ······ 1:26:10 left on top (beside the camera),
                // then title + category icon, then bar + button.
                // v24: long-press shows the same "day as a journey" card as the Lock Screen.
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.closed == true {
                        DayClosedCard(state: context.state, compact: true)
                    } else if context.state.driving == true {
                        DriveCard(state: context.state)
                    } else {
                        LockScreenCard(state: context.state, isStale: context.isStale, inIsland: true)
                    }
                }
            } compactLeading: {
                if context.state.closed == true || context.state.driving == true {
                    SourceIcon(source: context.state.source, size: 22,
                               tint: context.state.source == .free ? nil : context.state.accentColor,
                               iconName: context.state.iconName)
                } else {
                    IslandRingIcon(state: context.state, size: 22)
                }
            } compactTrailing: {
                if context.state.closed == true || context.state.driving == true {
                    DayRing(progress: context.state.dayProgress, accent: context.state.accentColor)
                        .frame(width: 20, height: 20)
                } else {
                    IslandTimer(state: context.state)
                }
            } minimal: {
                IslandRingIcon(state: context.state, size: 20)
            }
            .keylineTint(context.state.accentColor)
        }
        .supplementalActivityFamilies([.small])   // Apple Watch Smart Stack (watchOS 11 / iOS 18)
    }
}
