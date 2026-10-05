import Combine
import CoreLocation
import Foundation

/// #3 Reality line: what actually happened today, recorded on the iPhone only.
/// Sources: Location (arrive/leave Home, Office, Gym), your car (Shortcuts automation), Health (workouts).
struct RealityEvent: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case arrived, departed, driveStart, driveEnd }
    var id = UUID().uuidString
    var kind: Kind
    var place: String?     // "Home", "Office", "Gym"
    var date: Date
}

struct Place: Codable, Hashable, Identifiable {
    var id: String          // "home", "office", "gym"
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double = 150

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// A stretch of the real day for the "What happened" lane.
struct RealitySegment: Identifiable, Hashable {
    enum Kind: Hashable { case drive, place, workout }
    var id: String { "\(kind)-\(start.timeIntervalSince1970)" }
    var kind: Kind
    var label: String
    var start: Date
    var end: Date
}

@MainActor
final class RealityStore: ObservableObject {
    static let shared = RealityStore()

    @Published private(set) var events: [RealityEvent] = []
    @Published private(set) var places: [Place] = []
    @Published var workouts: [DateInterval] = []        // today's, from Health
    @Published var commuteSamples: [Int] = []           // minutes, last 10 home → office trips

    private struct Snapshot: Codable {
        var events: [RealityEvent]
        var places: [Place]
        var commuteSamples: [Int]?
    }

    private let fileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("daylive-reality.json")
    }()

    private init() { load() }

    // MARK: Places

    func place(_ id: String) -> Place? { places.first { $0.id == id } }

    func setPlace(_ id: String, name: String, at location: CLLocation) {
        places.removeAll { $0.id == id }
        places.append(Place(id: id, name: name, latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude))
        save()
        LocationService.shared.monitor(places)
    }

    // MARK: Events

    func record(_ kind: RealityEvent.Kind, place: String? = nil, at date: Date = .now) {
        events.append(RealityEvent(kind: kind, place: place, date: date))
        if kind == .arrived, place == "Office" { learnCommute(arrivedAt: date) }
        prune()
        save()
    }

    /// Driving now: the car connected less than 3 hours ago and hasn't disconnected.
    var driveStartedAt: Date? {
        guard let last = events.last(where: { $0.kind == .driveStart || $0.kind == .driveEnd }),
              last.kind == .driveStart, Date.now.timeIntervalSince(last.date) < 3 * 3600 else { return nil }
        return last.date
    }

    /// Home → Office trips teach the commute used by Tomorrow pre-flight.
    private func learnCommute(arrivedAt: Date) {
        guard let left = events.last(where: { $0.kind == .departed && $0.place == "Home" && $0.date < arrivedAt }),
              arrivedAt.timeIntervalSince(left.date) < 3 * 3600 else { return }
        let minutes = Int((arrivedAt.timeIntervalSince(left.date) / 60).rounded())
        commuteSamples = Array((commuteSamples + [minutes]).suffix(10))
        DayCloseSettings.learnedCommuteMinutes = commuteSamples.reduce(0, +) / max(commuteSamples.count, 1)
    }

    func segments(on day: Date) -> [RealitySegment] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? day
        let now = Date.now
        let todays = events.filter { $0.date >= dayStart && $0.date < dayEnd }.sorted { $0.date < $1.date }
        var out: [RealitySegment] = []
        var driveFrom: Date?
        var atPlace: (String, Date)?
        for e in todays {
            switch e.kind {
            case .driveStart: driveFrom = e.date
            case .driveEnd:
                if let f = driveFrom { out.append(.init(kind: .drive, label: "Drive", start: f, end: e.date)) }
                driveFrom = nil
            case .arrived: atPlace = (e.place ?? "Place", e.date)
            case .departed:
                if let ap = atPlace, ap.0 == e.place {
                    out.append(.init(kind: .place, label: "At \(ap.0.lowercased())", start: ap.1, end: e.date))
                }
                atPlace = nil
            }
        }
        let openEnd = min(now, dayEnd)
        if let f = driveFrom, f < openEnd { out.append(.init(kind: .drive, label: "Driving", start: f, end: openEnd)) }
        if let ap = atPlace, ap.1 < openEnd, ap.0 != "Home" {
            out.append(.init(kind: .place, label: "At \(ap.0.lowercased())", start: ap.1, end: openEnd))
        }
        for w in workouts where w.start >= dayStart && w.start < dayEnd {
            out.append(.init(kind: .workout, label: "Workout", start: w.start, end: w.end))
        }
        // Drive labels get their length: "Drive 28m"
        return out.map { s in
            var s = s
            if s.kind == .drive { s.label = "\(s.label) \(s.end.timeIntervalSince(s.start).hoursMinutes)" }
            return s
        }.sorted { $0.start < $1.start }
    }

    // MARK: Health

    /// Reads today's workouts and ticks Fitness blocks they overlap ("Workouts tick Fitness blocks").
    func refreshWorkouts() async {
        workouts = await HealthReality.workouts(on: .now)
        guard (UserDefaults.standard.object(forKey: "realityTickWorkouts") as? Bool) ?? true else { return }
        let blocks = LiveActivityManager.shared.allTodayBlocks()
        let done = Set(HistoryStore.shared.entries(on: .now).filter(\.done).map(\.id))
        for b in blocks where !done.contains(b.id)
            && CategoryStore.shared.categories(for: b).contains(where: { $0.id == "fitness" }) {
            if let w = workouts.first(where: { $0.start < b.end && $0.end > b.start }) {
                BlockStore.shared.finish(blockID: b.id, at: min(b.end, max(w.end, b.start.addingTimeInterval(60))))
            }
        }
    }

    // MARK: Persistence

    private func prune() {
        let cutoff = Date.now.addingTimeInterval(-60 * 86_400)
        events.removeAll { $0.date < cutoff }
    }

    private var loadBlocked = false

    func retryLoadIfNeeded() { if loadBlocked { load() } }
    func reloadFromDisk() { load() }   // after a restore

    private func load() {
        let s: Snapshot
        switch SafeFile.load(Snapshot.self, from: fileURL) {
        case .loaded(let x): s = x; loadBlocked = false
        case .missing: loadBlocked = false; return
        case .unavailable, .unreadable: loadBlocked = true; return
        }
        events = s.events
        places = s.places
        commuteSamples = s.commuteSamples ?? []
    }

    private func save() {
        guard !loadBlocked else { return }
        let s = Snapshot(events: events, places: places, commuteSamples: commuteSamples)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
