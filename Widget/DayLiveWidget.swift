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
                DynamicIslandExpandedRegion(.leading) {
                    AppMark(size: 22)
                        .padding(.leading, 6)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerLabel(state: context.state, size: 18)
                        .foregroundStyle(context.state.overSince != nil ? DayLiveStyle.stepYellow : .white)
                        .fixedSize()
                        .padding(.trailing, 6)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.closed == true {
                        DayClosedCard(state: context.state, compact: true)
                    } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                CardTitle(state: context.state, size: 20)
                                if let also = context.state.also {
                                    Text(also)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            SourceIcon(source: context.state.source, size: 36,
                                       tint: context.state.source == .free ? nil : context.state.accentColor,
                                       iconName: context.state.iconName)
                        }
                        HStack(spacing: 12) {
                            DayBar(state: context.state)
                            PauseButton(state: context.state)
                            BlockActionButton(state: context.state)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    }
                }
            } compactLeading: {
                if context.state.closed == true || context.state.driving == true {
                    SourceIcon(source: context.state.source, size: 22,
                               tint: context.state.source == .free ? nil : context.state.accentColor,
                               iconName: context.state.iconName)
                } else {
                    IslandRingIcon(state: context.state, size: 24)
                }
            } compactTrailing: {
                if context.state.closed == true || context.state.driving == true {
                    DayRing(progress: context.state.dayProgress, accent: context.state.accentColor)
                        .frame(width: 20, height: 20)
                } else {
                    IslandTimer(state: context.state)
                }
            } minimal: {
                IslandRingIcon(state: context.state, size: 22)
            }
            .keylineTint(context.state.accentColor)
        }
        .supplementalActivityFamilies([.small])   // Apple Watch Smart Stack (watchOS 11 / iOS 18)
    }
}
