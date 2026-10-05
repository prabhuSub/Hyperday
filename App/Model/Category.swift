import Combine
import Foundation
import SwiftUI

/// A category like Work or Fitness. Its color becomes the Live Activity accent.
struct Category: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var colorHex: String
    var icon: String? = nil   // asset name without "hd-"; nil = default for this category

    var color: Color { Color(hex: colorHex) }
    var iconName: String { icon ?? HDIcons.defaultCategoryIcon(id) }
}

/// "Title has gym, run -> Fitness". Rules are checked top to bottom; first match wins.
struct CategoryRule: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case title, calendar
        var label: String { self == .title ? "Title has" : "Calendar is" }
    }

    var id: String = UUID().uuidString
    var kind: Kind
    var keywords: String      // comma-separated, case-insensitive
    var categoryID: String

    var keywordList: [String] {
        keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    func matches(title: String, calendarName: String?) -> Bool {
        let haystack = (kind == .title ? title : (calendarName ?? "")).lowercased()
        guard !haystack.isEmpty else { return false }
        return keywordList.contains { haystack.contains($0) }
    }
}

@MainActor
final class CategoryStore: ObservableObject {
    static let shared = CategoryStore()

    static let teslaRed = "#E31937"
    static let palette = ["#E31937", "#0A84FF", "#BF5AF2", "#30D158", "#FF9F0A", "#FF375F",
                          "#64D2FF", "#FFD60A", "#5E5CE6", "#AC8E68", "#8E8E93"]

    static let defaultCategories: [Category] = [
        Category(id: "work", name: "Work", colorHex: "#0A84FF"),
        Category(id: "meetings", name: "Meetings", colorHex: "#BF5AF2"),
        Category(id: "deepwork", name: "Deep Work", colorHex: "#30D158"),
        Category(id: "fitness", name: "Fitness", colorHex: "#FF9F0A"),
        Category(id: "family", name: "Family", colorHex: "#FF375F"),
        Category(id: "personal", name: "Personal", colorHex: "#64D2FF"),
    ]

    /// Meeting keywords sit ABOVE the Tesla-calendar rule, or every Tesla meeting would count as Work.
    static let defaultRules: [CategoryRule] = [
        CategoryRule(kind: .title, keywords: "1:1, sync, standup, meeting, review, interview", categoryID: "meetings"),
        CategoryRule(kind: .title, keywords: "gym, run, workout, yoga, walk", categoryID: "fitness"),
        CategoryRule(kind: .title, keywords: "focus, deep work", categoryID: "deepwork"),
        CategoryRule(kind: .title, keywords: "family, dinner, kids", categoryID: "family"),
        CategoryRule(kind: .calendar, keywords: "tesla, work", categoryID: "work"),
    ]

    @Published var categories: [Category] = CategoryStore.defaultCategories { didSet { save() } }
    @Published var rules: [CategoryRule] = CategoryStore.defaultRules { didSet { save() } }
    /// Used when no rule matches ("Everything else").
    @Published var fallbackID: String = "personal" { didSet { save() } }
    /// Per-calendar display color, keyed by calendar name. "category" = follow the category color.
    @Published var calendarColors: [String: String] = [:] { didSet { save() } }

    private struct Snapshot: Codable {
        var categories: [Category]
        var rules: [CategoryRule]
        var fallbackID: String
        var calendarColors: [String: String]?
    }

    private var loading = false
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("daylive-categories.json")
    }()

    private init() { load() }

    // MARK: Lookup

    func category(id: String?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    var fallback: Category {
        category(id: fallbackID) ?? categories.first ?? CategoryStore.defaultCategories[5]
    }

    /// What the rules say, ignoring any manual override.
    func ruleCategory(title: String, calendarName: String?) -> Category {
        for rule in rules where rule.matches(title: title, calendarName: calendarName) {
            if let c = category(id: rule.categoryID) { return c }
        }
        return fallback
    }

    /// Manual override (set in the block editor) wins, then rules, then the fallback.
    func category(for block: Block) -> Category {
        if let c = category(id: BlockStore.shared.categoryOverrides[block.id]) { return c }
        return ruleCategory(title: block.title, calendarName: block.calendarName)
    }

    /// Every category of a block: the manual picks (first sets the color), or the one the rules give.
    func categories(for block: Block) -> [Category] {
        let picked = BlockStore.shared.manualCategoryIDs(for: block.id).compactMap { category(id: $0) }
        return picked.isEmpty ? [category(for: block)] : picked
    }

    // MARK: Calendar colors

    /// The color set for a calendar in Hyperday. Tesla calendars default to Tesla red.
    func calendarColorHex(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        if let hex = calendarColors[name] { return hex == "category" ? nil : hex }
        return name.lowercased().contains("tesla") ? CategoryStore.teslaRed : nil
    }

    /// Color shown for a block: manual category > calendar color > category from rules.
    func displayColorHex(for block: Block) -> String {
        if let c = category(id: BlockStore.shared.categoryOverrides[block.id]) { return c.colorHex }
        if block.source == .calendar, let hex = calendarColorHex(block.calendarName) { return hex }
        return category(for: block).colorHex
    }

    func displayColor(for block: Block) -> Color { Color(hex: displayColorHex(for: block)) }

    // MARK: Editing

    func upsert(_ category: Category) {
        if let i = categories.firstIndex(where: { $0.id == category.id }) {
            categories[i] = category
        } else {
            categories.append(category)
        }
    }

    func delete(id: String) {
        guard categories.count > 1 else { return }
        categories.removeAll { $0.id == id }
        rules.removeAll { $0.categoryID == id }
        if fallbackID == id { fallbackID = categories[0].id }
    }

    /// New rules go to the top so they take priority.
    func addRule(_ rule: CategoryRule) { rules.insert(rule, at: 0) }

    func deleteRule(id: String) { rules.removeAll { $0.id == id } }

    func moveRuleUp(id: String) {
        guard let i = rules.firstIndex(where: { $0.id == id }), i > 0 else { return }
        rules.swapAt(i, i - 1)
    }

    // MARK: Persistence

    private var loadBlocked = false

    func retryLoadIfNeeded() { if loadBlocked { load() } }
    func reloadFromDisk() { load() }   // after a restore

    private func load() {
        let snap: Snapshot
        switch SafeFile.load(Snapshot.self, from: fileURL) {
        case .loaded(let s): snap = s; loadBlocked = false
        case .missing: loadBlocked = false; return
        case .unavailable, .unreadable: loadBlocked = true; return
        }
        loading = true
        categories = snap.categories.isEmpty ? CategoryStore.defaultCategories : snap.categories
        rules = snap.rules
        fallbackID = snap.fallbackID
        calendarColors = snap.calendarColors ?? [:]
        loading = false
    }

    private func save() {
        guard !loading, !loadBlocked else { return }
        let snap = Snapshot(categories: categories, rules: rules, fallbackID: fallbackID, calendarColors: calendarColors)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
