import AppIntents
import Foundation

/// "Hey Siri, add a block in Hyperday" -> Siri asks what + how long.
/// Also usable from Shortcuts and the Action Button.
/// LiveActivityIntent (not plain AppIntent) so it may start the Live Activity from the background.
struct AddBlockIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add Block"
    static var description = IntentDescription("Plan a block of time in your day.")

    @Parameter(title: "What", requestValueDialog: "What are you going to do?")
    var what: String

    @Parameter(title: "Minutes", default: 60, requestValueDialog: "For how many minutes?")
    var minutes: Int

    @Parameter(title: "Start", description: "Leave empty to start now.")
    var start: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$what) for \(\.$minutes) minutes") {
            \.$start
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let begin = start ?? .now
        guard BlockStore.shared.add(title: what, start: begin, minutes: minutes) != nil else {
            return .result(dialog: "I couldn't add that. Try a name and a length.")
        }
        await LiveActivityManager.shared.refresh()
        return .result(dialog: "Added \(what) at \(begin.shortTime).")
    }
}

// MARK: - Siri: What's next / Start my day / I'm done / Start Deep Work

struct WhatsNextIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next"
    static var description = IntentDescription("Hear what you're doing now and what comes next.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let snap = LiveActivityManager.shared.snapshot(now: now)
        var parts: [String] = []
        if let c = snap.current {
            parts.append("You're in \(c.title) until \(c.end.shortTime).")
        }
        if let n = snap.next {
            let mins = Int((n.start.timeIntervalSince(now) / 60).rounded())
            let when = mins < 60 ? "in \(mins) minute\(mins == 1 ? "" : "s")" : "at \(n.start.shortTime)"
            parts.append("Next is \(n.title) \(when).")
        }
        if parts.isEmpty {
            parts.append(snap.all.isEmpty ? "Nothing is planned today." : "Nothing else is planned today.")
        }
        let text = parts.joined(separator: " ")
        return .result(dialog: "\(text)")
    }
}

/// LiveActivityIntent so it can start the Live Activity from the background (Action Button, automations).
struct StartMyDayIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start My Day"
    static var description = IntentDescription("Put today's plan live on your Lock Screen.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await LiveActivityManager.shared.start()
        let snap = LiveActivityManager.shared.snapshot()
        if let c = snap.current {
            return .result(dialog: "Your day is live. You're in \(c.title).")
        }
        if let n = snap.next {
            return .result(dialog: "Your day is live. First up: \(n.title) at \(n.start.shortTime).")
        }
        return .result(dialog: "Your day is live.")
    }
}

struct ImDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "I'm Done"
    static var description = IntentDescription("Finish the current block early.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snap = LiveActivityManager.shared.snapshot()
        guard let c = snap.current else {
            return .result(dialog: "Nothing is running right now.")
        }
        BlockStore.shared.finish(blockID: c.id, at: .now)
        await LiveActivityManager.shared.refresh()
        let next = LiveActivityManager.shared.snapshot().next
        if let next {
            return .result(dialog: "Done with \(c.title). Next is \(next.title) at \(next.start.shortTime).")
        }
        return .result(dialog: "Done with \(c.title).")
    }
}

/// Used by the Focus shortcut: starts a Deep Work block now and goes live.
/// Pair it in Shortcuts with "Set Focus" (apps can't turn Focus on themselves).
struct StartDeepWorkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Deep Work"
    static var description = IntentDescription("Start a Deep Work block now and show it live.")

    @Parameter(title: "Minutes", default: 90)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let mins = max(15, minutes)
        BlockStore.shared.add(title: "Deep Work", start: .now, minutes: mins, categoryID: "deepwork")
        await LiveActivityManager.shared.start()
        let end = Date.now.addingTimeInterval(TimeInterval(mins * 60))
        return .result(dialog: "Deep Work until \(end.shortTime).")
    }
}

struct DayLiveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "What's next on \(.applicationName)"
            ],
            shortTitle: "What's Next",
            systemImageName: "arrow.forward.circle"
        )
        AppShortcut(
            intent: StartMyDayIntent(),
            phrases: [
                "Start my day in \(.applicationName)",
                "Start my day with \(.applicationName)"
            ],
            shortTitle: "Start My Day",
            systemImageName: "sunrise"
        )
        AppShortcut(
            intent: ImDoneIntent(),
            phrases: [
                "I'm done in \(.applicationName)",
                "Finish my block in \(.applicationName)"
            ],
            shortTitle: "I'm Done",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: StartDeepWorkIntent(),
            phrases: [
                "Start deep work in \(.applicationName)"
            ],
            shortTitle: "Start Deep Work",
            systemImageName: "target"
        )
        AppShortcut(
            intent: ImDrivingIntent(),
            phrases: ["I'm driving in \(.applicationName)"],
            shortTitle: "I'm Driving",
            systemImageName: "car"
        )
        AppShortcut(
            intent: ArrivedIntent(),
            phrases: ["I arrived in \(.applicationName)"],
            shortTitle: "Arrived",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: AddBlockIntent(),
            phrases: [
                "Add a block in \(.applicationName)",
                "Plan something in \(.applicationName)"
            ],
            shortTitle: "Add Block",
            systemImageName: "plus.circle"
        )
    }
}
