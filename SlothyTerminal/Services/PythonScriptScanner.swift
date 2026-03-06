import Foundation

/// The kind of executable script.
enum ScriptKind: String {
  case python
  case shell

  /// File extensions matched by this kind.
  static func from(extension ext: String) -> ScriptKind? {
    switch ext {
    case "py":
      return .python

    case "sh":
      return .shell

    default:
      return nil
    }
  }

  /// SF Symbols icon name for display.
  var iconName: String {
    switch self {
    case .python:
      return "doc.text"

    case .shell:
      return "terminal"
    }
  }

  /// Short label for the script kind.
  var displayName: String {
    switch self {
    case .python:
      return "Python"

    case .shell:
      return "Shell"
    }
  }

  /// Builds the shell command string to execute this script kind.
  func executionCommand(escapedPath: String) -> String {
    switch self {
    case .python:
      return "python3 \(escapedPath)"

    case .shell:
      return "/bin/sh \(escapedPath)"
    }
  }
}

/// A discovered script with metadata.
struct ScriptItem: Identifiable {
  var id: URL { url }

  let name: String
  let url: URL
  let lineCount: Int
  let kind: ScriptKind
}

/// Scans a directory for executable script files (.py, .sh).
final class ScriptScanner {
  static let shared = ScriptScanner()

  /// Directories to skip during scan.
  /// Dot-prefixed dirs (.git, .venv, .mypy_cache, etc.) are already
  /// excluded by the .skipsHiddenFiles enumerator option.
  private static let skippedDirectories: Set<String> = [
    "node_modules", "__pycache__", "venv", "env",
    "build", "dist",
  ]

  private init() {}

  /// Scans the project root (shallow) and `scripts/` subfolder (recursive)
  /// for script files and returns them sorted by name.
  func scan(directory: URL) async -> [ScriptItem] {
    await Task.detached(priority: .userInitiated) {
      self.scanSync(directory: directory)
    }.value
  }

  /// Synchronous scan entry point. Internal for testability.
  func scanSync(directory: URL) -> [ScriptItem] {
    var results: [ScriptItem] = []

    /// 1. Shallow scan of the project root.
    results.append(contentsOf: scanShallow(directory: directory))

    /// 2. Recursive scan of the scripts/ subfolder.
    let scriptsDir = directory.appendingPathComponent("scripts")
    if FileManager.default.fileExists(atPath: scriptsDir.path) {
      results.append(contentsOf: scanRecursive(directory: scriptsDir))
    }

    return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Finds script files directly inside `directory` (no recursion).
  private func scanShallow(directory: URL) -> [ScriptItem] {
    let fm = FileManager.default

    guard let contents = try? fm.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return contents.compactMap { fileURL in
      makeScriptItem(from: fileURL)
    }
  }

  /// Finds script files recursively inside `directory`.
  private func scanRecursive(directory: URL) -> [ScriptItem] {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey]

    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var results: [ScriptItem] = []

    for case let fileURL as URL in enumerator {
      if Self.skippedDirectories.contains(fileURL.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }

      if let item = makeScriptItem(from: fileURL) {
        results.append(item)
      }
    }

    return results
  }

  private func makeScriptItem(from fileURL: URL) -> ScriptItem? {
    guard let kind = ScriptKind.from(extension: fileURL.pathExtension) else {
      return nil
    }

    guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
          values.isRegularFile == true
    else {
      return nil
    }

    return ScriptItem(
      name: fileURL.lastPathComponent,
      url: fileURL,
      lineCount: Self.countLines(at: fileURL),
      kind: kind
    )
  }

  static func countLines(at url: URL) -> Int {
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
