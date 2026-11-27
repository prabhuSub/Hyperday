import WidgetKit
import SwiftUI

// v78 Lock Screen look shared with HomeDeck (its Live Activity cards): small icon + mono caps header, one big Geist
// value, a drawn bar, a mono sub-line; circles are drawn rings. iOS tints Lock Screen widgets one colour over the
// wallpaper, so the style lives in type, icons and shapes.

struct LKHead<Icon: View>: View {
    let label: String; var right: String? = nil
    @ViewBuilder var icon: () -> Icon
    var body: some View {
        HStack(spacing: 3) {
            icon().font(.system(size: 9, weight: .semibold))
            Text(label.uppercased()).font(.mono(9, .semibold)).kerning(0.5).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            if let r = right { Text(r.uppercased()).font(.mono(9, .semibold)).kerning(0.4).lineLimit(1) }
        }
        .opacity(0.75)
    }
}

struct LKBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().opacity(0.25)
                Capsule().frame(width: max(3, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 3)
    }
}

struct LKRing<Center: View>: View {
    let value: Double
    @ViewBuilder var center: () -> Center
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 3.5).opacity(0.25).padding(4)
            Circle().trim(from: 0, to: min(1, max(0, value))).stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(4)
            center().padding(.horizontal, 7)
        }
    }
}
