import AppKit
import Foundation

/// Represents a file or directory item in the directory tree.
struct FileItem: Identifiable {
  /// Full path used as unique identifier.
  let id: String

  /// Display name of the file or directory.
  let name: String

  /// URL of the file or directory.
  let url: URL

  /// Whether this item is a directory.
  let isDirectory: Bool

  /// Whether this directory is expanded (only relevant for directories).
  var isExpanded: Bool = false

  /// Whether children are currently being loaded.
  var isLoadingChildren: Bool = false

  /// Whether child items have been loaded at least once.
  var didLoadChildren: Bool = false

  /// Monotonic token for invalidating stale child-load tasks.
  var childLoadGeneration: Int = 0

  /// Child items for expanded directories.
  var children: [FileItem] = []

  /// Cached file type icon.
  let icon: NSImage
}

/// Manages directory scanning and caching for the sidebar tree view.
final class DirectoryTreeManager {
  /// Shared singleton instance.
  static let shared = DirectoryTreeManager()
  private static let iconCache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 256
    return cache
  }()

  /// Maximum number of items to display to prevent performance issues.
  private let maxVisibleItems = 100

  private init() {}

  /// Loads the top-level items for a directory.
  func loadItems(in url: URL, showHidden: Bool = true) async -> [FileItem] {
    let entries = await DirectoryTreeScanner.scan(
      directory: url,
      showHidden: showHidden,
      maxVisibleItems: maxVisibleItems
    )

    guard !Task.isCancelled else {
      return []
    }

    return await MainActor.run {
      entries.map(Self.makeFileItem(from:))
    }
  }

  /// Loads children for a directory item.
  func loadChildren(in url: URL, showHidden: Bool = true) async -> [FileItem] {
    guard isDirectory(url) else {
      return []
    }

    return await loadItems(in: url, showHidden: showHidden)
  }

  /// Creates a FileItem from a scanned directory entry.
  @MainActor
  private static func makeFileItem(from entry: DirectoryTreeEntry) -> FileItem {
    return FileItem(
      id: entry.id,
      name: entry.name,
      url: entry.url,
      isDirectory: entry.isDirectory,
      icon: icon(for: entry.url, isDirectory: entry.isDirectory)
    )
  }

  @MainActor
  func icon(for url: URL) -> NSImage {
    Self.icon(for: url, isDirectory: isDirectory(url))
  }

  @MainActor
  func fileIcon(for url: URL) -> NSImage {
    Self.icon(for: url, isDirectory: false)
  }

  private func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
    return isDir.boolValue
  }

  @MainActor
  private static func icon(for url: URL, isDirectory: Bool) -> NSImage {
    let cacheKey = makeIconCacheKey(for: url, isDirectory: isDirectory)

    if let cached = iconCache.object(forKey: cacheKey as NSString) {
      return cached
    }

    let icon = NSWorkspace.shared.icon(forFile: url.path)
    iconCache.setObject(icon, forKey: cacheKey as NSString)

    return icon
  }

  private static func makeIconCacheKey(for url: URL, isDirectory: Bool) -> String {
    let kind = isDirectory ? "directory" : "file"
    return "\(kind):\(url.path)"
  }
}
