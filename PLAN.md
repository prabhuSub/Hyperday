# Hyperday

## Plan your day in blocks {#plan}
tech: BlockStore + DayEngine, EventKit calendars, categories/rules, App Intents, on-device AI planner
files: [App/Model/**, App/Views/ContentView.swift, App/Views/QuickAddSheet.swift, App/Views/ExtendSheet.swift, App/Views/DurationRuler.swift, App/Views/CalendarTabView.swift, App/Intents/**, App/AI/**, App/Photos/**]
links: [live, widgets, review]
- [x] Add, edit, move and delete planned blocks {#plan-blocks}
  tech: BlockStore.swift, QuickAddSheet.swift
- [x] Read your iOS calendars without ever editing them {#plan-calendar}
  tech: CalendarService.swift
- [x] Set a block's length with an Apple-style ruler and extend the running block {#plan-ruler}
  tech: DurationRuler.swift, ExtendSheet.swift
- [x] Attach the exact photo to a task (never read) {#plan-photos}
  tech: App/Photos/PhotoStore.swift, PhotoTaskSheet.swift
- [x] Plan with words using the on-device model {#plan-words}
  tech: AIPlanner.swift, PlanWithWordsSheet.swift
- [x] Add blocks from Siri / Shortcuts and filter by Focus {#plan-intents}
  tech: AddBlockIntent.swift, FocusFilter.swift

## Show the day on the Lock Screen and Dynamic Island {#live}
tech: ActivityKit Live Activity, shared SwiftUI card views, button intents
files: [Shared/LiveActivityViews.swift, Shared/DayActivityAttributes.swift, Shared/BlockActionIntent.swift, App/LiveActivity/**, Widget/DayLiveWidget.swift]
needs: [plan]
links: [push]
- [x] Show the running block with countdown, tick strip, Pause and Done {#live-running}
  tech: LiveActivityViews.swift (lockJourney / islandJourney)
- [x] Show free time as Free → Next → Later on one strip {#live-free}
  tech: LiveActivityViews.swift PhasesStrip
- [x] Close the day with a done check and thick focus bars {#live-closed}
  tech: DayClosedCard, Widget/DayLiveWidget.swift ClosedCheck
- [x] Keep the long-press Island compact so nothing is cut off {#live-island}
  tech: islandJourney (v37)

## Switch the card on time from the Raspberry Pi {#push}
tech: Python push server on prabhu-pi behind Tailscale, APNs
files: [server/**]
needs: [live]
- [x] Accept the day's card schedule and send it at each block boundary {#push-server}
  tech: server/hyperday_push
- [ ] Turn on real pushes with an APNs key (runs in dry-run until then) {#push-apns}
  from: roadmap

## Glance at your day with widgets {#widgets}
tech: WidgetKit Home / Lock Screen / StandBy widgets reading App Group data
files: [Widget/HyperdayWidgets.swift, Widget/DockWidgets.swift, Widget/LockScreenWidgets.swift, Widget/CalendarWidget.swift, Widget/HeatWidgets.swift, Shared/WidgetData.swift, Shared/Heatmap.swift, Shared/HDIcon.swift]
needs: [plan]
- [x] Today, Now, Day and Circle widgets {#widgets-day}
  tech: HyperdayWidgets.swift, LockScreenWidgets.swift
- [x] Calendar and heatmap widgets {#widgets-cal}
  tech: CalendarWidget.swift, HeatWidgets.swift
- [x] Dock-style widgets: Now strip, Day strip, Now with Pause/Done, 4 tiles {#widgets-dock}
  tech: Widget/DockWidgets.swift
  by: claude

## Show your Tesla {#car}
tech: Tesla Fleet API (PKCE, Keychain), SceneKit 3D Model Y, car widgets
files: [App/Car/**, Widget/CarWidgets.swift, Widget/CarSmallWidgets.swift, Shared/CarData.swift, tools/tesla_*.sh, tesla-site/**]
links: [widgets, ship]
- [x] Sign in with Tesla and read battery, range, lock, Sentry, climate, windows, tires {#car-read}
  tech: TeslaAuth.swift, TeslaAPI.swift, CarStore.swift
- [x] Show the car in 3D with preset views, badges and Tesla-style status {#car-3d}
  tech: CarView.swift
- [x] Car widgets: small gauges, Lock Screen card, Home small/medium/big {#car-widgets}
  tech: CarSmallWidgets.swift, CarWidgets.swift
- [ ] Lock, climate and charge limit from the app, signed on the iPhone with Face ID {#car-commands}
  tech: Secure Enclave P-256 key, re-pair, Vehicle Command Protocol; allowlist only (never unlock / start / summon)
  from: roadmap
- [ ] Frunk, trunk and charge-port labels on the 3D car {#car-labels}
  from: roadmap

## Compare the plan with real life and review the day {#review}
tech: CoreLocation places, HealthKit workouts, history, stats, weekly recap
files: [App/Reality/**, App/Recap/**, App/Insights/**, App/Model/HistoryStore.swift, App/Model/DayClose.swift, App/Views/StatsView.swift, App/Views/HeatmapCard.swift, App/Views/CloseDaySheet.swift]
needs: [plan]
- [x] Plan vs real lanes on Today {#review-reality}
  tech: RealityViews.swift RealityCard
- [x] Close the day and review what was left {#review-close}
  tech: CloseDaySheet.swift, DayClose.swift
- [x] Stats, heatmap and Sunday recap {#review-stats}
  tech: StatsView.swift, HeatmapCard.swift, WeeklyRecap.swift

## Make it look and feel like an Apple app {#look}
tech: SwiftUI components, Liquid Glass tab bar, iOS Settings-style list, icons
files: [App/Views/Components.swift, App/Views/SettingsView.swift, App/Profile/**, App/Assets.xcassets/**, Widget/Assets.xcassets/**, tools/make_icons.py, tools/filled_icons.json, tools/make_app_icon.py, tools/icon-layers/**]
links: [plan, car]
- [x] Apple tab bar with a dated Calendar icon and a floating + with the system menu {#look-tabs}
  tech: Components.swift RootView, AddFab
- [x] Settings like iOS Settings {#look-settings}
  tech: SettingsView.swift
- [x] Solid, rounded icons with no circles or squares behind them {#look-solid-icons}
  tech: tools/filled_icons.json, tools/make_icons.py, Assets.xcassets/Icons
  by: claude
- [ ] Turn Close the day, Reality line and Backup settings into native pages {#look-settings-rest}
  tech: still CardSettingsPage wrappers
  from: agent

## Build, ship and keep secrets safe {#ship}
tech: XcodeGen + deploy.sh to the phone, pre-commit secret guard, unit tests, docs
files: [deploy.sh, tools/sim.sh, project.yml, tools/secret-guard.py, Tests/**, docs/**, README.md, CHANGELOG.md, .gitignore]
links: [car]
- [x] One-command build and install to the iPhone {#ship-deploy}
  tech: deploy.sh, project.yml
- [x] Block Tesla keys and tokens from ever being committed {#ship-secrets}
  tech: tools/secret-guard.py, .gitignore (.tesla-keys)
- [x] Day engine unit tests {#ship-tests}
  tech: Tests/DayEngineTests.swift
- [x] Test every Live Activity state and a full test day from Settings › Developer {#ship-testkit}
  tech: LiveActivityManager.previewStates (11 states), loadTestDay
  by: claude
- [x] Build and run on the iPhone 17 Pro Max simulator {#ship-sim}
  tech: tools/sim.sh (Xcode 27 Device Hub)
  by: claude

## decisions
- 2026-10-09: Map auto-generated by Claude from the code layout, git log (v2–v46) and server/README. Ticks are from files found in the repo; nothing was run or compiled to check behaviour.
- Car commands stay unchecked on purpose: Prabhu paused them to review; they must stay allowlist-only with Face ID.
