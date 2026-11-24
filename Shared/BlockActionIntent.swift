import AppIntents
import Foundation

/// The Done / Start next button on the Live Activity.
/// LiveActivityIntent runs in the APP's process (iOS wakes it in the background),
/// so the widget extension only needs the type to exist; the work is app-only.
struct BlockActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Done / Next"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Block ID")
    var blockID: String

    @Parameter(title: "Action")
    var actionRaw: String

    init() {}

    init(blockID: String, action: BlockAction) {
        self.blockID = blockID
        self.actionRaw = action.rawValue
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let action = BlockAction(rawValue: actionRaw) ?? .done
        let id = blockID
        await MainActor.run {
            switch action {
            case .done:      BlockStore.shared.finish(blockID: id, at: .now)
            case .startNext: BlockStore.shared.start(blockID: id, at: .now)
            case .checkStep: BlockStore.shared.checkNextStep(blockID: id)
            }
        }
        await LiveActivityManager.shared.refresh()
        #endif
        return .result()
    }
}

/// v20: Pause / Resume on the Live Activity (your own planned blocks). Pausing moves the end later.
struct PauseBlockIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause / Resume"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Block ID")
    var blockID: String

    @Parameter(title: "Pause")
    var pause: Bool

    init() {}

    init(blockID: String, pause: Bool) {
        self.blockID = blockID
        self.pause = pause
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let id = blockID, p = pause
        await MainActor.run {
            if p { BlockStore.shared.pause(blockID: id, at: .now) } else { BlockStore.shared.resume(blockID: id, at: .now) }
        }
        await LiveActivityManager.shared.refresh()
        #endif
        return .result()
    }
}

/// v68: ↻ on the Live Activity: read JobTrail now and redraw the card (runs in the app's process,
/// iOS wakes Hyperday in the background; no need to open it).
struct RefreshMacsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Refresh Macs"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await JobTrailLive.shared.poll()
        await LiveActivityManager.shared.refresh()
        #endif
        return .result()
    }
}
