import EventKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct DayLiveApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @StateObject private var store = BlockStore.shared
    @StateObject private var activity = LiveActivityManager.shared
    @StateObject private var categories = CategoryStore.shared
    @StateObject private var history = HistoryStore.shared
    @StateObject private var recap = RecapCenter.shared
    @StateObject private var cars = CarStore.shared
    @State private var showCloseDay = false

    init() {
        // v35: no custom tab bar look: Apple's own bar (Liquid Glass on iOS 26).
        // Must be set before launch finishes so a tap on the Sunday recap opens it.
        UNUserNotificationCenter.current().delegate = RecapCenter.shared
        // Reality line: keep watching saved places (iOS relaunches us on arrive/leave).
        if !RealityStore.shared.places.isEmpty { LocationService.shared.monitor(RealityStore.shared.places) }
        // v6: appearance follows the system by default (the header button used to force light/dark).
        if !UserDefaults.standard.bool(forKey: "appearanceResetV6") {
            UserDefaults.standard.set(Appearance.system.rawValue, forKey: "appearance")
            UserDefaults.standard.set(true, forKey: "appearanceResetV6")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme((Appearance(rawValue: appearance) ?? .system).scheme)
                .tint(Theme.blue)
                .environmentObject(store)
                .environmentObject(activity)
                .environmentObject(categories)
                .environmentObject(history)
                .environmentObject(cars)
                .fullScreenCover(isPresented: $recap.showing) { WeeklyRecapView() }
                // "Day closed · Review" on the Lock Screen opens hyperday://close
                .onOpenURL { url in
                    if url.host == "close" { showCloseDay = true }
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
            if phase == .active {
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
            await LiveActivityManager.shared.refresh()
            if Features.car || Features.carWidgets { await CarStore.shared.refresh() }   // v38: keeps car widgets current
        }
    }
}
