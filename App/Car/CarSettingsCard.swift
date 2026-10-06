import SwiftUI

/// v31 Settings › Car: connect, usage this month (capped), sample car for widgets, plate.
struct CarSettingsCard: View {
    @EnvironmentObject private var cars: CarStore
    @State private var clientID = ""
    @State private var secret = ""
    @State private var showKeys = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Car", icon: "car", color: Color(hex: "#64D2FF"))

            if cars.signedIn {
                HStack {
                    Text("Connected to Tesla").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Button("Disconnect") { cars.disconnect() }.font(.system(size: 13, weight: .bold)).foregroundStyle(.red)
                }
            } else {
                Button("Sign in with Tesla") { Task { await cars.connect() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!cars.hasClientID)
            }

            // What's set up, and what Tesla last said (so problems aren't silent).
            VStack(alignment: .leading, spacing: 3) {
                Label(cars.hasClientID ? "Client ID saved" : "No Client ID yet",
                      systemImage: cars.hasClientID ? "checkmark.circle.fill" : "exclamationmark.circle")
                Label(TeslaKeychain.get("clientSecret") != nil ? "Client secret saved" : "No client secret (only needed if Tesla asks)",
                      systemImage: TeslaKeychain.get("clientSecret") != nil ? "checkmark.circle.fill" : "circle")
                if let m = cars.message { Label(m, systemImage: "info.circle").foregroundStyle(.orange) }
                if let c = cars.car, !c.isSample {
                    Label("Last read \(c.updatedAt.formatted(.relative(presentation: .named))): \(c.battery)% · \(c.rangeMiles) mi",
                          systemImage: "car")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.muted)

            if cars.signedIn {
                Button(cars.busy ? "Reading…" : "Read my car now (wakes it, 2¢)") { cars.start(force: true, wake: true) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(cars.busy)
            }

            // This month's Tesla calls (Hyperday stops before Tesla's $10 free credit runs out).
            HStack(spacing: 14) {
                meter("Reads", .data); meter("Wakes", .wake); meter("Commands", .command)
            }
            Text(String(format: "About $%.2f of Tesla's $10 free credit this month.", TeslaMeter.dollars))
                .font(.system(size: 12)).foregroundStyle(Theme.muted)

            Toggle(isOn: Binding(get: { cars.car?.isSample == true }, set: { cars.setSample($0) })) {
                Text("Sample car for widgets").font(.system(size: 14)).foregroundStyle(Theme.text)
            }
            .tint(Theme.blue)

            HStack {
                Text("Plate").font(.system(size: 14)).foregroundStyle(Theme.text)
                TextField("e.g. 7ABC123", text: $cars.plate)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .multilineTextAlignment(.trailing).font(.system(size: 14, weight: .semibold))
            }
            Text("Drawn on the 3D car only. Stays on this iPhone.").font(.system(size: 11)).foregroundStyle(Theme.faint)

            DisclosureGroup(isExpanded: $showKeys) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Client ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Client secret (only if Tesla asks)", text: $secret)
                    Button("Save to Keychain") {
                        if !clientID.isEmpty { TeslaKeychain.set(clientID, for: "clientID") }
                        if !secret.isEmpty { TeslaKeychain.set(secret, for: "clientSecret") }
                        clientID = ""; secret = ""; saved = true
                        cars.objectWillChange.send()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if saved { Text("✓ Saved. The fields clear on purpose; the keys are in the Keychain.").foregroundStyle(DayLiveStyle.doneGreen).font(.system(size: 12, weight: .semibold)) }
                    Text("Saved only in this iPhone's Keychain (never synced, never in a backup).")
                        .font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
                .font(.system(size: 14))
                .padding(.top, 6)
            } label: {
                Text("Tesla app keys").font(.system(size: 14)).foregroundStyle(Theme.text)
            }
            .tint(Theme.muted)
        }
        .cardBox()
    }

    private func meter(_ label: String, _ k: TeslaMeter.Kind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(TeslaMeter.used(k))/\(TeslaMeter.cap(k))").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).kerning(0.8).foregroundStyle(Theme.muted)
        }
    }
}
