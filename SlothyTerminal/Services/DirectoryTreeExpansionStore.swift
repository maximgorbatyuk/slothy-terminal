import Foundation
import OSLog

/// Remembers which sidebar directory-tree folders are expanded, keyed by the
/// tree's root directory path, so the expansion state survives workspace
/// switches (which recreate `DirectoryTreeView`) and app restarts.
///
/// Deliberately kept outside the observable `AppConfig`: folder toggles are
/// frequent UI events, and writing them into `ConfigManager.shared.config`
/// would invalidate every view that reads config (the same reasoning as
/// `ConfigManager.saveWindowFrame`). State is persisted to its own JSON file
/// in Application Support.
final class DirectoryTreeExpansionStore {
  /// Shared singleton instance.
  static let shared = DirectoryTreeExpansionStore()

  /// Expanded folder paths keyed by root directory path.
  private var expandedPathsByRoot: [String: Set<String>] = [:]

  /// URL of the JSON file backing the store.
  private let fileURL: URL

  /// Debounce timer for saving.
  private var saveTimer: Timer?
  private let saveDebounceInterval: TimeInterval = 0.5

  /// Default location: Application Support/SlothyTerminal/directory-tree-state.json.
  static var defaultFileURL: URL {
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
    else {
      /// Fallback to temporary directory if Application Support is unavailable.
      return FileManager.default.temporaryDirectory
        .appendingPathComponent("SlothyTerminal", isDirectory: true)
        .appendingPathComponent("directory-tree-state.json")
    }

    return appSupport
      .appendingPathComponent("SlothyTerminal", isDirectory: true)
      .appendingPathComponent("directory-tree-state.json")
  }

  init(fileURL: URL = DirectoryTreeExpansionStore.defaultFileURL) {
    self.fileURL = fileURL
    load()
  }

  /// Returns the remembered expanded folder paths for a root directory.
  func expandedPaths(forRoot rootPath: String) -> Set<String> {
    expandedPathsByRoot[rootPath] ?? []
  }

  /// Records the expansion state of a folder under the given root.
  ///
  /// Collapsing a folder removes only that folder's path; remembered
  /// descendant paths are kept so re-expanding the folder restores them.
  func setExpanded(_ isExpanded: Bool, path: String, rootPath: String) {
    var paths = expandedPathsByRoot[rootPath] ?? []

    if isExpanded {
      paths.insert(path)
    } else {
      paths.remove(path)
    }

    if paths.isEmpty {
      expandedPathsByRoot.removeValue(forKey: rootPath)
    } else {
      expandedPathsByRoot[rootPath] = paths
    }

    saveDebounced()
  }

  /// Writes the state to disk immediately, cancelling any pending
  /// debounced save. Used by tests and the app termination path.
  func saveNow() {
    saveTimer?.invalidate()
    saveTimer = nil

    let fileManager = FileManager.default
    let folder = fileURL.deletingLastPathComponent()

    do {
      if !fileManager.fileExists(atPath: folder.path) {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      }

      /// Sort paths for a stable, diff-friendly file.
      let snapshot = expandedPathsByRoot.mapValues { Array($0).sorted() }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(snapshot)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      Logger.app.error("Failed to save directory tree state: \(error.localizedDescription)")
    }
  }

  /// Loads persisted state from disk, leaving the store empty on any failure.
  private func load() {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return
    }

    do {
      let data = try Data(contentsOf: fileURL)
      let decoded = try JSONDecoder().decode([String: [String]].self, from: data)
      expandedPathsByRoot = decoded.mapValues(Set.init)
    } catch {
      Logger.app.error("Failed to load directory tree state: \(error.localizedDescription)")
    }
  }

  /// Saves the state after a short debounce delay.
  private func saveDebounced() {
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { [weak self] _ in
      self?.saveNow()
    }
  }
}
