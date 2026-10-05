import Foundation
import SwiftUI

/// v25 Backup & Restore. One JSON file per backup in Documents/Backups, visible in
/// Files › On My iPhone › Hyperday › Backups. Holds plans, history, categories, places and settings
/// (not the calendar itself — that stays in Calendar). Weekly automatic copy, 8 kept.
@MainActor
final class BackupStore: ObservableObject {
    static let shared = BackupStore()

    struct Item: Identifiable, Hashable {
        let url: URL
        let date: Date
        let bytes: Int
        var id: URL { url }
    }

    private struct Archive: Codable {
        var version = 1
        var created: Date
        var files: [String: Data]      // file name → contents
        var defaults: Data?            // settings (property list)
    }

    @Published private(set) var items: [Item] = []
    @AppStorage("backupWeekly") var weekly = true
    @AppStorage("backupLast") private var lastBackupTime: Double = 0

    var lastBackup: Date? { lastBackupTime > 0 ? Date(timeIntervalSince1970: lastBackupTime) : nil }

    private static let files = ["daylive-store.json", "daylive-history.json", "daylive-categories.json", "daylive-reality.json"]
    private static let keep = 8
    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var folder: URL { docs.appendingPathComponent("Backups", isDirectory: true) }

    private init() { reloadList() }

    // MARK: Back up

    @discardableResult
    func backUpNow(tag: String = "") -> Bool {
        var files: [String: Data] = [:]
        for name in Self.files {
            if let d = try? Data(contentsOf: docs.appendingPathComponent(name)) { files[name] = d }
        }
        guard !files.isEmpty else { return false }
        let prefs = UserDefaults.standard.dictionaryRepresentation().filter { Self.isSetting($0.key) }
        let archive = Archive(created: .now, files: files,
                              defaults: try? PropertyListSerialization.data(fromPropertyList: prefs, format: .binary, options: 0))
        guard let data = try? JSONEncoder().encode(archive) else { return false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"
        let url = folder.appendingPathComponent("hyperday-\(f.string(from: .now))\(tag).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        lastBackupTime = Date.now.timeIntervalSince1970
        prune()
        reloadList()
        return true
    }

    /// Called when the app comes to the front: one automatic copy a week.
    func backUpIfDue() {
        guard weekly else { return }
        if let last = lastBackup, Date.now.timeIntervalSince(last) < 7 * 86_400 { return }
        backUpNow()
    }

    // MARK: Restore

    /// Backs up what's there now first (so a restore can be undone), then puts the backup's files back.
    func restore(_ item: Item) -> Bool {
        guard let data = try? Data(contentsOf: item.url),
              let archive = try? JSONDecoder().decode(Archive.self, from: data) else { return false }
        backUpNow(tag: "-before-restore")
        for (name, contents) in archive.files where Self.files.contains(name) {
            try? contents.write(to: docs.appendingPathComponent(name), options: .atomic)
        }
        if let d = archive.defaults,
           let prefs = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
            for (k, v) in prefs where Self.isSetting(k) { UserDefaults.standard.set(v, forKey: k) }
        }
        BlockStore.shared.reloadFromDisk()
        HistoryStore.shared.reloadFromDisk()
        CategoryStore.shared.reloadFromDisk()
        RealityStore.shared.reloadFromDisk()
        Task { await LiveActivityManager.shared.refresh() }
        return true
    }

    // MARK: Files

    func reloadList() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        items = urls.filter { $0.pathExtension == "json" }.compactMap { u in
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return Item(url: u, date: v?.contentModificationDate ?? .distantPast, bytes: v?.fileSize ?? 0)
        }
        .sorted { $0.date > $1.date }
    }

    private func prune() {
        reloadList()
        for old in items.dropFirst(Self.keep) { try? FileManager.default.removeItem(at: old.url) }
    }

    /// Hyperday's own settings only (not Apple's or other frameworks' keys).
    private static func isSetting(_ key: String) -> Bool {
        let mine = ["dc", "appearance", "reality", "meetingAlerts", "autoStart", "focus", "category", "calendar", "heat", "recap"]
        return mine.contains { key.hasPrefix($0) } && !key.hasPrefix("backup")
    }
}
