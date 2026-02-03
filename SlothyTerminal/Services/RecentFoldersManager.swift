import Foundation

/// Manages recent folders storage using UserDefaults.
@Observable
class RecentFoldersManager {
  static let shared = RecentFoldersManager()

  private let userDefaults = UserDefaults.standard
  private let recentFoldersKey = "recentFolders"
  private let maxRecentFolders = 10

  private(set) var recentFolders: [URL] = []

  private init() {
    loadRecentFolders()
  }

  /// Adds a folder to the recent list.
  /// If the folder already exists, it moves to the top.
  func addRecentFolder(_ url: URL) {
    /// Remove if already exists.
    recentFolders.removeAll { $0.path == url.path }

    /// Add to the beginning.
    recentFolders.insert(url, at: 0)

    /// Trim to max size.
    if recentFolders.count > maxRecentFolders {
      recentFolders = Array(recentFolders.prefix(maxRecentFolders))
    }

    saveRecentFolders()
  }

  /// Removes a folder from the recent list.
  func removeRecentFolder(_ url: URL) {
    recentFolders.removeAll { $0.path == url.path }
    saveRecentFolders()
  }

  /// Clears all recent folders.
  func clearRecentFolders() {
    recentFolders = []
    saveRecentFolders()
  }

  /// Loads recent folders from UserDefaults.
  /// Filters out non-existent directories and saves the cleaned list.
  private func loadRecentFolders() {
    guard let paths = userDefaults.stringArray(forKey: recentFoldersKey) else {
      return
    }

    let originalCount = paths.count

    recentFolders = paths.compactMap { path in
      let url = URL(fileURLWithPath: path)

      /// Check if the folder still exists.
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
         isDirectory.boolValue
      {
        return url
      }
      return nil
    }

    /// Save cleaned list if any invalid paths were removed.
    if recentFolders.count < originalCount {
      saveRecentFolders()
    }
  }

  /// Saves recent folders to UserDefaults as path strings.
  private func saveRecentFolders() {
    let paths = recentFolders.map { $0.path }
    userDefaults.set(paths, forKey: recentFoldersKey)
  }
}
