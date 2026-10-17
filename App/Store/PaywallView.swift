import StoreKit
import SwiftUI

/// v49 paywall (approved mockup): what Pro adds, Yearly / Monthly, "Start 7-day free trial", Restore, Terms, Privacy.
struct PaywallView: View {
    @ObservedObject private var pro = ProStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pickYearly = true

    private var selected: Product? { pickYearly ? (pro.yearly ?? pro.monthly) : (pro.monthly ?? pro.yearly) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array([(14.0, "#5E5CE6"), (26, "#0A84FF"), (36, "#30D158"), (22, "#FF9F0A"), (30, "#BF5AF2")].enumerated()), id: \.offset) { _, b in
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: b.1)).frame(width: 8, height: b.0)
                        }
                    }
                    Text("Hyperday Pro").font(.hd(size: 30, weight: .heavy)).padding(.top, 12)
                    Text("Your whole day, everywhere you look.").font(.hd(size: 15)).foregroundStyle(.secondary)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        feature("timer", "#30D158", "All widgets", "Dock-style, Lock Screen and StandBy widgets with Pause and Done.")
                        feature("recap", "#BF5AF2", "Stats and weekly recap", "Focus by hour, streaks, your Sunday recap.")
                        feature("deepwork", "#5E5CE6", "Plan vs real", "See what you planned next to what happened.")
                        feature("siri", "#0A84FF", "Plan with words", "Say your day; it becomes blocks, on your iPhone.")
                        feature("event", "#FF3B30", "Photo tasks", "Attach the exact photo to a task.")
                    }
                    .padding(.top, 14)

                    HStack(spacing: 10) {
                        plan(title: "Yearly", product: pro.yearly, fallback: "$19.99", sub: perMonth(pro.yearly) ?? "$1.67 / month",
                             on: pickYearly, badge: "SAVE 44%") { pickYearly = true }
                        plan(title: "Monthly", product: pro.monthly, fallback: "$2.99", sub: "per month",
                             on: !pickYearly, badge: nil) { pickYearly = false }
                    }
                    .padding(.top, 16)

                    Button {
                        if let p = selected { Task { await pro.buy(p) } }
                    } label: {
                        Group {
                            if pro.busy { ProgressView().tint(.white) } else { Text(trialText).font(.hd(size: 17, weight: .bold)) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .disabled(selected == nil || pro.busy)
                    .padding(.top, 16)

                    Text("Then \(selected?.displayPrice ?? (pickYearly ? "$19.99" : "$2.99"))/\(pickYearly ? "year" : "month"). Cancel anytime in Settings › Apple ID.")
                        .font(.hd(size: 11.5)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 8)
                    HStack(spacing: 6) {
                        Button("Restore purchases") { Task { await pro.restore() } }
                        Text("·").foregroundStyle(.secondary)
                        Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Text("·").foregroundStyle(.secondary)
                        Link("Privacy", destination: URL(string: "https://prabhusubramanian.com/hyperday/privacy")!)
                    }
                    .font(.hd(size: 11.5)).frame(maxWidth: .infinity).padding(.top, 4)
                    if let m = pro.message {
                        Text(m).font(.hd(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
                    }
                }
                .padding(24)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { SheetCloseButton(title: "Close") { dismiss(); pro.showPaywall = false } } }
            .task { if pro.products.isEmpty { await pro.load() } }
        }
    }

    private var trialText: String {
        guard let p = selected, p.subscription?.introductoryOffer?.paymentMode == .freeTrial else { return "Subscribe" }
        return "Start 7-day free trial"
    }

    private func perMonth(_ p: Product?) -> String? {
        guard let p else { return nil }
        return (p.price / 12).formatted(p.priceFormatStyle) + " / month"
    }

    private func feature(_ icon: String, _ hex: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HDIcon(icon, size: 24).foregroundStyle(Color(hex: hex))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.hd(size: 15, weight: .semibold))
                Text(sub).font(.hd(size: 12.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func plan(title: String, product: Product?, fallback: String, sub: String, on: Bool, badge: String?,
                      tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.hd(size: 13, weight: .bold))
                Text(product?.displayPrice ?? fallback).font(.hd(size: 20, weight: .bold))
                Text(sub).font(.hd(size: 11.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(on ? Theme.blue : Theme.border, lineWidth: on ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge).font(.hd(size: 10, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.blue)).offset(x: -10, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
