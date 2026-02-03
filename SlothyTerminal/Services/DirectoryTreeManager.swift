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

  /// Child items (only populated for expanded directories).
  var children: [FileItem]? = nil

  /// System icon for this file type.
  var icon: NSImage {
    NSWorkspace.shared.icon(forFile: url.path)
  }
}

/// Manages directory scanning and caching for the sidebar tree view.
final class DirectoryTreeManager {
  /// Shared singleton instance.
  static let shared = DirectoryTreeManager()

  /// Maximum number of items to display to prevent performance issues.
  private let maxVisibleItems = 100

  private init() {}

  /// Scans a directory and returns its immediate children.
  /// - Parameters:
  ///   - url: The directory URL to scan.
  ///   - showHidden: Whether to include hidden files (starting with '.').
  /// - Returns: Array of FileItem representing the directory contents.
  func scanDirectory(_ url: URL, showHidden: Bool = true) -> [FileItem] {
    guard url.hasDirectoryPath || isDirectory(url) else {
      return []
    }

    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
        options: showHidden ? [] : [.skipsHiddenFiles]
      )

      var items = contents.compactMap { itemURL -> FileItem? in
        createFileItem(from: itemURL)
      }

      items = sortItems(items)

      if items.count > maxVisibleItems {
        items = Array(items.prefix(maxVisibleItems))
      }

      return items
    } catch {
      return []
    }
  }

  /// Loads children for a directory item.
  /// - Parameters:
  ///   - item: The directory item to load children for.
  ///   - showHidden: Whether to include hidden files.
  /// - Returns: Array of child FileItem objects.
  func loadChildren(for item: FileItem, showHidden: Bool = true) -> [FileItem] {
    guard item.isDirectory else {
      return []
    }

    return scanDirectory(item.url, showHidden: showHidden)
  }

  /// Creates a FileItem from a URL.
  private func createFileItem(from url: URL) -> FileItem? {
    let name = url.lastPathComponent

    guard !name.isEmpty else {
      return nil
    }

    let isDir = isDirectory(url)

    return FileItem(
      id: url.path,
      name: name,
      url: url,
      isDirectory: isDir
    )
  }

  /// Checks if a URL points to a directory.
  private func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
    return isDir.boolValue
  }

  /// Sorts items with directories first, then files, both alphabetically.
  private func sortItems(_ items: [FileItem]) -> [FileItem] {
    items.sorted { lhs, rhs in
      if lhs.isDirectory == rhs.isDirectory {
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      return lhs.isDirectory && !rhs.isDirectory
    }
  }
}
