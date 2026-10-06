import Foundation

/// v31: counts Tesla calls per month and refuses past a cap, so the bill stays under Tesla's $10 monthly credit.
/// Prices: data $0.002 · command $0.001 · wake $0.02.
enum TeslaMeter {
    enum Kind: String, CaseIterable { case data, command, wake }

    static func cap(_ k: Kind) -> Int {
        switch k { case .data: return 2500; case .command: return 600; case .wake: return 60 }   // ≈ $5 + $0.60 + $1.20
    }
    static func price(_ k: Kind) -> Double {
        switch k { case .data: return 0.002; case .command: return 0.001; case .wake: return 0.02 }
    }
    private static var month: String {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }
    static func used(_ k: Kind) -> Int { UserDefaults.standard.integer(forKey: "tesla.\(month).\(k.rawValue)") }
    static var dollars: Double { Kind.allCases.reduce(0) { $0 + Double(used($1)) * price($1) } }

    static func spend(_ k: Kind) throws {
        guard used(k) < cap(k) else { throw TeslaError.monthlyCap(k.rawValue) }
        UserDefaults.standard.set(used(k) + 1, forKey: "tesla.\(month).\(k.rawValue)")
    }
}

struct TeslaVehicle {
    let vin: String
    let name: String
    let state: String       // "online", "asleep", "offline"
}

/// Read-only Fleet API calls (commands come later, signed with the paired key).
enum TeslaAPI {
    static let base = URL(string: TeslaAuth.audience)!

    private static func call(_ path: String, method: String = "GET", kind: TeslaMeter.Kind,
                             query: [URLQueryItem] = [], retried: Bool = false) async throws -> [String: Any] {
        try TeslaMeter.spend(kind)
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.timeoutInterval = 20
        let token = try await TeslaAuth.shared.accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject ?? [:]
        switch status {
        case 200: return json
        case 401 where !retried:
            TeslaKeychain.set(nil, for: "expiry")   // force a refresh, then try once more
            return try await call(path, method: method, kind: kind, query: query, retried: true)
        case 408: throw TeslaError.asleep
        default: throw TeslaError.http(status, (json["error"] as? String) ?? "request failed")
        }
    }

    static func vehicles() async throws -> [TeslaVehicle] {
        let j = try await call("api/1/vehicles", kind: .data)
        let list = j["response"] as? [JSONObject] ?? []
        return list.compactMap { v in
            guard let vin = v["vin"] as? String else { return nil }
            return TeslaVehicle(vin: vin, name: (v["display_name"] as? String) ?? "My car", state: (v["state"] as? String) ?? "unknown")
        }
    }

    static func vehicleData(_ vin: String) async throws -> [String: Any] {
        let j = try await call("api/1/vehicles/\(vin)/vehicle_data", kind: .data,
                               query: [URLQueryItem(name: "endpoints",
                                                    value: "charge_state;climate_state;drive_state;location_data;vehicle_state")])
        return j["response"] as? JSONObject ?? [:]
    }

    static func wake(_ vin: String) async throws {
        _ = try await call("api/1/vehicles/\(vin)/wake_up", method: "POST", kind: .wake)
    }
}

/// JSON object from Tesla.
typealias JSONObject = [String: Any]
