import Foundation

/// v49: whether Hyperday Pro is unlocked, shared with the widgets through the App Group.
/// The app writes it after every StoreKit check; widgets only read it.
/// Your own build (no PUBLIC_BUILD flag) is always Pro.
enum ProFlag {
    private static let key = "hd.pro"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetShared.appGroup) }

    static var isPro: Bool {
        #if PUBLIC_BUILD
        return defaults?.bool(forKey: key) ?? false
        #else
        return true
        #endif
    }

    static func set(_ on: Bool) { defaults?.set(on, forKey: key) }
}
