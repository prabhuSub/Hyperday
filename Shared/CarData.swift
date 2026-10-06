import Foundation

/// v30: the car as the app last read it. Widgets only ever show this (they never call Tesla themselves).
struct CarSnapshot: Codable, Equatable {
    var name: String
    var battery: Int                 // %
    var rangeMiles: Int
    var chargeLimit: Int?            // %
    var charging: Bool
    var chargeKW: Double?
    var fullAt: Date?
    var locked: Bool?
    var sentry: Bool?
    var insideF: Int?
    var place: String?               // "Home"
    var updatedAt: Date
    var isSample: Bool = false
    // From your day plan
    var todayMiles: Int?
    var nextTripTitle: String?
    var leaveBy: Date?
    var drivesToday: Int?

    var enoughForToday: Bool? { todayMiles.map { rangeMiles >= $0 + 15 } }

    static func sample(now: Date = .now) -> CarSnapshot {
        CarSnapshot(name: "Quick Silver", battery: 78, rangeMiles: 241, chargeLimit: 80, charging: false,
                    chargeKW: nil, fullAt: nil, locked: true, sentry: true, insideF: 64, place: "Home",
                    updatedAt: now.addingTimeInterval(-12 * 60), isSample: true,
                    todayMiles: 64, nextTripTitle: "Office", leaveBy: now.addingTimeInterval(42 * 60), drivesToday: 2)
    }

    static func sampleCharging(now: Date = .now) -> CarSnapshot {
        var s = sample(now: now)
        s.battery = 62; s.rangeMiles = 188; s.charging = true; s.chargeKW = 11
        s.fullAt = now.addingTimeInterval(2.5 * 3600); s.insideF = 71; s.sentry = false
        return s
    }
}

enum CarShared {
    static let glanceKind = "HyperdayCarGlance"
    static let readyKind = "HyperdayCarReady"
    static let dayKind = "HyperdayCarDay"
    static let chargeKind = "HyperdayCarCharge"
    static let hubKind = "HyperdayCarHub"
    static let lockKind = "HyperdayCarLock"
    static let lockReadyKind = "HyperdayCarLockReady"
    static let batteryKind = "HyperdayCarBattery"          // v38 A + J1
    static let batteryLockKind = "HyperdayCarBatteryLock"  // v38 I
    static let listKind = "HyperdayCarList"                // v38 M
    static let allKinds = [glanceKind, readyKind, dayKind, chargeKind, hubKind, lockKind, lockReadyKind,
                           batteryKind, batteryLockKind, listKind]

    static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroup)?
            .appendingPathComponent("widget-car.json")
    }

    @discardableResult
    static func save(_ car: CarSnapshot?) -> Bool {
        guard let url else { return false }
        guard let car else { try? FileManager.default.removeItem(at: url); return true }
        guard let data = try? JSONEncoder().encode(car) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func load() -> CarSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CarSnapshot.self, from: data)
    }
}
