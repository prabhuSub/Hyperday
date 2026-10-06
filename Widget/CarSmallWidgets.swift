import SwiftUI
import WidgetKit

// v38 small car widgets (v38b mockups, Prabhu picked A, I, J1, M).
// They show what the app last read; widgets never call Tesla and never wake the car.

/// Your car's side silhouette, traced from the app's 3D Model Y (filled, like the mockup).
struct CarSilhouette: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ r: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(r, 0.0218, 0.2959))
        path.addCurve(to: p(r, 0.0305, 0.4763), control1: p(r, 0.0000, 0.3506), control2: p(r, 0.0314, 0.4186))
        path.addCurve(to: p(r, 0.0150, 0.6479), control1: p(r, 0.0291, 0.5355), control2: p(r, 0.0173, 0.6021))
        path.addCurve(to: p(r, 0.0159, 0.7515), control1: p(r, 0.0123, 0.6938), control2: p(r, 0.0137, 0.7101))
        path.addCurve(to: p(r, 0.0278, 0.8979), control1: p(r, 0.0182, 0.7944), control2: p(r, 0.0200, 0.8683))
        path.addCurve(to: p(r, 0.0637, 0.9320), control1: p(r, 0.0355, 0.9290), control2: p(r, 0.0496, 0.9275))
        path.addCurve(to: p(r, 0.1124, 0.9260), control1: p(r, 0.0778, 0.9364), control2: p(r, 0.1038, 0.9512))
        path.addCurve(to: p(r, 0.1161, 0.7840), control1: p(r, 0.1211, 0.9024), control2: p(r, 0.1129, 0.8269))
        path.addCurve(to: p(r, 0.1325, 0.6642), control1: p(r, 0.1197, 0.7396), control2: p(r, 0.1243, 0.6997))
        path.addCurve(to: p(r, 0.1643, 0.5725), control1: p(r, 0.1402, 0.6302), control2: p(r, 0.1529, 0.5947))
        path.addCurve(to: p(r, 0.2021, 0.5355), control1: p(r, 0.1761, 0.5503), control2: p(r, 0.1884, 0.5385))
        path.addCurve(to: p(r, 0.2453, 0.5562), control1: p(r, 0.2157, 0.5340), control2: p(r, 0.2317, 0.5370))
        path.addCurve(to: p(r, 0.2845, 0.6509), control1: p(r, 0.2594, 0.5754), control2: p(r, 0.2754, 0.6169))
        path.addCurve(to: p(r, 0.3022, 0.7618), control1: p(r, 0.2940, 0.6849), control2: p(r, 0.2995, 0.7115))
        path.addCurve(to: p(r, 0.3022, 0.9571), control1: p(r, 0.3054, 0.8136), control2: p(r, 0.3009, 0.9216))
        path.addCurve(to: p(r, 0.3104, 0.9763), control1: p(r, 0.3036, 0.9941), control2: p(r, 0.2426, 0.9749))
        path.addCurve(to: p(r, 0.7101, 0.9689), control1: p(r, 0.3782, 0.9793), control2: p(r, 0.6427, 1.0000))
        path.addCurve(to: p(r, 0.7137, 0.7840), control1: p(r, 0.7774, 0.9364), control2: p(r, 0.7105, 0.8343))
        path.addCurve(to: p(r, 0.7301, 0.6642), control1: p(r, 0.7169, 0.7322), control2: p(r, 0.7219, 0.6997))
        path.addCurve(to: p(r, 0.7619, 0.5725), control1: p(r, 0.7378, 0.6302), control2: p(r, 0.7506, 0.5947))
        path.addCurve(to: p(r, 0.7997, 0.5355), control1: p(r, 0.7738, 0.5503), control2: p(r, 0.7861, 0.5385))
        path.addCurve(to: p(r, 0.8430, 0.5562), control1: p(r, 0.8129, 0.5340), control2: p(r, 0.8293, 0.5370))
        path.addCurve(to: p(r, 0.8821, 0.6509), control1: p(r, 0.8566, 0.5754), control2: p(r, 0.8726, 0.6139))
        path.addCurve(to: p(r, 0.9017, 0.7840), control1: p(r, 0.8921, 0.6893), control2: p(r, 0.8976, 0.7322))
        path.addCurve(to: p(r, 0.9049, 0.9615), control1: p(r, 0.9053, 0.8358), control2: p(r, 0.8976, 0.9334))
        path.addCurve(to: p(r, 0.9454, 0.9527), control1: p(r, 0.9122, 0.9896), control2: p(r, 0.9345, 0.9601))
        path.addCurve(to: p(r, 0.9718, 0.9172), control1: p(r, 0.9568, 0.9453), control2: p(r, 0.9663, 0.9393))
        path.addCurve(to: p(r, 0.9791, 0.8254), control1: p(r, 0.9772, 0.8964), control2: p(r, 0.9759, 0.8476))
        path.addCurve(to: p(r, 0.9909, 0.7811), control1: p(r, 0.9827, 0.8033), control2: p(r, 0.9886, 0.8180))
        path.addCurve(to: p(r, 0.9932, 0.6050), control1: p(r, 0.9936, 0.7456), control2: p(r, 1.0000, 0.6494))
        path.addCurve(to: p(r, 0.9508, 0.5207), control1: p(r, 0.9863, 0.5621), control2: p(r, 0.9663, 0.5444))
        path.addCurve(to: p(r, 0.8999, 0.4615), control1: p(r, 0.9354, 0.4956), control2: p(r, 0.9335, 0.4882))
        path.addCurve(to: p(r, 0.7487, 0.3536), control1: p(r, 0.8662, 0.4334), control2: p(r, 0.7947, 0.4083))
        path.addCurve(to: p(r, 0.6227, 0.1287), control1: p(r, 0.7023, 0.2973), control2: p(r, 0.6604, 0.1834))
        path.addCurve(to: p(r, 0.5230, 0.0222), control1: p(r, 0.5849, 0.0725), control2: p(r, 0.5589, 0.0429))
        path.addCurve(to: p(r, 0.4056, 0.0044), control1: p(r, 0.4866, 0.0015), control2: p(r, 0.4456, 0.0000))
        path.addCurve(to: p(r, 0.2822, 0.0518), control1: p(r, 0.3650, 0.0089), control2: p(r, 0.3227, 0.0281))
        path.addCurve(to: p(r, 0.1625, 0.1435), control1: p(r, 0.2417, 0.0740), control2: p(r, 0.2057, 0.1036))
        path.addCurve(to: p(r, 0.0218, 0.2959), control1: p(r, 0.1193, 0.1849), control2: p(r, 0.0437, 0.2396))
        path.closeSubpath()
        return path
    }
}

/// The two wheels, under the arches.
struct CarWheels: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let rad = r.width * 0.078
        for cx in [0.207, 0.802] {
            path.addEllipse(in: CGRect(x: r.minX + r.width * cx - rad, y: r.minY + r.height * 0.80 - rad, width: rad * 2, height: rad * 2))
        }
        return path
    }
}

/// Filled car: white body, grey wheels. Width sets the size (the car is 3.25 : 1).
struct CarGlyph: View {
    var width: CGFloat = 22
    var body: some View {
        ZStack {
            CarSilhouette().fill(.primary)
            CarWheels().fill(.primary.opacity(0.5))
        }
        .frame(width: width, height: width / 3.25 * 1.12)
        .accessibilityLabel("Car")
    }
}

// MARK: A · battery gauge (F while charging) · J1 inline

struct CarBatteryView: View {
    let entry: CarEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let c = entry.car
        switch family {
        case .accessoryInline:
            if let c {
                if c.charging, let full = c.fullAt {
                    Label("\(c.battery)% · full \(full.formatted(date: .omitted, time: .shortened))", systemImage: "bolt.fill")
                } else {
                    Label { Text("\(c.battery)% · \(c.rangeMiles) mi") } icon: { Image("hd-car").renderingMode(.template) }
                }
            } else {
                Text("Car · open Hyperday")
            }
        default:
            gauge(c)
        }
    }

    @ViewBuilder
    private func gauge(_ c: CarSnapshot?) -> some View {
        if let c, c.charging {
            Gauge(value: Double(c.battery), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: 0) {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                    Text("\(c.battery)").font(.system(size: 15, weight: .bold))
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            Gauge(value: Double(c?.battery ?? 0), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: 1) {
                    CarGlyph(width: 20)
                    Text(c.map { "\($0.battery)" } ?? "–").font(.system(size: 15, weight: .bold))
                }
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}

// MARK: I · battery gauge + lock badge

struct CarBatteryLockView: View {
    let entry: CarEntry
    var body: some View {
        let c = entry.car
        ZStack(alignment: .bottomTrailing) {
            CarBatteryView(entry: entry)
            if let c {
                Image(systemName: c.locked == false ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.black))
                    .overlay(Circle().stroke(.primary.opacity(0.4), lineWidth: 1))
                    .accessibilityLabel(c.locked == false ? "Unlocked" : "Locked")
            }
        }
    }
}

// MARK: M · Home Screen small list

struct CarListView: View {
    let entry: CarEntry
    var body: some View {
        if let c = entry.car {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(c.name).font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(ago(c.updatedAt, entry.date)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                }
                row(AnyView(CarGlyph(width: 20)), c.charging ? "\(c.battery)% · charging" : "\(c.battery)% · \(c.rangeMiles) mi")
                row(AnyView(Image(systemName: c.locked == false ? "lock.open.fill" : "lock.fill").font(.system(size: 13, weight: .semibold))),
                    c.locked == false ? "Unlocked" : "Locked", tint: c.locked == false ? Color(hex: "#FF453A") : nil)
                if let f = c.insideF {
                    row(AnyView(Image(systemName: "thermometer.medium").font(.system(size: 13, weight: .semibold))), "\(f)° inside")
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                CarGlyph(width: 34).foregroundStyle(.white)
                Text("Open Hyperday to read your car").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func row(_ icon: AnyView, _ text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 8) {
            icon.frame(width: 22)
            Text(text).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint ?? .white)
    }

    private func ago(_ d: Date, _ now: Date) -> String {
        let m = max(0, Int(now.timeIntervalSince(d) / 60))
        return m < 1 ? "now" : (m < 60 ? "\(m)m ago" : "\(m / 60)h ago")
    }
}

// MARK: Widgets

struct HyperdayCarBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.batteryKind, provider: CarProvider()) {
            CarBatteryView(entry: $0)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Car battery").description("Battery gauge with your car, or a line above the clock.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct HyperdayCarBatteryLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.batteryLockKind, provider: CarProvider()) {
            CarBatteryLockView(entry: $0)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Car battery + lock").description("Battery gauge with a lock badge.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct HyperdayCarListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarShared.listKind, provider: CarProvider()) {
            CarListView(entry: $0)
                .containerBackground(for: .widget) { Color(red: 0.11, green: 0.114, blue: 0.13) }
        }
        .configurationDisplayName("Car").description("Battery, range, lock and inside temperature.")
        .supportedFamilies([.systemSmall])
    }
}
