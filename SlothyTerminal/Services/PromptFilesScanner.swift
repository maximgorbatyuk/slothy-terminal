import Foundation

/// Scans `<workspaceRoot>/docs/prompts/` recursively for `.md` / `.txt` files
/// and reads their contents on demand.
enum PromptFilesScanner {
  private static let supportedExtensions: Set<String> = ["md", "txt"]

  /// Asynchronously scans the prompts folder under `workspaceRoot`.
  static func scan(workspaceRoot: URL) async -> [PromptFile] {
    await Task.detached(priority: .userInitiated) {
      scanSync(workspaceRoot: workspaceRoot)
    }.value
  }

  /// Synchronous scan entry point. Internal for testability.
  static func scanSync(workspaceRoot: URL) -> [PromptFile] {
    let promptsDir = workspaceRoot
      .appendingPathComponent("docs", isDirectory: true)
      .appendingPathComponent("prompts", isDirectory: true)

    let fm = FileManager.default
    var isDir: ObjCBool = false

    guard fm.fileExists(atPath: promptsDir.path, isDirectory: &isDir), isDir.boolValue else {
      return []
    }

    let keys: [URLResourceKey] = [.isRegularFileKey]

    guard let enumerator = fm.enumerator(
      at: promptsDir,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var results: [PromptFile] = []

    for case let fileURL as URL in enumerator {
      let ext = fileURL.pathExtension.lowercased()

      guard supportedExtensions.contains(ext) else {
        continue
      }

      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
            values.isRegularFile == true
      else {
        continue
      }

      let relative = relativePath(from: promptsDir, to: fileURL)

      results.append(PromptFile(
        fileName: fileURL.lastPathComponent,
        url: fileURL,
        relativePath: relative,
        fileExtension: ext
      ))
    }

    return results.sorted {
      $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
    }
  }

  /// Reads the file contents as UTF-8, falling back to ISO Latin-1.
  static func readContent(of file: PromptFile) async -> String? {
    await Task.detached(priority: .userInitiated) {
      if let utf8 = try? String(contentsOf: file.url, encoding: .utf8) {
        return utf8
      }

      return try? String(contentsOf: file.url, encoding: .isoLatin1)
    }.value
  }

  /// Computes path of `target` relative to `base` (expected to be an ancestor directory).
  private static func relativePath(from base: URL, to target: URL) -> String {
    let baseParts = base.standardizedFileURL.pathComponents
    let targetParts = target.standardizedFileURL.pathComponents

    var commonLength = 0
    let minLength = min(baseParts.count, targetParts.count)
    while commonLength < minLength && baseParts[commonLength] == targetParts[commonLength] {
      commonLength += 1
    }

    let remaining = targetParts[commonLength...]
    return remaining.joined(separator: "/")
  }
}
