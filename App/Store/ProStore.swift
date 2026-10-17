import StoreKit
import SwiftUI
import WidgetKit

/// v49 Hyperday Pro with StoreKit 2: monthly or yearly subscription, 7-day free trial (set in App Store Connect,
/// and in Hyperday.storekit for testing in the simulator before joining the Developer Program).
@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    static let monthlyID = "com.prabhu.hyperday.pro.monthly"
    static let yearlyID = "com.prabhu.hyperday.pro.yearly"

    @Published private(set) var isPro = ProFlag.isPro
    @Published private(set) var products: [Product] = []
    @Published private(set) var trialEnd: Date?
    @Published var showPaywall = false
    @Published private(set) var busy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    private init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await load(); await refresh() }
    }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }

    func load() async {
        do { products = try await Product.products(for: [Self.monthlyID, Self.yearlyID]) }
        catch { message = "Couldn't reach the App Store. Try again in a moment." }
    }

    /// Pro = any verified, unrevoked entitlement for one of our products.
    func refresh() async {
        #if PUBLIC_BUILD
        var on = false
        var end: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil,
                  [Self.monthlyID, Self.yearlyID].contains(t.productID) else { continue }
            on = true
            if t.offerType == .introductory { end = t.expirationDate }
        }
        isPro = on
        trialEnd = end
        ProFlag.set(on)
        #else
        isPro = true   // your own build: everything unlocked
        #endif
        WidgetCenter.shared.reloadAllTimelines()
    }

    func buy(_ product: Product) async {
        busy = true; defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result { await t.finish() }
                await refresh()
                if isPro { showPaywall = false }
            case .pending: message = "Waiting for approval (Ask to Buy)."
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        busy = true; defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = isPro ? nil : "No Hyperday Pro purchase found for this Apple ID."
        if isPro { showPaywall = false }
    }
}

/// Pro features: show the feature, or a blurred preview with "Try free for 7 days".
struct ProLocked<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @ObservedObject private var pro = ProStore.shared

    var body: some View {
        if pro.isPro {
            content()
        } else {
            content()
                .blur(radius: 7)
                .allowsHitTesting(false)
                .overlay {
                    VStack(spacing: 8) {
                        Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                        Button("Try free for 7 days") { pro.showPaywall = true }
                            .font(.system(size: 14, weight: .bold))
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    }
                }
                .clipped()
        }
    }
}

/// Sheets behind Pro: the feature for Pro users, the paywall for everyone else.
struct ProSheet<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ObservedObject private var pro = ProStore.shared
    var body: some View {
        if pro.isPro { content() } else { PaywallView() }
    }
}

/// "PRO" chip next to a feature name.
struct ProChip: View {
    @ObservedObject private var pro = ProStore.shared
    var body: some View {
        if !pro.isPro {
            Text("PRO").font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(Theme.blue)
                .background(Capsule().fill(Theme.blue.opacity(0.12)))
        }
    }
}
