import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// #5 Speak-to-plan and #6 Evening story, using Apple Intelligence's on-device model (iOS 26+).
/// Nothing leaves the iPhone. On older iOS or without Apple Intelligence these features hide themselves.
struct PlanProposal: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var start: Date
    var minutes: Int
    var categoryID: String?
    var include = true
}

enum AIPlanner {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var unavailableReason: String {
        "Needs Apple Intelligence on iOS 26 or later. Turn it on in Settings › Apple Intelligence & Siri."
    }

    /// Turn "gym after work, call mom at lunch, finish the project doc (90 min)" into blocks in today's free time.
    @MainActor
    static func plan(_ text: String, now: Date = .now) async throws -> [PlanProposal] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let ids = CategoryStore.shared.categories.map(\.id).joined(separator: ", ")
            let session = LanguageModelSession(instructions: """
                You turn a person's to-do list into calendar blocks. Split it into separate tasks. \
                Keep titles short. Use only these category ids: \(ids).
                """)
            let response = try await session.respond(to: text, generating: Draft.self)
            return fit(response.content.items, now: now)
        }
        #endif
        return []
    }

    /// Three sentences about the day for the Close the day sheet.
    @MainActor
    static func story(done: [String], notDone: [String], reality: [String]) async throws -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                Write a warm, plain, honest 3-sentence recap of the person's day in second person ("you"). \
                No emoji, no headings, no advice. Mention what went well and what slipped.
                """)
            let prompt = """
                Finished: \(done.isEmpty ? "nothing" : done.joined(separator: "; ")).
                Not finished: \(notDone.isEmpty ? "nothing" : notDone.joined(separator: "; ")).
                What actually happened: \(reality.isEmpty ? "no data" : reality.joined(separator: "; ")).
                """
            return try await session.respond(to: prompt).content
        }
        #endif
        return nil
    }

    // MARK: Fit into free time

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @MainActor
    private static func fit(_ items: [DraftItem], now: Date) -> [PlanProposal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var busy = LiveActivityManager.shared.todayBlocks(now: now).map { DateInterval(start: $0.start, end: max($0.end, $0.start)) }
        let dayEnd = today.addingTimeInterval(22 * 3600)
        let earliest = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300)
        var out: [PlanProposal] = []
        let validIDs = Set(CategoryStore.shared.categories.map(\.id))

        for item in items {
            let minutes = min(max(item.minutes, 10), 240)
            let length = TimeInterval(minutes * 60)
            var wanted = earliest
            let parts = item.start.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, let t = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: today), t > earliest {
                wanted = t
            }
            // First free slot at or after the wanted time.
            var slot = wanted
            for b in busy.sorted(by: { $0.start < $1.start }) where b.end > slot {
                if b.start >= slot.addingTimeInterval(length) { break }
                slot = max(slot, b.end)
            }
            if slot.addingTimeInterval(length) > dayEnd {
                // No room today: tomorrow, first gap after 9 AM.
                slot = (cal.date(byAdding: .day, value: 1, to: today) ?? today).addingTimeInterval(9 * 3600)
            }
            busy.append(DateInterval(start: slot, duration: length))
            out.append(PlanProposal(title: item.title, start: slot, minutes: minutes,
                                    categoryID: validIDs.contains(item.category) ? item.category : nil))
        }
        return out.sorted { $0.start < $1.start }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct DraftItem {
    @Guide(description: "Short task title, like 'Call Mom' or 'Finish project doc'")
    var title: String
    @Guide(description: "How long it takes in minutes, between 10 and 240. Use 30 if not said.")
    var minutes: Int
    @Guide(description: "Start time as 24-hour HH:mm only if the person gave a time or part of the day (morning 09:00, lunch 12:30, afternoon 14:00, after work 18:00, evening 19:30). Otherwise an empty string.")
    var start: String
    @Guide(description: "The best matching category id from the list in the instructions")
    var category: String
}

@available(iOS 26.0, *)
@Generable
struct Draft {
    @Guide(description: "Each separate task the person mentioned, in order")
    var items: [DraftItem]
}
#endif
