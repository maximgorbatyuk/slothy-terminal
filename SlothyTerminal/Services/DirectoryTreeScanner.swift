import Foundation

struct DirectoryTreeEntry: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let url: URL
  let isDirectory: Bool
}

enum DirectoryTreeScanner {
  static func scan(
    directory: URL,
    showHidden: Bool = true,
    maxVisibleItems: Int = 100
  ) async -> [DirectoryTreeEntry] {
    let scanTask = Task.detached(priority: .userInitiated) {
      scanSync(
        directory: directory,
        showHidden: showHidden,
        maxVisibleItems: maxVisibleItems
      )
    }

    return await withTaskCancellationHandler {
      await scanTask.value
    } onCancel: {
      scanTask.cancel()
    }
  }

  static func scanSync(
    directory: URL,
    showHidden: Bool = true,
    maxVisibleItems: Int = 100
  ) -> [DirectoryTreeEntry] {
    guard directory.hasDirectoryPath || isDirectory(directory) else {
      return []
    }

    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
        options: showHidden ? [] : [.skipsHiddenFiles]
      )

      var entries: [DirectoryTreeEntry] = []
      entries.reserveCapacity(contents.count)

      for itemURL in contents {
        if Task.isCancelled {
          return []
        }

        if let entry = makeEntry(from: itemURL) {
          entries.append(entry)
        }
      }

      if Task.isCancelled {
        return []
      }

      entries.sort(by: sortEntries)

      guard entries.count > maxVisibleItems else {
        return entries
      }

      return Array(entries.prefix(maxVisibleItems))
    } catch {
      return []
    }
  }

  private static func makeEntry(from url: URL) -> DirectoryTreeEntry? {
    let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
    let name = resourceValues?.name ?? url.lastPathComponent

    guard !name.isEmpty else {
      return nil
    }

    return DirectoryTreeEntry(
      id: url.path,
      name: name,
      url: url,
      isDirectory: resourceValues?.isDirectory ?? isDirectory(url)
    )
  }

  private static func isDirectory(_ url: URL) -> Bool {
    var isDirectoryFlag: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectoryFlag)
    return isDirectoryFlag.boolValue
  }

  private static func sortEntries(_ lhs: DirectoryTreeEntry, _ rhs: DirectoryTreeEntry) -> Bool {
    if lhs.isDirectory == rhs.isDirectory {
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    return lhs.isDirectory && !rhs.isDirectory
  }
}
