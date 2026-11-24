#if DEBUG
import SwiftUI

/// v61 debug only (`-hdLAPreview YES`): the Lock Screen card at its real 160 pt cap, with sample Macs,
/// for every preview state. Used to check nothing is cut off.
struct LAPreviewScreen: View {
    private static var doneState: DayActivityAttributes.ContentState {
        var d = DayActivityAttributes.ContentState(label: "Nothing else today", title: "Day complete", also: nil, source: .free,
            segments: [], dayProgress: 1, currentEnd: nil, actionBlockID: nil, action: nil, stepsDone: nil, stepsTotal: nil,
            accentHex: nil, alsoIsStep: nil, freeStart: nil, nextStart: nil, nextTitle: nil, overSince: nil, iconName: nil)
        d.doneCount = 7; d.totalCount = 7; d.macs = boardMacs
        return d
    }
    private static let boardMacs: [MacLive] = [
        MacLive(id: "local", name: "MacBook Pro", desktop: false, online: true, running: 3, waiting: 2, gpu: 0, mem: 42,
                top: "S01_run2.sh", topSince: .now.addingTimeInterval(-33600), topWaiting: false, battery: 71, charging: false,
                gpuHist: [3, 5, 2, 8, 12, 6, 4, 2, 0, 1, 3, 0, 0, 2, 5, 3, 1, 0, 0, 0],
                jobs: [MacJob(label: "S01_run2.sh", since: .now.addingTimeInterval(-33600), waiting: false),
                       MacJob(label: "ssh mini", since: .now.addingTimeInterval(-30100), waiting: false),
                       MacJob(label: "watch · grep", since: .now.addingTimeInterval(-9000), waiting: true)]),
        MacLive(id: "remote", name: "Mac mini", desktop: true, online: true, running: 2, waiting: 0, gpu: 97, mem: 39,
                top: "rsync", topSince: .now.addingTimeInterval(-2064), topWaiting: false,
                gpuHist: [60, 72, 88, 95, 97, 98, 96, 99, 97, 94, 98, 99, 97, 96, 98, 99, 97, 98, 97, 97],
                jobs: [MacJob(label: "rsync", since: .now.addingTimeInterval(-2064), waiting: false),
                       MacJob(label: "render_s01.py", since: .now.addingTimeInterval(-5400), waiting: false)]),
    ]
    private static let macs = [
        MacLive(name: "MacBook Pro", desktop: false, online: true, running: 3, waiting: 1, gpu: 0, mem: 42,
                top: "S01_run2.sh --scene 4", topSince: .now.addingTimeInterval(-2843), topWaiting: false),
        MacLive(name: "Mac mini", desktop: true, online: true, running: 1, waiting: 0, gpu: 98, mem: 37,
                top: "~/ai/ltx-2-mlx/.venv/bin/python render_s01.py", topSince: .now.addingTimeInterval(-1290), topWaiting: false),
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LockScreenCard(state: Self.doneState)
                    .frame(maxWidth: .infinity, maxHeight: 160, alignment: .top)
                    .frame(height: 160, alignment: .top)
                    .background(Color(UIColor(hd: 0x0C0C0C)).opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                // v70: expanded Dynamic Island (black, its own margins, about 120 pt below the camera)
                LockScreenCard(state: Self.doneState, inIsland: true)
                    .frame(maxWidth: .infinity, maxHeight: 124, alignment: .top)
                    .frame(height: 124, alignment: .top)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).strokeBorder(.red.opacity(0.3)))
                ForEach(Array(LiveActivityManager.previewStates(now: .now).prefix(5).enumerated()), id: \.offset) { _, item in
                    var st = item.0
                    let _ = (st.macs = Self.macs)
                    LockScreenCard(state: st)
                        .frame(maxWidth: .infinity, maxHeight: 160, alignment: .top)
                        .frame(height: 160, alignment: .top)
                        .background(Color(UIColor(hd: 0x0C0C0C)).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.red.opacity(0.3)))
                }
            }
            .padding(12)
        }
        .background(Color.gray.opacity(0.3))
        .environment(\.colorScheme, .dark)
    }
}
#endif

#if DEBUG
/// v64 debug only (`-hdWidgetPreview YES`): the Macs widgets at iPhone sizes, with live JobTrail data if
/// the app has read it, else sample data.
struct WidgetPreviewScreen: View {
    @State private var snap = JTStore.load().flatMap { $0.macs.isEmpty ? nil : $0 } ?? .sample
    private func card<V: View>(_ w: CGFloat, _ h: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        v().padding(16).frame(width: w, height: h, alignment: .topLeading)
            .background(InstrumentBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(HDTone.amber.opacity(0.45)))
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    card(170, 170) { MacsSmallView(snap: snap, now: .now) }
                    card(170, 170) {
                        MacsLockView(snap: snap).foregroundStyle(.white).frame(height: 60)
                    }
                }
                card(364, 170) { MacsMediumView(snap: snap, now: .now) }
                card(364, 382) { MacsLargeView(snap: snap, now: .now) }
            }
            .padding(12)
        }
        .background(Color.gray.opacity(0.35))
        .environment(\.colorScheme, .dark)
        .task {
            await JobTrailLive.shared.poll()
            try? await Task.sleep(for: .seconds(3))
            if let s = JTStore.load(), !s.macs.isEmpty { snap = s }
        }
    }
}
#endif
