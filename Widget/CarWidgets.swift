import SwiftUI
import WidgetKit

// v31 car widgets (v30 mockups). They only show what the app last read; they never call Tesla.

struct CarEntry: TimelineEntry {
    let date: Date
    let car: CarSnapshot?
}

struct CarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarEntry { CarEntry(date: .now, car: .sample()) }
    func getSnapshot(in context: Context, completion: @escaping (CarEntry) -> Void) {
        completion(CarEntry(date: .now, car: CarShared.load() ?? .sample()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CarEntry>) -> Void) {
        let now = Date.now
        // Redraw every 15 min so "12m ago" and charging times stay right; data changes come from the app.
        let entries = (0..<8).map { CarEntry(date: now.addingTimeInterval(Double($0) * 900), car: CarShared.load()) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 3600))))
    }
}

private let carGreen = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
private let carCyan = Color(hex: "#64D2FF")
private let carBG = Color(red: 0.11, green: 0.114, blue: 0.13)

private func ago(_ d: Date, now: Date) -> String {
    let m = max(0, Int(now.timeIntervalSince(d) / 60))
    return m < 1 ? "just now" : (m < 60 ? "\(m)m ago" : "\(m / 60)h ago")
}

private struct CarPicture: View {
    var body: some View { Image("CarFront").resizable().scaledToFit() }   // v40: front view, matte
}

private struct NotConnected: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HDIcon("car", size: 22).foregroundStyle(.white)
            Text("Connect your car in Hyperday").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            Text("Settings › Car").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: S1 · Car glance

struct CarGlanceView: View {
    let entry: CarEntry
    var body: some View {
        if let c = entry.car {
            VStack(alignment: .leading, spacing: 0) {
                Text(c.name).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(c.battery)%").font(.system(size: 22, weight: .heavy)).foregroundStyle(carGreen)
                    Text("\(c.rangeMiles) mi").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                CarPicture().padding(.horizontal, -6)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: c.locked == false ? "lock.open.fill" : "lock.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(c.locked == false ? .red : carGreen)
                    Text(ago(c.updatedAt, now: entry.date))   // v40: the lock icon says it
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
        } else { NotConnected() }
    }
}

// MARK: S2 · Ready for today?

struct CarReadyView: View {
    let entry: CarEntry
    var body: some View {
        if let c = entry.car {
            let need = c.todayMiles ?? 0
            let ok = c.enoughForToday ?? true
            VStack(alignment: .leading, spacing: 6) {
                Text("Ready for today?").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 8)
                    Circle().trim(from: 0, to: min(1, CGFloat(c.rangeMiles) / 330))
                        .stroke(ok ? carGreen : .orange, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: ok ? "checkmark" : "exclamationmark").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                }
                .frame(width: 62, height: 62).frame(maxWidth: .infinity)
                Text(c.todayMiles == nil ? "No trips planned" : "\(need) mi planned").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                Text("\(c.rangeMiles) mi in the car").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
        } else { NotConnected() }
    }
}

// MARK: M1 · Car + your day

struct CarDayView: View {
    let entry: CarEntry
    var body: some View {
        if let c = entry.car {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c.battery)% · \(c.rangeMiles) mi").font(.system(size: 15, weight: .heavy)).foregroundStyle(carGreen)
                    HStack(spacing: 5) {   // v40: lock icon instead of the word
                        Image(systemName: c.locked == false ? "lock.open.fill" : "lock.fill")
                            .foregroundStyle(c.locked == false ? Color.red : .white.opacity(0.6))
                        if let place = c.place { Text(place) }
                    }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Spacer(minLength: 0)
                    CarPicture()
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXT TRIP").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white.opacity(0.5))
                    if let t = c.nextTripTitle, let leave = c.leaveBy {
                        Text("Leave \(leave.formatted(date: .omitted, time: .shortened)) → \(t)")
                            .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).lineLimit(2)
                    } else {
                        Text("No trips today").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    }
                    Text("TODAY").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white.opacity(0.5))
                    let need = c.todayMiles ?? 0
                    ProgressView(value: min(1, Double(need) / Double(max(c.rangeMiles, 1)))).tint(Theme_blue)
                    HStack {
                        Text("\(need) mi of \(c.rangeMiles)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        if c.enoughForToday != false {
                            Text("✓ enough").font(.system(size: 10, weight: .heavy)).foregroundStyle(carGreen)
                        } else {
                            Text("charge first").font(.system(size: 10, weight: .heavy)).foregroundStyle(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else { NotConnected() }
    }
}

private let Theme_blue = Color(red: 10 / 255, green: 132 / 255, blue: 1)

// MARK: M2 · Charging (small = StandBy)

struct CarChargeView: View {
    let entry: CarEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let c = entry.car {
            let limit = Double(c.chargeLimit ?? 80)
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.charging ? "CHARGING" : "BATTERY").font(.system(size: 10, weight: .heavy)).foregroundStyle(carGreen)
                    Text("\(c.battery)%").font(.system(size: 40, weight: .heavy)).foregroundStyle(carGreen)
                    Text(c.fullAt.map { "→ \(Int(limit))% · \($0.formatted(date: .omitted, time: .shortened))" } ?? "Limit \(Int(limit))%")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Spacer(minLength: 0)
                    ProgressView(value: Double(c.battery) / 100).tint(carGreen)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(Circle().fill(c.charging ? carGreen : Color(white: 0.4)))
                        Text(c.charging ? "Charging · \(c.battery)% → \(Int(limit))%" : "Not charging · \(c.battery)%")
                            .font(.system(size: 15, weight: .heavy)).foregroundStyle(c.charging ? carGreen : .white)
                        Spacer()
                        if let kw = c.chargeKW, c.charging {
                            Text("\(Int(kw)) kW").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    ProgressView(value: Double(c.battery) / 100).tint(carGreen)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.fullAt.map { "Full by \($0.formatted(date: .omitted, time: .shortened))" } ?? "\(c.rangeMiles) mi range")
                                .font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                            if let leave = c.leaveBy {
                                let ready = (c.fullAt ?? .distantPast) <= leave
                                Text(ready ? "Ready before Leave by \(leave.formatted(date: .omitted, time: .shortened)) ✓"
                                           : "Not full by \(leave.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Spacer()
                        CarPicture().frame(width: 120)
                    }
                }
            }
        } else { NotConnected() }
    }
}

// MARK: L1 · Car hub

struct CarHubView: View {
    let entry: CarEntry
    var body: some View {
        if let c = entry.car {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(c.name).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Text("\(c.battery)% · \(c.rangeMiles) mi").font(.system(size: 14, weight: .heavy)).foregroundStyle(carGreen)
                }
                Text([c.place, "parked", ago(c.updatedAt, now: entry.date)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                CarPicture().padding(.horizontal, -8)
                HStack(spacing: 6) {
                    if let l = c.locked { chip(l ? "lock.fill" : "lock.open.fill", l ? "Locked" : "Unlocked", l ? carGreen : .red) }
                    if let s = c.sentry { chip("shield.fill", s ? "Sentry" : "Sentry off", s ? Color(hex: "#BF5AF2") : .gray) }
                    if let t = c.insideF { chip("thermometer.medium", "\(t)°F", Theme_blue) }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    button("snowflake", "Climate", Theme_blue)
                    button("lock.fill", "Lock", carGreen)
                }
            }
        } else { NotConnected() }
    }

    private func chip(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(color))
            Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        }
        .padding(.leading, 3).padding(.trailing, 9).padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // Commands need Tesla's signed-command protocol (next step); until then these open the Car tab.
    private func button(_ icon: String, _ title: String, _ color: Color) -> some View {
        Link(destination: URL(string: "hyperday://car")!) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 36).background(Capsule().fill(color))
        }
    }
}

// MARK: Lock Screen

struct CarLockView: View {
    let entry: CarEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let c = entry.car
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(c?.battery ?? 0), in: 0...100) {
                HDIcon("car", size: 14)
            } currentValueLabel: {
                Text(c.map { "\($0.battery)" } ?? "–")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryInline:
            Text(c.map { "Car \($0.battery)%" + ($0.leaveBy.map { " · Leave \($0.formatted(date: .omitted, time: .shortened))" } ?? " · \($0.rangeMiles) mi") } ?? "Car · connect in Hyperday")
        default:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) { HDIcon("car", size: 16); Text(c.map { "\($0.battery)% · \($0.rangeMiles) mi" } ?? "Car").font(.system(size: 14, weight: .heavy)) }
                if let c {
                    Text(((c.locked == false) ? "Unlocked" : "Locked") + (c.insideF.map { " · \($0)°F" } ?? ""))
                        .font(.system(size: 12, weight: .semibold))
                    if let leave = c.leaveBy {
                        Text("Leave \(leave.formatted(date: .omitted, time: .shortened))").font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CarLockReadyView: View {
    let entry: CarEntry
    var body: some View {
        let c = entry.car
        Gauge(value: Double(c?.todayMiles ?? 0), in: 0...Double(max(c?.rangeMiles ?? 1, 1))) {
            Text("mi")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Image(systemName: (c?.enoughForToday ?? true) ? "checkmark" : "exclamationmark").font(.system(size: 12, weight: .heavy))
                Text(c?.todayMiles.map { "\($0)mi" } ?? "–").font(.system(size: 9, weight: .bold))
            }
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: Widgets

struct CarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HyperdayCarGlanceWidget()
        HyperdayCarReadyWidget()
        HyperdayCarDayWidget()
        HyperdayCarChargeWidget()
        HyperdayCarHubWidget()
        HyperdayCarLockWidget()
        HyperdayCarLockReadyWidget()
    }
}

private extension View {
    func carBackground() -> some View {
        containerBackground(for: .widget) { carBG }.widgetURL(URL(string: "hyperday://car"))
    }
}

struct HyperdayCarGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.glanceKind, provider: CarProvider()) { CarGlanceView(entry: $0).carBackground() }
            .configurationDisplayName("Car").description("Battery, range and lock state, with your car.")
            .supportedFamilies([.systemSmall])
    }
}

struct HyperdayCarReadyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.readyKind, provider: CarProvider()) { CarReadyView(entry: $0).carBackground() }
            .configurationDisplayName("Ready for today?").description("Today's planned miles against the car's range.")
            .supportedFamilies([.systemSmall])
    }
}

struct HyperdayCarDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.dayKind, provider: CarProvider()) { CarDayView(entry: $0).carBackground() }
            .configurationDisplayName("Car + your day").description("Your next trip, leave-by time and today's miles.")
            .supportedFamilies([.systemMedium])
    }
}

struct HyperdayCarChargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.chargeKind, provider: CarProvider()) { CarChargeView(entry: $0).carBackground() }
            .configurationDisplayName("Charging").description("Charge level, finish time and whether it's ready before you leave. Small size works in StandBy.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HyperdayCarHubWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.hubKind, provider: CarProvider()) { CarHubView(entry: $0).carBackground() }
            .configurationDisplayName("Car hub").description("Your car, its status and quick buttons.")
            .supportedFamilies([.systemLarge])
    }
}

struct HyperdayCarLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.lockKind, provider: CarProvider()) {
            CarLockView(entry: $0)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(URL(string: "hyperday://car"))
        }
        .configurationDisplayName("Car (Lock Screen)").description("Battery gauge, status card or a line above the clock.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct HyperdayCarLockReadyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.lockReadyKind, provider: CarProvider()) {
            CarLockReadyView(entry: $0)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(URL(string: "hyperday://car"))
        }
        .configurationDisplayName("Range vs today").description("A check when the car has enough range for today's trips.")
        .supportedFamilies([.accessoryCircular])
    }
}
