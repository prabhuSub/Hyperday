import AppIntents
import SwiftUI
import UIKit

/// v35: Settings like the iOS Settings app. One inset-grouped list with coloured icon squares;
/// each row opens its own plain Apple page.
struct SettingsView: View {
    @EnvironmentObject private var categories: CategoryStore
    @EnvironmentObject private var activity: LiveActivityManager
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @ObservedObject private var profile = ProfileStore.shared
    @State private var showProfile = false

    // v58: JobTrail settings: grouped cards with mono section heads; every row opens the same page as before.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { showProfile = true } label: {
                    JTCard(padding: 16) {
                        HStack(spacing: 14) {
                            ProfileAvatar(size: 54)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Your profile")
                                    .font(.hd(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                                Text("PHOTO AND NAME").font(.hdMono(size: 10, weight: .semibold)).kerning(0.8)
                                    .foregroundStyle(Theme.faint)
                            }
                            Spacer()
                            JTBadge(text: activity.isRunning ? "Live" : "Idle", working: activity.isRunning)
                        }
                    }
                }
                .buttonStyle(JTPressStyle())
                .jtStagger(0)

                group("Your day", index: 1) {
                    link("Appearance", "sun.max.fill", .orange, value: (Appearance(rawValue: appearance) ?? .dark).label) { AppearanceSettings() }
                    link("Categories", "tag.fill", .purple, value: "\(categories.categories.count)") { CategoriesSettings() }
                    link("Calendars", "calendar", .red, value: "\(CalendarService.shared.calendarList().count)") { CalendarsSettings() }
                    link("Auto rules", "bolt.fill", .indigo, value: "\(categories.rules.count)", last: true) { RulesSettings() }
                }
                group("Live", index: 2) {
                    link("Live Activity", "timer", .green, value: activity.autoStart ? "On" : "Off", status: activity.isRunning ? .running : .idle) { LiveActivitySettings() }
                    link("Close the day", "moon.fill", .indigo) { CardSettingsPage(title: "Close the day") { DayCloseSettingsCard() } }
                    link("Reality line", "mappin", .blue) { CardSettingsPage(title: "Reality line") { RealitySettingsCard() } }
                    link("Focus & Siri", "mic.fill", .purple, last: true) { FocusSettings() }
                }
                group("System", index: 3) {
                    link("Backup", "externaldrive.fill", .gray) { CardSettingsPage(title: "Backup") { BackupCard() } }
                    link("Developer", "hammer.fill", Color(white: 0.4), last: !Features.car) { DeveloperSettings() }
                    if Features.car {
                        link("Car", "car.fill", .red, last: true) { CardSettingsPage(title: "Car") { CarSettingsCard() } }
                    }
                }
                Text("HYPERDAY · v58")
                    .font(.hdMono(size: 10, weight: .medium)).kerning(1.2)
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
            }
            .padding(.horizontal, Theme.edge)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .jtScrollsToTop("settings")   // v60
        .sheet(isPresented: $showProfile) { ProfileSheet() }
    }

    private func group<C: View>(_ title: String, index: Int, @ViewBuilder _ rows: () -> C) -> some View {
        let content = rows()
        return VStack(alignment: .leading, spacing: 8) {
            JTSectionHead(title)
            JTCard { VStack(spacing: 0) { content } }
        }
        .jtStagger(index)
    }

    private func link<D: View>(_ title: String, _ symbol: String, _ color: Color, value: String? = nil,
                               status: HDStatus? = nil, last: Bool = false,
                               @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.geist(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.navActive, lineWidth: 1))
                Text(title).font(.hd(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                Spacer()
                if let status {
                    if status == .running {
                        JTPulseButton(info: JTPulseInfo(title: "Live Activity", status: .running,
                                                        subtitle: "ON YOUR LOCK SCREEN AND DYNAMIC ISLAND",
                                                        items: [JTKV(key: "State", value: "Running", color: HDTone.green),
                                                                JTKV(key: "Auto start", value: activity.autoStart ? "On" : "Off")]),
                                      boxed: false)
                            .frame(width: 34, height: 12)
                    }
                    JTStatusDot(status: status, size: 6)
                }
                if let value { Text(value).font(.hdMono(size: 12)).foregroundStyle(Theme.muted) }
                Image(systemName: "chevron.right").font(.geist(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(Theme.navActive).frame(height: 1).padding(.leading, 56) }
            }
        }
        .buttonStyle(JTPressStyle())
    }
}

/// The coloured rounded square with a white SF Symbol, like iOS Settings.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)   // v47: solid symbol in colour, no square behind
            .font(.hd(size: 19, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
    }
}

/// Pages not yet turned into native lists: the existing card on the grouped background.
struct CardSettingsPage<C: View>: View {
    let title: String
    @ViewBuilder var content: () -> C
    var body: some View {
        ScrollView { content().padding(16).jtStagger(0) }
            .background(Theme.bg)
    }
}

struct AppearanceSettings: View {
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

struct CategoriesSettings: View {
    @ObservedObject private var categories = CategoryStore.shared
    @State private var editing: Category?
    var body: some View {
        List {
            Section {
                ForEach(categories.categories) { c in
                    Button { editing = c } label: {
                        HStack(spacing: 12) {
                            Circle().fill(c.color).frame(width: 12, height: 12)
                            Text(c.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.hd(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
            } footer: { Text("Tap a category to rename it or change its color and icon.") }
            Section {
                Button("New category") {
                    editing = Category(id: UUID().uuidString, name: "",
                                       colorHex: CategoryStore.palette[categories.categories.count % CategoryStore.palette.count])
                }
            }
        }
        .sheet(item: $editing) { c in
            CategoryEditorSheet(category: c, isNew: categories.category(id: c.id) == nil)
                .presentationDetents([.medium])
        }
    }
}

struct CalendarsSettings: View {
    @ObservedObject private var categories = CategoryStore.shared
    @State private var editing: CalendarPick?
    var body: some View {
        let list = CalendarService.shared.calendarList()
        List {
            Section {
                if list.isEmpty { Text("Allow calendar access to color your calendars.").foregroundStyle(.secondary) }
                ForEach(list, id: \.name) { item in
                    let custom = categories.calendarColorHex(item.name)
                    Button { editing = CalendarPick(name: item.name, iosHex: item.hex) } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(custom.map { Color(hex: $0) } ?? Color.clear)
                                .overlay(Circle().stroke(custom == nil ? Color.secondary : .clear, lineWidth: 1.5))
                                .frame(width: 12, height: 12)
                            Text(item.name).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            Text(custom == nil ? "By category" : "Custom").foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: { Text("A calendar color beats the category color everywhere except Stats. Tesla calendars start as Tesla red.") }
        }
        .sheet(item: $editing) { pick in
            CalendarColorSheet(pick: pick).presentationDetents([.medium])
        }
    }
}

struct RulesSettings: View {
    @ObservedObject private var categories = CategoryStore.shared
    @State private var adding = false
    var body: some View {
        List {
            Section {
                ForEach(Array(categories.rules.enumerated()), id: \.element.id) { index, rule in
                    HStack(spacing: 12) {
                        Circle().fill(categories.category(id: rule.categoryID)?.color ?? .secondary).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(rule.kind.label) “\(rule.keywords)”").lineLimit(2)
                            Text(categories.category(id: rule.categoryID)?.name ?? "—").font(.hd(size: 15)).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { categories.deleteRule(id: rule.id) }
                    }
                    .contextMenu {
                        if index > 0 {
                            Button { categories.moveRuleUp(id: rule.id) } label: { Label("Move up", systemImage: "arrow.up") }
                        }
                        Button(role: .destructive) { categories.deleteRule(id: rule.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            } header: { Text("First match wins") } footer: { Text("Swipe left to delete. Touch and hold to move a rule up.") }
            Section {
                Picker("Everything else", selection: $categories.fallbackID) {
                    ForEach(categories.categories) { c in Text(c.name).tag(c.id) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add rule")
            }
        }
        .sheet(isPresented: $adding) { RuleEditorSheet().presentationDetents([.medium]) }
    }
}

struct LiveActivitySettings: View {
    @EnvironmentObject private var activity: LiveActivityManager
    @AppStorage(MacAlerts.key) private var macAlerts = false
    @State private var syncing = false
    @State private var piError = false
    var body: some View {
        Form {
            Section {
                Toggle("Start automatically", isOn: $activity.autoStart)
            } footer: { Text("Starts when the day has blocks. \(activity.statusText)") }
            // v75
            Section {
                Toggle("Mac alerts", isOn: $macAlerts)
                    .onChange(of: macAlerts) { _, on in if !syncing { Task { if !(await MacAlerts.setRemote(on)) { piError = true } } } }
            } footer: {
                Text(piError ? "Couldn't reach the Pi, so the switch didn't save. Is Tailscale on?" :
                    "Your Pi sends these to the ntfy app within a minute, even with Hyperday closed: MacBook under 20 % and not charging, or the Mac mini not answering for 3 minutes. Same switch as in HomeDeck › Settings › Alerts. While it lasts, a red line shows on the Live Activity.")
            }
            .task { syncing = true; if let on = await MacAlerts.remote() { macAlerts = on }; try? await Task.sleep(for: .milliseconds(100)); syncing = false }
            Section {
                Button("Preview all styles") { Task { await activity.previewStyles() } }
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: { Text("Look") } footer: {
                Text("Tap Preview, then lock the phone: all 11 states (running, last 5 min, free, closed, paused, overtime, steps, calendar event, free with Next only, closed with tasks left, driving), 5 seconds each. Then your real day comes back.")
            }
        }
    }
}

struct FocusSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Right now", value: FocusFilterState.current.rawValue)
            } header: { Text("Focus filters") } footer: {
                Text("In iOS Settings › Focus › Work › Add Filter › Hyperday, choose what Hyperday shows while that Focus is on.")
            }
            Section {
                ShortcutsLink().shortcutsLinkStyle(.automaticOutline)
            } header: { Text("Deep Work + Focus") } footer: {
                Text("Apple doesn't let apps turn Focus on. In Shortcuts, make one shortcut with “Start Deep Work” (Hyperday) and “Set Focus: Work”, then run it from Siri or the Action Button.")
            }
            Section("Say to Siri") {
                ForEach(["What's next in Hyperday", "Start my day in Hyperday", "I'm done in Hyperday", "Start deep work in Hyperday"], id: \.self) {
                    Text("“\($0)”")
                }
            }
        }
    }
}

struct DeveloperSettings: View {
    @EnvironmentObject private var activity: LiveActivityManager
    @EnvironmentObject private var history: HistoryStore
    var body: some View {
        Form {
            Section {
                ForEach(Array(["Running", "Last 5 min", "Free (Next + Later)", "Day closed",
                                      "Paused", "Overtime", "Steps", "Calendar event",
                                      "Free (Next only)", "Day closed, tasks left", "Driving"].enumerated()), id: \.offset) { i, name in
                    Button(name) { Task { await activity.previewOne(i) } }
                }
            } header: { Text("Test one style for 60 s") }
            Section {
                Button("Show onboarding") { NotificationCenter.default.post(name: .showOnboarding, object: nil) }
            } header: { Text("First run") }
            Section {
                Button("Load test day") { Task { await activity.loadTestDay() } }
                Button("Remove test day", role: .destructive) { Task { await activity.clearTestDay() } }
            } header: { Text("Test a real mini-day") } footer: {
                Text("Adds 'Test ·' blocks around now: Inbox zero done earlier, Deep work running with steps (1 of 4, last 5 min in about a minute), a short free gap, a photo task at +9 min, Standup at +20, Gym at +45. Remove deletes only the test blocks and their photo.")
            }
            Section {
                Button(history.hasDemo ? "Remove sample data" : "Load sample data", role: history.hasDemo ? .destructive : nil) {
                    if history.hasDemo { DemoData.remove() } else { DemoData.load() }
                    Task { await activity.refresh() }
                }
            } header: { Text("Sample data") } footer: {
                Text("8 sample weeks for Today, Calendar and Stats. Your real calendars are never touched.")
            }
        }
    }
}

// MARK: - Category editor

struct CategoryEditorSheet: View {
    @State var category: Category
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CategoryStore.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Caps("Name")
                    TextField("Category name", text: $category.name)
                        .font(.hd(size: 20, weight: .semibold))
                }
                .cardBox()

                VStack(alignment: .leading, spacing: 10) {
                    Caps("Color")
                    FlowLayout(spacing: 10) {
                        ForEach(CategoryStore.palette, id: \.self) { hex in
                            Button { category.colorHex = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Theme.text, lineWidth: category.colorHex == hex ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(hex)")
                        }
                    }
                }
                .cardBox()

                VStack(alignment: .leading, spacing: 10) {
                    Caps("Icon")
                    FlowLayout(spacing: 10) {
                        ForEach(HDIcons.categoryChoices, id: \.self) { name in
                            let on = category.iconName == name
                            Button { category.icon = name } label: {
                                HDIcon(name, size: 22)
                                    .foregroundStyle(on ? Theme.bg : Theme.text)
                                    .frame(width: 42, height: 42)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.text : Theme.card))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Icon \(name)")
                        }
                    }
                }
                .cardBox()

                if !isNew && store.categories.count > 1 {
                    Button("Delete category") {
                        store.delete(id: category.id)
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .foregroundStyle(Theme.red)
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.section)
            .navigationTitle(isNew ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        category.name = category.name.trimmingCharacters(in: .whitespaces)
                        store.upsert(category)
                        Task { await LiveActivityManager.shared.refresh() }
                        dismiss()
                    }
                    .disabled(category.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Rule editor

struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CategoryStore.shared

    @State private var kind: CategoryRule.Kind = .title
    @State private var keywords = ""
    @State private var categoryID: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Caps("When")
                    PillNav(options: CategoryRule.Kind.allCases, selection: $kind) { $0.label }
                    TextField(kind == .title ? "gym, run, yoga" : "Tesla", text: $keywords)
                        .font(.hd(size: 17))
                        .textInputAutocapitalization(.never)
                    Text("Separate words with commas. Not case-sensitive.")
                        .font(.hd(size: 12))
                        .foregroundStyle(Theme.faint)
                }
                .cardBox()

                VStack(alignment: .leading, spacing: 10) {
                    Caps("Then category")
                    FlowLayout(spacing: 8) {
                        ForEach(store.categories) { c in
                            Chip(title: c.name, color: c.color, selected: categoryID == c.id) { categoryID = c.id }
                        }
                    }
                }
                .cardBox()
                Spacer()
            }
            .padding(20)
            .background(Theme.section)
            .navigationTitle("New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let categoryID {
                            store.addRule(CategoryRule(kind: kind, keywords: keywords, categoryID: categoryID))
                            Task { await LiveActivityManager.shared.refresh() }
                        }
                        dismiss()
                    }
                    .disabled(categoryID == nil || keywords.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Calendar color

struct CalendarPick: Identifiable {
    var id: String { name }
    let name: String
    let iosHex: String
}

struct CalendarColorSheet: View {
    let pick: CalendarPick
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CategoryStore.shared

    var body: some View {
        let current = store.calendarColorHex(pick.name)
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Caps("Color for \(pick.name)")
                    FlowLayout(spacing: 10) {
                        ForEach([pick.iosHex] + CategoryStore.palette, id: \.self) { hex in
                            Button { choose(hex) } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Theme.text, lineWidth: current == hex ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hex == pick.iosHex ? "iOS color" : "Color \(hex)")
                        }
                    }
                    Text("First swatch is this calendar's color in the iOS Calendar app.")
                        .font(.hd(size: 12))
                        .foregroundStyle(Theme.faint)
                }
                .cardBox()

                Button("Use category colors instead") { choose("category") }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
            .padding(20)
            .background(Theme.section)
            .navigationTitle(pick.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func choose(_ hex: String) {
        store.calendarColors[pick.name] = hex
        Task { await LiveActivityManager.shared.refresh() }
    }
}


/// v25 Settings › Backup (mockup V25Backup).
struct BackupCard: View {
    @ObservedObject private var backups = BackupStore.shared
    @State private var restoring = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Backup", icon: "share", color: HDTone.blue).padding(.bottom, 8)
            Toggle("Weekly backup", isOn: $backups.weekly)
                .font(.hd(size: 14, weight: .semibold))
                .tint(DayLiveStyle.doneGreen)
                .padding(.bottom, 8)
            line("Last backup", backups.lastBackup.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "Never",
                 color: backups.lastBackup == nil ? Theme.muted : DayLiveStyle.doneGreen)
            line("Kept", "\(backups.items.count) of 8")
            line("Size", ByteCountFormatter.string(fromByteCount: Int64(backups.items.first?.bytes ?? 0), countStyle: .file))
            HStack(spacing: 10) {
                Button("Back up now") {
                    message = backups.backUpNow() ? "Backed up." : "Nothing to back up yet."
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Restore…") { backups.reloadList(); restoring = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(backups.items.isEmpty)
            }
            .padding(.top, 12)
            if let message {
                Text(message).font(.hd(size: 12, weight: .semibold)).foregroundStyle(DayLiveStyle.doneGreen).padding(.top, 6)
            }
            Text("Saved in Files › On My iPhone › Hyperday › Backups. Plans, history, categories, places and settings — not your calendar (that stays in Calendar). AirDrop or save to iCloud Drive from Files for an off-phone copy.")
                .font(.hd(size: 11.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
        .cardBox()
        .sheet(isPresented: $restoring) {
            RestoreSheet { message = $0 }
                .presentationDetents([.medium, .large])
        }
    }

    private func line(_ a: String, _ b: String, color: Color = Theme.muted) -> some View {
        HStack {
            Text(a).font(.hd(size: 14)).foregroundStyle(Theme.text)
            Spacer()
            Text(b).font(.hd(size: 14, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

private struct RestoreSheet: View {
    @ObservedObject private var backups = BackupStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var picked: BackupStore.Item?
    let done: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Restore a backup").font(.hd(size: 20, weight: .heavy)).foregroundStyle(Theme.text)
            Text("Your current data is backed up first, so you can undo.")
                .font(.hd(size: 12)).foregroundStyle(Theme.muted).padding(.top, 4).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(backups.items) { item in
                        Button { picked = item } label: {
                            HStack {
                                Image(systemName: picked == item ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(picked == item ? Theme.blue : Theme.faint)
                                Text(item.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(item.bytes), countStyle: .file))
                                    .foregroundStyle(Theme.muted)
                            }
                            .font(.hd(size: 14))
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Restore") {
                    guard let picked else { return }
                    done(backups.restore(picked) ? "Restored. Your previous data was backed up first." : "That backup couldn't be read.")
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(picked == nil)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .background(Theme.section)
    }
}
