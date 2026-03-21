import Foundation

/// A recent folder entry with its last-used timestamp.
struct RecentFolderEntry: Codable, Equatable {
  let path: String
  var lastUsedDate: Date

  var url: URL {
    URL(fileURLWithPath: path)
  }
}

/// Manages recent folders storage using UserDefaults.
/// Stores timestamps alongside paths to support time-based filtering.
@Observable
class RecentFoldersManager {
  static let shared = RecentFoldersManager()

  private let userDefaults = UserDefaults.standard

  /// New key for timestamped entries (JSON).
  private let entriesKey = "recentFolderEntries"

  /// Legacy key for plain path strings (migration source).
  private let legacyKey = "recentFolders"

  /// Upper bound to prevent unbounded UserDefaults growth.
  private let maxEntries = 50

  private(set) var entries: [RecentFolderEntry] = []

  /// Convenience accessor returning just URLs, sorted by most recent first.
  var recentFolders: [URL] {
    entries.map { $0.url }
  }

  private init() {
    loadEntries()
  }

  /// Adds a folder to the recent list.
  /// If the folder already exists, updates its timestamp and moves it to the top.
  func addRecentFolder(_ url: URL) {
    entries.removeAll { $0.path == url.path }
    let entry = RecentFolderEntry(path: url.path, lastUsedDate: Date())
    entries.insert(entry, at: 0)

    /// Evict oldest entries beyond the cap.
    if entries.count > maxEntries {
      entries = Array(entries.prefix(maxEntries))
    }

    saveEntries()
  }

  /// Removes a folder from the recent list.
  func removeRecentFolder(_ url: URL) {
    entries.removeAll { $0.path == url.path }
    saveEntries()
  }

  /// Clears all recent folders.
  func clearRecentFolders() {
    entries = []
    saveEntries()
  }

  /// Returns folders whose last-used date is within the given number of days.
  func foldersUsedWithin(days: Int) -> [RecentFolderEntry] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

    return entries.filter { $0.lastUsedDate >= cutoff }
  }

  // MARK: - Testing Support

  /// Replaces a single entry in-place. Intended for unit tests that need to backdate timestamps.
  func replaceEntry(at index: Int, with entry: RecentFolderEntry) {
    guard entries.indices.contains(index) else {
      return
    }

    entries[index] = entry
  }

  // MARK: - Persistence

  /// Loads entries from UserDefaults, migrating from legacy format if needed.
  /// Filters out non-existent directories.
  private func loadEntries() {
    if let data = userDefaults.data(forKey: entriesKey) {
      loadFromJSON(data)
    } else if let paths = userDefaults.stringArray(forKey: legacyKey) {
      migrateFromLegacy(paths)
    }
  }

  private func loadFromJSON(_ data: Data) {
    guard let decoded = try? JSONDecoder().decode([RecentFolderEntry].self, from: data) else {
      return
    }

    let originalCount = decoded.count
    entries = decoded.filter { folderExists(at: $0.path) }

    if entries.count < originalCount {
      saveEntries()
    }
  }

  /// Migrates legacy path-only storage to timestamped entries.
  /// Assigns the current date to all migrated entries.
  private func migrateFromLegacy(_ paths: [String]) {
    let now = Date()

    entries = paths.compactMap { path in
      guard folderExists(at: path) else {
        return nil
      }

      return RecentFolderEntry(path: path, lastUsedDate: now)
    }

    saveEntries()
    userDefaults.removeObject(forKey: legacyKey)
  }

  private func saveEntries() {
    guard let data = try? JSONEncoder().encode(entries) else {
      return
    }

    userDefaults.set(data, forKey: entriesKey)
  }

  private func folderExists(at path: String) -> Bool {
    var isDirectory: ObjCBool = false

    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}
