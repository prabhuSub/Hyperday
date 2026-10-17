import ActivityKit
import EventKit
import SwiftUI
import UserNotifications

/// v50: first-run flow (approved mockup). Welcome → Permissions → Shape your day.
/// Calendar access is read-only: Hyperday never edits or deletes events.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = false
    @State private var page = 0
    @State private var calendarOn = CalendarService.shared.hasAccess
    @State private var notificationsOn = false
    @State private var liveOn = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var picked: Set<String> = ["Deep Work", "Meetings", "Fitness", "Family"]
    @State private var showPro = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < 2 { Button("Skip") { finish() }.font(.system(size: 16, weight: .medium)) }
            }
            .frame(height: 44).padding(.horizontal, 22)

            TabView(selection: $page) {
                welcome.tag(0)
                permissions.tag(1)
                shape.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            VStack(spacing: 18) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i == page ? Color.accentColor : Color(.systemGray4))
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                Button {
                    if page < 2 { page += 1 } else { finish() }
                } label: {
                    Text(["Get started", "Continue", "Start my day"][page])
                        .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 52)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                if page == 2 {
                    Button("Try Pro free for 7 days") { showPro = true }.font(.system(size: 15, weight: .medium))
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .task { await refreshStatus() }
        .sheet(isPresented: $showPro) { PaywallView() }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ON YOUR LOCK SCREEN").font(.system(size: 13, weight: .semibold)).tracking(0.3)
                .foregroundStyle(.secondary).frame(maxWidth: .infinity)
            sampleActivity.padding(.top, 12)
            (Text("Your day,\n") + Text("live.").foregroundColor(.accentColor))
                .font(.system(size: 38, weight: .heavy)).tracking(-0.6).padding(.top, 36)
            Text("Plan your day in blocks. Hyperday keeps the current one on your Lock Screen until it's done.")
                .font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 10)
            HStack(alignment: .top, spacing: 8) {
                value(Image(systemName: "square.grid.2x2.fill"), "#5E5CE6", "Plan in", "blocks")
                value(Image("hd-lock").renderingMode(.template), "#30D158", "Live on", "Lock Screen")
                value(Image(systemName: "chart.bar.fill"), "#FF9F0A", "Plan vs", "real")
            }
            .padding(.top, 36)
            Spacer()
        }
        .padding(.horizontal, 24).padding(.top, 8)
    }

    private var sampleActivity: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HDIcon("deepwork", size: 22).foregroundStyle(Color(hex: "#30D158"))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Deep work").font(.system(size: 16, weight: .bold))
                    Text("Next: Standup at 10:30").font(.system(size: 12.5)).foregroundStyle(Color(.systemGray))
                }
                Spacer()
                Text("42:10").font(.system(size: 26, weight: .bold)).monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<36, id: \.self) { k in
                    RoundedRectangle(cornerRadius: 2).fill(k < 15 ? Color(hex: "#30D158") : Color(white: 0.24))
                        .frame(width: 4, height: k % 6 == 0 ? 14 : 9)
                }
            }
            HStack(spacing: 8) {
                Text("Pause").frame(maxWidth: .infinity).frame(height: 34).background(Color(white: 0.17), in: Capsule())
                Text("Done").foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 34)
                    .background(Color(hex: "#30D158"), in: Capsule())
            }
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func value(_ icon: Image, _ hex: String, _ a: String, _ b: String) -> some View {
        VStack(spacing: 8) {
            icon.resizable().scaledToFit().frame(width: 28, height: 28).foregroundStyle(Color(hex: hex))
            (Text(a + "\n") + Text(b).foregroundColor(.secondary).fontWeight(.medium))
                .font(.system(size: 12.5, weight: .semibold)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Three things to\nmake it work").font(.system(size: 34, weight: .heavy)).tracking(-0.5)
            Text("You can change any of these later in Settings.")
                .font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 10)
            VStack(spacing: 0) {
                permRow(HDIcon("event", size: 28).foregroundStyle(Color(hex: "#FF3B30")), "Calendar",
                        "Shows your events between blocks. Read-only: Hyperday never edits them.", calendarOn) {
                    _ = await CalendarService.shared.requestAccess()
                    CalendarService.shared.invalidate()
                    await LiveActivityManager.shared.refresh()
                }
                Divider().padding(.leading, 58)
                permRow(Image(systemName: "bell.fill").font(.system(size: 24)).foregroundStyle(Color(hex: "#FF9F0A")),
                        "Notifications", "A nudge when a block starts or runs over.", notificationsOn) {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                }
                Divider().padding(.leading, 58)
                permRow(Image(systemName: "platter.filled.bottom.iphone").font(.system(size: 24)).foregroundStyle(Color(hex: "#30D158")),
                        "Live Activities", "The current block on your Lock Screen and Dynamic Island.", liveOn) {
                    // iOS has no prompt for this: it's on by default; if it was turned off, send them to Settings.
                    if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, 34)
            Label("Your plan stays on this iPhone. No account needed.", systemImage: "lock.fill")
                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 24)
            Spacer()
        }
        .padding(.horizontal, 24).padding(.top, 20)
    }

    private func permRow(_ icon: some View, _ title: String, _ detail: String, _ on: Bool,
                         action: @escaping () async -> Void) -> some View {
        HStack(spacing: 14) {
            icon.frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if on {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: "#30D158"))
            } else {
                Button("Allow") { Task { await action(); await refreshStatus() } }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private static let suggestions: [(String, String)] = [
        ("Deep Work", "#30D158"), ("Meetings", "#BF5AF2"), ("Fitness", "#FF9F0A"), ("Study", "#5E5CE6"),
        ("Errands", "#64D2FF"), ("Reading", "#FFD60A"), ("Family", "#FF375F"), ("Side project", "#0A84FF"), ("Meals", "#AC8E68"),
    ]

    private var shape: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Shape your day").font(.system(size: 34, weight: .heavy)).tracking(-0.5)
            Text("Pick what fills your day. Each one becomes a category with its own color. Change them anytime in Settings.")
                .font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 10)
            Text("WHAT FILLS YOUR DAY?").font(.system(size: 13, weight: .semibold)).tracking(0.3)
                .foregroundStyle(.secondary).padding(.top, 30)
            ChipFlow(spacing: 8) {
                ForEach(Self.suggestions, id: \.0) { s in
                    let on = picked.contains(s.0)
                    Button {
                        if on { picked.remove(s.0) } else { picked.insert(s.0) }
                    } label: {
                        Text(s.0).font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 15).padding(.vertical, 9)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
            Spacer()
        }
        .padding(.horizontal, 24).padding(.top, 20)
    }

    // MARK: Actions

    private func refreshStatus() async {
        calendarOn = CalendarService.shared.hasAccess
        liveOn = ActivityAuthorizationInfo().areActivitiesEnabled
        notificationsOn = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Adds picked categories that don't exist yet. Never removes or renames anything.
    private func finish() {
        let store = CategoryStore.shared
        for s in Self.suggestions where picked.contains(s.0) {
            let exists = store.categories.contains { $0.name.caseInsensitiveCompare(s.0) == .orderedSame }
            if !exists { store.upsert(Category(id: UUID().uuidString, name: s.0, colorHex: s.1)) }
        }
        onboarded = true
        dismiss()
    }
}

/// Wraps chips onto new lines (simple flow layout; app only, never in a Live Activity).
struct ChipFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > w { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}
