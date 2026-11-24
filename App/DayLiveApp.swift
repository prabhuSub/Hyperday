import EventKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct DayLiveApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @StateObject private var store = BlockStore.shared
    @StateObject private var activity = LiveActivityManager.shared
    @StateObject private var categories = CategoryStore.shared
    @StateObject private var history = HistoryStore.shared
    @StateObject private var recap = RecapCenter.shared
    @StateObject private var cars = CarStore.shared
    @State private var showCloseDay = false
    @AppStorage("onboarded") private var onboarded = false
    @State private var showOnboarding = false

    init() {
        // v35: no custom tab bar look: Apple's own bar (Liquid Glass on iOS 26).
        // Must be set before launch finishes so a tap on the Sunday recap opens it.
        UNUserNotificationCenter.current().delegate = RecapCenter.shared
        // Reality line: keep watching saved places (iOS relaunches us on arrive/leave).
        if !RealityStore.shared.places.isEmpty { LocationService.shared.monitor(RealityStore.shared.places) }
        // v6: appearance follows the system by default (the header button used to force light/dark).
        if !UserDefaults.standard.bool(forKey: "appearanceResetV6") {
            UserDefaults.standard.set(Appearance.dark.rawValue, forKey: "appearance")
            UserDefaults.standard.set(true, forKey: "appearanceResetV6")
        }
        // v57: the JobTrail look is a dark design, so the revamp starts in Dark once (Light still works).
        if !UserDefaults.standard.bool(forKey: "appearanceResetV57") {
            UserDefaults.standard.set(Appearance.dark.rawValue, forKey: "appearance")
            UserDefaults.standard.set(true, forKey: "appearanceResetV57")
        }
        HDFonts.applyUIKit()
        #if DEBUG
        // v57: `-hdDemo YES` (simulator launch argument) loads sample data, for screenshots.
        if UserDefaults.standard.bool(forKey: "hdDemo") && !HistoryStore.shared.hasDemo { DemoData.load() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TypeSizeRebuilder {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "hdLAPreview") { LAPreviewScreen() } else { RootView().font(.hd(size: 16)) }
                #else
                RootView().font(.hd(size: 16))
                #endif
            }   // v52: fonts follow Text Size · v57: Geist by default
                .preferredColorScheme((Appearance(rawValue: appearance) ?? .dark).scheme)
                .tint(Theme.blue)
                .environmentObject(store)
                .environmentObject(activity)
                .environmentObject(categories)
                .environmentObject(history)
                .environmentObject(cars)
                .fullScreenCover(isPresented: $recap.showing) { WeeklyRecapView() }
                // v50: first run only. Existing installs (any history or blocks) skip it.
                .fullScreenCover(isPresented: $showOnboarding) { OnboardingView() }
                .onAppear {
                    if !onboarded {
                        if HistoryStore.shared.days.isEmpty && BlockStore.shared.planBlocks.isEmpty { showOnboarding = true }
                        else { onboarded = true }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in showOnboarding = true }
                // "Day closed · Review" on the Lock Screen opens hyperday://close
                .onOpenURL { url in
                    if url.host == "close" { showCloseDay = true }
                    if url.host == "onboarding" { showOnboarding = true }   // v50 test link
                    if url.host == "calendar" { CalendarJump.open(.now) }
                    if url.host == "car" { NotificationCenter.default.post(name: .openCarTab, object: nil) }   // car widgets   // calendar widget → Calendar tab, today
                }
                .sheet(isPresented: $showCloseDay) {
                    CloseDaySheet()
                        .environmentObject(store)
                        .environmentObject(history)
                        .presentationDetents([.large])
                }
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                    Task { await LiveActivityManager.shared.refresh() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { JobTrailLive.shared.start() } else if phase == .background { JobTrailLive.shared.stop() }   // v61
            if phase == .active {
                HDLog.event("foreground")
                // A save file that was locked at launch (after a reboot) can be read now.
                BlockStore.shared.retryLoadIfNeeded()
                HistoryStore.shared.retryLoadIfNeeded()
                CategoryStore.shared.retryLoadIfNeeded()
                RealityStore.shared.retryLoadIfNeeded()
                BackupStore.shared.backUpIfDue()   // weekly copy to Files › Hyperday › Backups
                Task {
                    await RealityStore.shared.refreshWorkouts()
                    await LiveActivityManager.shared.refresh()
                    await RecapCenter.shared.schedule()
                    if Features.car || Features.carWidgets { await CarStore.shared.refresh() }   // v35: car is off for now
                }
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.id)) {
            HDLog.event("bg-fired")   // v52: did iOS actually wake us?
            await JobTrailLive.shared.poll()   // v61: fresh Mac status for the card
            await LiveActivityManager.shared.refresh()
            if Features.car || Features.carWidgets { await CarStore.shared.refresh() }   // v38: keeps car widgets current
        }
    }
}

/// v57: Geist in the UIKit parts SwiftUI doesn't reach (navigation titles, tab bar labels).
enum HDFonts {
    static func applyUIKit() {
        func f(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
        }
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: f("Geist-Bold", 32, .largeTitle)]
        nav.titleTextAttributes = [.font: f("Geist-SemiBold", 17, .headline)]
        let tab = UITabBarItem.appearance()
        tab.setTitleTextAttributes([.font: f("GeistMono-Medium", 10, .caption2)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: f("Geist-Medium", 13, .footnote)], for: .normal)
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("hd.showOnboarding")   // Settings › Developer › Show onboarding
}
