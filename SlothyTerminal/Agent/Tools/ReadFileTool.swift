import Foundation

/// Reads the contents of a file with optional offset/limit.
///
/// Returns line-numbered output similar to `cat -n`. Supports
/// reading a specific range of lines for large files.
struct ReadFileTool: AgentTool {
  let id = "read"

  let toolDescription = """
    Read the contents of a file at the given path. \
    Returns the file content with line numbers.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "file_path": .init(
        type: "string",
        description: "Absolute path to the file to read",
        enumValues: nil
      ),
      "offset": .init(
        type: "integer",
        description: "Line number to start reading from (1-based, optional)",
        enumValues: nil
      ),
      "limit": .init(
        type: "integer",
        description: "Number of lines to read (optional, default: all)",
        enumValues: nil
      ),
    ],
    required: ["file_path"]
  )

  /// Maximum number of lines to return by default.
  private let defaultLimit = 2000

  /// Maximum characters per line before truncation.
  private let maxLineLength = 2000

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let path) = arguments["file_path"] else {
      return ToolResult(output: "Error: file_path is required", isError: true)
    }

    let url = URL(fileURLWithPath: path)

    guard FileManager.default.fileExists(atPath: url.path) else {
      return ToolResult(output: "Error: File not found: \(path)", isError: true)
    }

    let content: String
    do {
      content = try String(contentsOf: url, encoding: .utf8)
    } catch {
      return ToolResult(
        output: "Error: Unable to read file: \(error.localizedDescription)",
        isError: true
      )
    }

    let lines = content.components(separatedBy: "\n")

    var offset = 0
    if case .number(let n) = arguments["offset"] {
      offset = max(0, Int(n) - 1)
    }

    var limit = defaultLimit
    if case .number(let n) = arguments["limit"] {
      limit = Int(n)
    }

    let startIndex = min(offset, lines.count)
    let endIndex = min(offset + limit, lines.count)
    let slice = lines[startIndex..<endIndex]

    let numbered = slice.enumerated().map { index, line in
      let lineNum = offset + index + 1
      let truncated = line.count > maxLineLength
        ? String(line.prefix(maxLineLength)) + "..."
        : line
      return "\(lineNum)\t\(truncated)"
    }.joined(separator: "\n")

    return ToolResult(output: numbered)
  }
}
