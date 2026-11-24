#if DEBUG
import SwiftUI

/// v61 debug only (`-hdLAPreview YES`): the Lock Screen card at its real 160 pt cap, with sample Macs,
/// for every preview state. Used to check nothing is cut off.
struct LAPreviewScreen: View {
    private static let macs = [
        MacLive(name: "MacBook Pro", desktop: false, online: true, running: 3, waiting: 1, gpu: 0, mem: 42,
                top: "S01_run2.sh --scene 4", topSince: .now.addingTimeInterval(-2843), topWaiting: false),
        MacLive(name: "Mac mini", desktop: true, online: true, running: 1, waiting: 0, gpu: 98, mem: 37,
                top: "~/ai/ltx-2-mlx/.venv/bin/python render_s01.py", topSince: .now.addingTimeInterval(-1290), topWaiting: false),
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
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
