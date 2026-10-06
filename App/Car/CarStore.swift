import CoreLocation
import Foundation
import SwiftUI
import WidgetKit

/// v31: the car for the Car tab and the widgets. Reads Tesla only when you open the app (at most every
/// 10 minutes) or pull to refresh. Never wakes the car unless you ask.
@MainActor
final class CarStore: ObservableObject {
    static let shared = CarStore()

    @Published private(set) var car: CarSnapshot?
    @Published private(set) var signedIn = false
    @Published private(set) var busy = false
    @Published private(set) var asleep = false
    @Published var message: String?
    /// Drawn on the 3D car's plate; stays on this iPhone.
    @Published var plate = UserDefaults.standard.string(forKey: "carPlate") ?? "" {
        didSet { UserDefaults.standard.set(plate, forKey: "carPlate") }
    }

    private var lastRefresh: Date?
    private var running: Task<Void, Never>?

    /// Starts a read that the screen can't cancel (a cancelled screen task was showing "cancelled").
    @discardableResult
    func start(force: Bool = false, wake: Bool = false) -> Task<Void, Never> {
        if let running { return running }
        let t = Task { [weak self] in
            await self?.refresh(force: force, wake: wake)
            self?.running = nil
        }
        running = t
        return t
    }

    init() {
        car = CarShared.load()
        signedIn = TeslaAuth.shared.isSignedIn
    }

    var hasClientID: Bool { TeslaAuth.shared.clientID != nil }

    func connect() async {
        message = nil
        do {
            try await TeslaAuth.shared.signIn()
            signedIn = true
            await running?.value                          // let any read already under way finish
            await start(force: true, wake: true).value   // once, so your real numbers show right away (2¢)
        } catch {
            message = error.localizedDescription
        }
    }

    func disconnect() {
        TeslaAuth.shared.signOut()
        signedIn = false
        if car?.isSample != true { publish(nil) }
    }

    func setSample(_ on: Bool) {
        publish(on ? .sample() : nil)
        if !on, signedIn { Task { await refresh(force: true) } }
    }

    /// Cheap check first (vehicle list); full data only when the car is already awake.
    func refresh(force: Bool = false, wake: Bool = false) async {
        guard signedIn, !busy else { return }
        if !force, let last = lastRefresh, Date.now.timeIntervalSince(last) < 600 { return }
        busy = true
        defer { busy = false; lastRefresh = .now }
        do {
            guard let v = try await TeslaAPI.vehicles().first else { message = "No car on this Tesla account."; return }
            var state = v.state
            if state != "online", wake {
                try await TeslaAPI.wake(v.vin)
                for _ in 0..<4 {                       // up to ~30 s
                    try await Task.sleep(for: .seconds(8))
                    state = try await TeslaAPI.vehicles().first(where: { $0.vin == v.vin })?.state ?? state
                    if state == "online" { break }
                }
            }
            guard state == "online" else {
                asleep = true
                if car?.isSample == true { publish(nil) }   // never show sample numbers as your car
                message = "Asleep · showing the last reading. Pull down to wake it (costs 2¢)."
                return
            }
            asleep = false
            let data = try await TeslaAPI.vehicleData(v.vin)
            var snap = Self.snapshot(from: data, name: v.name, previous: car)
            snap.place = await placeName(data)
            publish(snap)
            message = nil
        } catch TeslaError.asleep {
            asleep = true
            message = TeslaError.asleep.localizedDescription
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            message = error.localizedDescription
        }
    }

    private func publish(_ snap: CarSnapshot?) {
        car = snap
        CarShared.save(snap)
        for k in CarShared.allKinds { WidgetCenter.shared.reloadTimelines(ofKind: k) }
    }

    // MARK: Parsing

    static func snapshot(from d: [String: Any], name: String, previous: CarSnapshot?) -> CarSnapshot {
        let charge = d["charge_state"] as? JSONObject ?? [:]
        let climate = d["climate_state"] as? JSONObject ?? [:]
        let vs = d["vehicle_state"] as? JSONObject ?? [:]
        func num(_ o: Any?) -> Double? { (o as? NSNumber)?.doubleValue }
        let charging = (charge["charging_state"] as? String) == "Charging"
        let hoursToFull = num(charge["time_to_full_charge"]) ?? 0
        let insideC = num(climate["inside_temp"])
        return CarSnapshot(
            name: name,
            battery: Int(num(charge["battery_level"]) ?? Double(previous?.battery ?? 0)),
            rangeMiles: Int((num(charge["battery_range"]) ?? Double(previous?.rangeMiles ?? 0)).rounded()),
            chargeLimit: num(charge["charge_limit_soc"]).map { Int($0) },
            charging: charging,
            chargeKW: num(charge["charger_power"]),
            fullAt: charging && hoursToFull > 0 ? Date.now.addingTimeInterval(hoursToFull * 3600) : nil,
            locked: vs["locked"] as? Bool,
            sentry: vs["sentry_mode"] as? Bool,
            insideF: insideC.map { Int(($0 * 9 / 5 + 32).rounded()) },
            place: previous?.place,
            updatedAt: .now,
            isSample: false,
            todayMiles: previous?.todayMiles,
            nextTripTitle: previous?.nextTripTitle,
            leaveBy: previous?.leaveBy,
            drivesToday: previous?.drivesToday)
    }

    /// "Home" / "Office" from your saved places, else the street name.
    private func placeName(_ d: [String: Any]) async -> String? {
        let drive = d["drive_state"] as? JSONObject ?? [:]
        guard let lat = (drive["latitude"] as? NSNumber)?.doubleValue,
              let lon = (drive["longitude"] as? NSNumber)?.doubleValue else { return car?.place }
        let here = CLLocation(latitude: lat, longitude: lon)
        if let p = RealityStore.shared.places.first(where: {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here) < 150
        }) { return p.name }
        let marks = try? await CLGeocoder().reverseGeocodeLocation(here)
        return marks?.first.flatMap { $0.thoroughfare ?? $0.locality }
    }
}
