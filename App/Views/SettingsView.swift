import AppIntents
import SwiftUI
import UIKit

/// v35: Settings like the iOS Settings app. One inset-grouped list with coloured icon squares;
/// each row opens its own plain Apple page.
struct SettingsView: View {
    @EnvironmentObject private var categories: CategoryStore
    @EnvironmentObject private var activity: LiveActivityManager
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @ObservedObject private var profile = ProfileStore.shared
    @State private var showProfile = false

    var body: some View {
        List {
            Section {
                Button { showProfile = true } label: {
                    HStack(spacing: 14) {
                        ProfileAvatar(size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Your profile")
                                .font(.title3.weight(.semibold)).foregroundStyle(.primary)
                            Text("Photo and name").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                link("Appearance", "sun.max.fill", .orange, value: (Appearance(rawValue: appearance) ?? .system).label) { AppearanceSettings() }
                link("Categories", "tag.fill", .purple, value: "\(categories.categories.count)") { CategoriesSettings() }
                link("Calendars", "calendar", .red, value: "\(CalendarService.shared.calendarList().count)") { CalendarsSettings() }
                link("Auto rules", "bolt.fill", .indigo, value: "\(categories.rules.count)") { RulesSettings() }
            }
            Section {
                link("Live Activity", "timer", .green, value: activity.autoStart ? "On" : "Off") { LiveActivitySettings() }
                link("Close the day", "moon.fill", .indigo) { CardSettingsPage(title: "Close the day") { DayCloseSettingsCard() } }
                link("Reality line", "mappin", .blue) { CardSettingsPage(title: "Reality line") { RealitySettingsCard() } }
                link("Focus & Siri", "mic.fill", .purple) { FocusSettings() }
            }
            Section {
                link("Backup", "externaldrive.fill", .gray) { CardSettingsPage(title: "Backup") { BackupCard() } }
                link("Developer", "hammer.fill", Color(white: 0.4)) { DeveloperSettings() }
                // Car is off for now (v35). Bring back: Features.car = true.
                if Features.car {
                    link("Car", "car.fill", .red) { CardSettingsPage(title: "Car") { CarSettingsCard() } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showProfile) { ProfileSheet() }
    }

    private func link<D: View>(_ title: String, _ symbol: String, _ color: Color, value: String? = nil,
                               @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, color: color)
                Text(title)
                Spacer()
                if let value { Text(value).foregroundStyle(.secondary) }
            }
        }
    }
}

/// The coloured rounded square with a white SF Symbol, like iOS Settings.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Pages not yet turned into native lists: the existing card on the grouped background.
struct CardSettingsPage<C: View>: View {
    let title: String
    @ViewBuilder var content: () -> C
    var body: some View {
        ScrollView { content().padding(16) }
            .background(Color(UIColor.systemGroupedBackground))
    }
}

struct AppearanceSettings: View {
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
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
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
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
                            Text(categories.category(id: rule.categoryID)?.name ?? "—").font(.subheadline).foregroundStyle(.secondary)
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
    var body: some View {
        Form {
            Section {
                Toggle("Start automatically", isOn: $activity.autoStart)
            } footer: { Text("Starts when the day has blocks. \(activity.statusText)") }
            Section {
                Button("Preview all styles") { Task { await activity.previewStyles() } }
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: { Text("Look") } footer: {
                Text("Tap Preview, then lock the phone: Running → Last 5 min → Free → Day closed, 7 seconds each. Then your real day comes back.")
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
                ForEach(Array(["Running", "Last 5 min", "Free", "Day closed"].enumerated()), id: \.offset) { i, name in
                    Button(name) { Task { await activity.previewOne(i) } }
                }
            } header: { Text("Test one style for 60 s") }
            Section {
                Button("Load test day") { Task { await activity.loadTestDay() } }
                Button("Remove test day", role: .destructive) { Task { await activity.clearTestDay() } }
            } header: { Text("Test a real mini-day") } footer: {
                Text("Adds 'Test ·' blocks around now: Deep work running (last 5 min in about a minute), 3 min free, Standup at +9 min, Gym at +30. Remove deletes only the test blocks.")
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
                        .font(.system(size: 20, weight: .semibold))
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
                        .font(.system(size: 17))
                        .textInputAutocapitalization(.never)
                    Text("Separate words with commas. Not case-sensitive.")
                        .font(.system(size: 12))
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
                        .font(.system(size: 12))
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
            SectionHeader("Backup", icon: "share", color: Color(hex: "#64D2FF")).padding(.bottom, 8)
            Toggle("Weekly backup", isOn: $backups.weekly)
                .font(.system(size: 14, weight: .semibold))
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
                Text(message).font(.system(size: 12, weight: .semibold)).foregroundStyle(DayLiveStyle.doneGreen).padding(.top, 6)
            }
            Text("Saved in Files › On My iPhone › Hyperday › Backups. Plans, history, categories, places and settings — not your calendar (that stays in Calendar). AirDrop or save to iCloud Drive from Files for an off-phone copy.")
                .font(.system(size: 11.5))
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
            Text(a).font(.system(size: 14)).foregroundStyle(Theme.text)
            Spacer()
            Text(b).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
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
            Text("Restore a backup").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.text)
            Text("Your current data is backed up first, so you can undo.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 4).padding(.bottom, 10)
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
                            .font(.system(size: 14))
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
