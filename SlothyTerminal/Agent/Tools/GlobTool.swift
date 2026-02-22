import Foundation

/// File pattern matching tool.
///
/// Supports simple glob patterns: `*` matches any sequence of characters
/// in a single path component, `**` matches across directories.
/// Returns matching file paths sorted by modification time (most recent first).
struct GlobTool: AgentTool {
  let id = "glob"

  let toolDescription = """
    Find files matching a glob pattern. \
    Supports * and ** wildcards. \
    Returns matching file paths sorted by modification time.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "pattern": .init(
        type: "string",
        description: "Glob pattern to match (e.g., \"**/*.swift\", \"src/**/*.ts\")",
        enumValues: nil
      ),
      "path": .init(
        type: "string",
        description: "Directory to search in (defaults to working directory)",
        enumValues: nil
      ),
    ],
    required: ["pattern"]
  )

  /// Maximum number of results to return.
  private let maxResults = 500

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let pattern) = arguments["pattern"] else {
      return ToolResult(output: "Error: pattern is required", isError: true)
    }

    let searchDir: URL
    if case .string(let path) = arguments["path"] {
      searchDir = URL(fileURLWithPath: path)
    } else {
      searchDir = context.workingDirectory
    }

    guard FileManager.default.fileExists(atPath: searchDir.path) else {
      return ToolResult(
        output: "Error: Directory not found: \(searchDir.path)",
        isError: true
      )
    }

    let fm = FileManager.default
    let enumerator = fm.enumerator(
      at: searchDir,
      includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )

    guard let enumerator else {
      return ToolResult(
        output: "Error: Unable to enumerate directory: \(searchDir.path)",
        isError: true
      )
    }

    var matches: [(path: String, modified: Date)] = []

    while let url = enumerator.nextObject() as? URL {
      let resourceValues = try? url.resourceValues(
        forKeys: [.isRegularFileKey, .contentModificationDateKey]
      )

      guard resourceValues?.isRegularFile == true else {
        continue
      }

      let relativePath = url.path.replacingOccurrences(
        of: searchDir.path + "/",
        with: ""
      )

      guard matchesGlob(pattern: pattern, path: relativePath) else {
        continue
      }

      let modified = resourceValues?.contentModificationDate ?? .distantPast
      matches.append((path: url.path, modified: modified))
    }

    matches.sort { $0.modified > $1.modified }

    if matches.isEmpty {
      return ToolResult(output: "No files matched pattern: \(pattern)")
    }

    let truncated = matches.count > maxResults
    let results = matches.prefix(maxResults)
    var output = results.map(\.path).joined(separator: "\n")

    if truncated {
      output += "\n... (\(matches.count - maxResults) more files not shown)"
    }

    return ToolResult(output: output)
  }

  // MARK: - Glob matching

  /// Simple glob matcher supporting `*` (single component) and `**` (recursive).
  private func matchesGlob(pattern: String, path: String) -> Bool {
    let patternParts = pattern.components(separatedBy: "/")
    let pathParts = path.components(separatedBy: "/")
    return matchParts(patternParts[...], pathParts[...])
  }

  private func matchParts(
    _ pattern: ArraySlice<String>,
    _ path: ArraySlice<String>
  ) -> Bool {
    guard let first = pattern.first else {
      return path.isEmpty
    }

    let rest = pattern.dropFirst()

    if first == "**" {
      /// `**` matches zero or more path components.
      if matchParts(rest, path) {
        return true
      }
      if let _ = path.first {
        return matchParts(pattern, path.dropFirst())
      }
      return false
    }

    guard let pathFirst = path.first else {
      return false
    }

    if matchWildcard(pattern: first, string: pathFirst) {
      return matchParts(rest, path.dropFirst())
    }

    return false
  }

  /// Matches `*` within a single path component.
  private func matchWildcard(pattern: String, string: String) -> Bool {
    if pattern == "*" {
      return true
    }

    if !pattern.contains("*") {
      return pattern == string
    }

    let parts = pattern.components(separatedBy: "*")

    guard parts.count == 2 else {
      /// Multiple wildcards — fall back to simple prefix/suffix check.
      let prefix = parts.first ?? ""
      let suffix = parts.last ?? ""
      return string.hasPrefix(prefix) && string.hasSuffix(suffix)
    }

    let prefix = parts[0]
    let suffix = parts[1]

    return string.hasPrefix(prefix)
      && string.hasSuffix(suffix)
      && string.count >= prefix.count + suffix.count
  }
}
