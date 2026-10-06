import SwiftUI

/// v32: Extend the running block, Apple Timer–style. Ruler picks how much to add; the pill confirms.
struct ExtendSheet: View {
    let block: Block
    let onExtend: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var add = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("EXTEND · \(block.title.uppercased())")
                .font(.system(size: 12, weight: .heavy)).tracking(1)
                .foregroundStyle(Theme.muted).lineLimit(1)
            Text("Ends \(block.end.shortTime) → \(block.end.addingTimeInterval(TimeInterval(add * 60)).shortTime)")
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.numericText())
            DurationRuler(minutes: $add, range: 5...180)
            HStack {
                Button {
                    onExtend(add)
                    dismiss()
                } label: {
                    Text("Add \(DurationRuler.long(add))")
                        .font(.system(size: 16, weight: .heavy))
                        .padding(.horizontal, 18).frame(height: 40)
                        .background(Capsule().fill(Theme.blue.opacity(0.18)))
                        .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
                Spacer()
                DurationReadout(minutes: add)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }
}
