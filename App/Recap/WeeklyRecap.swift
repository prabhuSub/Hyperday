import SwiftUI
import UIKit
import UserNotifications

// MARK: - Numbers

struct WeeklyRecap {
    var range: String            // "SEP 22 – 28"
    var focusedHours: Double
    var changeHours: Double?     // vs the 7 days before; nil when there's no history then
    var streak: Int
    var steps: Int
    var bestDay: String?         // "Wed"
    var byCategory: [CategoryHours]
    var topCategory: String?
    var meetingShare: Int?       // % of tracked time
    var isEmpty: Bool
}

extension HistoryStore {
    /// The 7 days ending today (Sunday evening -> Monday–Sunday).
    func weeklyRecap(now: Date = .now) -> WeeklyRecap {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let dates = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let prior = (7..<14).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let focusIDs: Set<String> = ["work", "deepwork"]

        func entries(_ ds: [Date]) -> [HistoryEntry] { ds.compactMap { days[Self.key($0)] }.flatMap(\.entries) }
        func focused(_ es: [HistoryEntry]) -> Double { es.reduce(0) { $0 + $1.hours(in: focusIDs) } }

        let week = entries(dates)
        let before = entries(prior)
        let total = week.reduce(0) { $0 + $1.hours }

        var byID: [String: Double] = [:]
        for e in week { for s in e.shares { byID[s.id, default: 0] += s.hours } }
        let byCategory = CategoryStore.shared.categories
            .map { CategoryHours(id: $0.id, name: $0.name, color: $0.color, hours: byID[$0.id] ?? 0) }
            .filter { $0.hours > 0.05 }
            .sorted { $0.hours > $1.hours }

        let best = dates
            .map { d in (d, focused(days[Self.key(d)]?.entries ?? [])) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0

        let first = dates.last ?? today
        let sameMonth = cal.component(.month, from: first) == cal.component(.month, from: today)
        let startText = first.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        let endText = sameMonth ? today.formatted(.dateTime.day()) : today.formatted(.dateTime.month(.abbreviated).day()).uppercased()

        return WeeklyRecap(
            range: "\(startText) – \(endText)",
            focusedHours: focused(week),
            changeHours: before.isEmpty ? nil : focused(week) - focused(before),
            streak: streak(now: now),
            steps: week.reduce(0) { $0 + $1.stepsDone },
            bestDay: best?.formatted(.dateTime.weekday(.abbreviated)),
            byCategory: byCategory,
            topCategory: byCategory.first?.name,
            meetingShare: total > 0 ? Int(((byID["meetings"] ?? 0) / total * 100).rounded()) : nil,
            isEmpty: week.isEmpty
        )
    }
}

private func hoursText(_ h: Double) -> String {
    h >= 10 ? "\(Int(h.rounded()))h" : (h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h))
}

// MARK: - Notification (Sunday 7 PM, local — no server)

@MainActor
final class RecapCenter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = RecapCenter()
    nonisolated static let id = "hyperday.weekly-recap"

    /// Set when the notification is tapped; RootView shows the recap full screen.
    @Published var showing = false

    /// Once per launch/foreground: (re)schedule the next Sunday 7 PM with this week's numbers so far.
    func schedule() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            // Ask only once there's something to recap.
            guard !HistoryStore.shared.days.isEmpty else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        var next = DateComponents()
        next.weekday = 1   // Sunday
        next.hour = 19
        guard let fire = Calendar.current.nextDate(after: .now, matching: next, matchingPolicy: .nextTime) else { return }

        var recap = HistoryStore.shared.weeklyRecap(now: fire)
        recap.streak = HistoryStore.shared.streak(now: .now)   // counting from the future Sunday always gave 0
        let content = UNMutableNotificationContent()
        content.title = "Hyperday"
        content.body = recap.isEmpty
            ? "Your weekly recap is ready. Tap to see it."
            : "Your week: \(hoursText(recap.focusedHours)) focused, \(recap.streak)-day streak. Tap to see your recap."
        content.sound = .default
        if let check = Self.checkAttachment() { content.attachments = [check] }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
            repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [Self.id])
        try? await center.add(UNNotificationRequest(identifier: Self.id, content: content, trigger: trigger))
    }

    /// Small green round check shown as the notification's thumbnail.
    private static func checkAttachment() -> UNNotificationAttachment? {
        let renderer = ImageRenderer(content: GreenCheck(size: 60))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recap-check-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "check", url: url)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Self.id else { return }
        await MainActor.run { self.showing = true }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - Views

struct GreenCheck: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.19, green: 0.82, blue: 0.35))   // #30D158
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// The shareable card. Always dark, like the mockup.
struct RecapCard: View {
    let recap: WeeklyRecap

    private let muted = Color(white: 0.64)
    private let line = Color(white: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) {
                    GreenCheck(size: 13)
                    Text("HYPERDAY").font(.system(size: 12, weight: .heavy)).kerning(4)
                }
                Spacer()
                caps(recap.range)
            }

            VStack(alignment: .leading, spacing: 2) {
                caps("Your week")
                Text(hoursText(recap.focusedHours))
                    .font(.system(size: 64, weight: .heavy))
                    .kerning(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subline).font(.system(size: 15)).foregroundStyle(muted)
            }

            HStack(spacing: 14) {
                stat("Streak", "\(recap.streak) day\(recap.streak == 1 ? "" : "s")")
                stat("Steps", "\(recap.steps)")
                stat("Best day", recap.bestDay ?? "—")
            }

            if !recap.byCategory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    caps("Where it went")
                    GeometryReader { geo in
                        let total = recap.byCategory.reduce(0) { $0 + $1.hours }
                        HStack(spacing: 0) {
                            ForEach(recap.byCategory) { c in
                                c.color.frame(width: geo.size.width * c.hours / max(total, 0.01))
                            }
                        }
                    }
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    FlowLayout(spacing: 12) {
                        ForEach(recap.byCategory) { c in
                            HStack(spacing: 5) {
                                Circle().fill(c.color).frame(width: 7, height: 7)
                                Text(c.name).font(.system(size: 11)).foregroundStyle(muted)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if let top = recap.topCategory {
                (Text("Top category: ").foregroundStyle(muted)
                 + Text(top).bold()
                 + Text(recap.meetingShare.map { " · Meetings took \($0)% of your time" } ?? "").foregroundStyle(muted))
                    .font(.system(size: 12))
            }
        }
        .foregroundStyle(Color(white: 0.96))
        .padding(.horizontal, 24)
        .padding(.vertical, 26)
        .background(
            LinearGradient(colors: [Color(red: 0.11, green: 0.114, blue: 0.133), Color(red: 0.063, green: 0.067, blue: 0.078)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(line))
    }

    private var subline: String {
        guard let c = recap.changeHours, abs(c) >= 0.5 else { return "focused" }
        return "focused · \(c > 0 ? "+" : "−")\(hoursText(abs(c))) vs last week"
    }

    private func caps(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 10, weight: .bold)).kerning(1.4).foregroundStyle(muted)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            caps(label)
            Text(value).font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .overlay(alignment: .top) { line.frame(height: 1) }
    }
}

struct WeeklyRecapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    let recap: WeeklyRecap

    @MainActor
    init(recap: WeeklyRecap? = nil) { self.recap = recap ?? HistoryStore.shared.weeklyRecap() }

    @State private var image: UIImage?

    private func render() -> UIImage? {
        let r = ImageRenderer(content: RecapCard(recap: recap).frame(width: 350, height: 540).padding(20)
            .background(Color(red: 0.05, green: 0.055, blue: 0.063)))
        r.scale = 3
        return r.uiImage
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.055, blue: 0.063).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        HDIcon("close", size: 16)
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                RecapCard(recap: recap)
                    .task { if image == nil { image = render() } }   // once, not on every redraw
                HStack(spacing: 10) {
                    if let img = image {
                        ShareLink(item: Image(uiImage: img),
                                  preview: SharePreview("My week in Hyperday", image: Image(uiImage: img))) {
                            Text("Share").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RecapButton(filled: true))
                    }
                    Button {
                        if let img = image {
                            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                            saved = true
                        }
                    } label: {
                        Text(saved ? "Saved" : "Save image").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RecapButton(filled: false))
                    .disabled(saved)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.dark)
    }
}

private struct RecapButton: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 44)
            .background(filled ? Theme.blue : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(filled ? Color.clear : Color(white: 0.18)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
