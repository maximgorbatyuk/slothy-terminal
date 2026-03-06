import Foundation

/// A discovered Python script with metadata.
struct PythonScriptItem: Identifiable {
  var id: URL { url }

  let name: String
  let url: URL
  let lineCount: Int
}

/// Scans a directory recursively for Python (.py) files.
final class PythonScriptScanner {
  static let shared = PythonScriptScanner()

  /// Directories to skip during scan.
  /// Dot-prefixed dirs (.git, .venv, .mypy_cache, etc.) are already
  /// excluded by the .skipsHiddenFiles enumerator option.
  private static let skippedDirectories: Set<String> = [
    "node_modules", "__pycache__", "venv", "env",
    "build", "dist",
  ]

  private init() {}

  /// Scans the project root (shallow) and `scripts/` subfolder (recursive)
  /// for .py files and returns them sorted by name.
  func scan(directory: URL) async -> [PythonScriptItem] {
    await Task.detached(priority: .userInitiated) {
      self.scanSync(directory: directory)
    }.value
  }

  private func scanSync(directory: URL) -> [PythonScriptItem] {
    var results: [PythonScriptItem] = []

    /// 1. Shallow scan of the project root.
    results.append(contentsOf: scanShallow(directory: directory))

    /// 2. Recursive scan of the scripts/ subfolder.
    let scriptsDir = directory.appendingPathComponent("scripts")
    if FileManager.default.fileExists(atPath: scriptsDir.path) {
      results.append(contentsOf: scanRecursive(directory: scriptsDir))
    }

    return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Finds .py files directly inside `directory` (no recursion).
  private func scanShallow(directory: URL) -> [PythonScriptItem] {
    let fm = FileManager.default

    guard let contents = try? fm.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return contents.compactMap { fileURL in
      guard fileURL.pathExtension == "py" else {
        return nil
      }

      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
            values.isRegularFile == true
      else {
        return nil
      }

      return PythonScriptItem(
        name: fileURL.lastPathComponent,
        url: fileURL,
        lineCount: Self.countLines(at: fileURL)
      )
    }
  }

  /// Finds .py files recursively inside `directory`.
  private func scanRecursive(directory: URL) -> [PythonScriptItem] {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey]

    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var results: [PythonScriptItem] = []

    for case let fileURL as URL in enumerator {
      if Self.skippedDirectories.contains(fileURL.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }

      guard fileURL.pathExtension == "py" else {
        continue
      }

      guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
            values.isRegularFile == true
      else {
        continue
      }

      results.append(PythonScriptItem(
        name: fileURL.lastPathComponent,
        url: fileURL,
        lineCount: Self.countLines(at: fileURL)
      ))
    }

    return results
  }

  private static func countLines(at url: URL) -> Int {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
      return 0
    }

    guard !data.isEmpty else {
      return 0
    }

    var count = 0
    data.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return
      }

      for i in 0..<buffer.count {
        if base[i] == 0x0A { // newline
          count += 1
        }
      }
    }

    /// If the last byte isn't a newline, count the trailing line.
    if let last = data.last, last != 0x0A {
      count += 1
    }

    return count
  }
}
