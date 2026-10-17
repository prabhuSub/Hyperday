import SwiftUI
import UIKit

/// v52 Dynamic Type: the app used fixed point sizes everywhere, so Settings › Text Size did nothing.
/// `.hd(size:)` is a drop-in for `.hd(size:)` that grows with the user's text size,
/// capped at XXX Large so card layouts don't break (the accessibility sizes are a later step).
extension Font {
    static func hd(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: HDType.scaled(size), weight: weight, design: design)
    }
}

extension Font {
    /// v55: SF Mono readouts that follow Text Size.
    static func hdMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: HDType.scaled(size), weight: weight, design: .monospaced)
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
