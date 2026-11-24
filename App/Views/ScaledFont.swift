import SwiftUI
import UIKit

/// v52 Dynamic Type: the app used fixed point sizes everywhere, so Settings › Text Size did nothing.
/// `.hd(size:)` is a drop-in for `.hd(size:)` that grows with the user's text size,
/// capped at XXX Large so card layouts don't break (the accessibility sizes are a later step).
extension Font {
    /// v57: Geist (Geist Mono when `design: .monospaced`), following Text Size.
    static func hd(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        design == .monospaced ? .geistMono(size: HDType.scaled(size), weight: weight)
                              : .geist(size: HDType.scaled(size), weight: weight)
    }
}

extension Font {
    /// v57: Geist Mono readouts (labels, times, stats) that follow Text Size.
    static func hdMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .geistMono(size: HDType.scaled(size), weight: weight)
    }
}

enum HDType {
    static let maxCategory: UIContentSizeCategory = .extraExtraExtraLarge

    static func scaled(_ size: CGFloat) -> CGFloat {
        var cat = UIApplication.shared.preferredContentSizeCategory
        if cat > maxCategory { cat = maxCategory }
        return UIFontMetrics.default.scaledValue(for: size, compatibleWith: UITraitCollection(preferredContentSizeCategory: cat))
    }
}

/// Rebuilds its content when Text Size changes, so every `.hd` font re-reads the new size.
struct TypeSizeRebuilder<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var content: Content
    var body: some View { content.id(typeSize) }
}
