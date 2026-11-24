import SwiftUI
import WidgetKit

// v64: JobTrail on the Home Screen and Lock Screen. The widget reads JobTrail itself over Tailscale
// (every ~15 min, iOS's budget) and the app pushes fresh data whenever it's open.

struct MacsEntry: TimelineEntry {
    let date: Date
    let snap: JTSnapshot
}

struct MacsProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacsEntry { MacsEntry(date: .now, snap: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (MacsEntry) -> Void) {
        let s = JTStore.load()
        completion(MacsEntry(date: .now, snap: (s?.macs.isEmpty == false ? s : nil) ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacsEntry>) -> Void) {
        Task {
            let snap = await JTStore.refresh()
            let now = Date.now
            completion(Timeline(entries: [MacsEntry(date: now, snap: snap)],
                                policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }
}

struct HyperdayMacsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: JTStore.kind, provider: MacsProvider()) { e in
            MacsWidgetView(entry: e)
        }
        .configurationDisplayName("Macs · JobTrail")
        .description("Your MacBook Pro and Mac mini: GPU and memory graphs, running jobs with live timers, the last 24 hours.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MacsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacsEntry
    var body: some View {
        Group {
            switch family {
            case .systemLarge: MacsLargeView(snap: entry.snap, now: entry.date)
            case .systemMedium: MacsMediumView(snap: entry.snap, now: entry.date)
            default: MacsSmallView(snap: entry.snap, now: entry.date)
            }
        }
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { InstrumentBackground() }
        .overlay {
            if entry.snap.macs.contains(where: { $0.running > 0 }) {
                ContainerRelativeShape().strokeBorder(HDTone.amber.opacity(0.45), lineWidth: 1).padding(-12)
            }
        }
        .widgetURL(URL(string: "hyperday://jobtrail"))
    }
}

struct HyperdayMacsLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: JTStore.lockKind, provider: MacsProvider()) { e in
            MacsLockView(snap: e.snap)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(URL(string: "hyperday://jobtrail"))
        }
        .configurationDisplayName("Macs")
        .description("Both Macs: running jobs, GPU and memory.")
        .supportedFamilies([.accessoryRectangular])
    }
}
