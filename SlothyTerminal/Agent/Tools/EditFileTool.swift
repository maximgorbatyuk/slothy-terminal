import Foundation

/// Performs exact string replacement in a file.
///
/// Replaces `old_string` with `new_string`. The old string must appear
/// exactly once in the file (uniqueness check) unless `replace_all` is set.
struct EditFileTool: AgentTool {
  let id = "edit"

  let toolDescription = """
    Perform an exact string replacement in a file. \
    The old_string must be unique in the file unless replace_all is true.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "file_path": .init(
        type: "string",
        description: "Absolute path to the file to edit",
        enumValues: nil
      ),
      "old_string": .init(
        type: "string",
        description: "The exact text to replace",
        enumValues: nil
      ),
      "new_string": .init(
        type: "string",
        description: "The replacement text",
        enumValues: nil
      ),
      "replace_all": .init(
        type: "boolean",
        description: "Replace all occurrences (default: false)",
        enumValues: nil
      ),
    ],
    required: ["file_path", "old_string", "new_string"]
  )

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let path) = arguments["file_path"] else {
      return ToolResult(output: "Error: file_path is required", isError: true)
    }

    guard case .string(let oldString) = arguments["old_string"] else {
      return ToolResult(output: "Error: old_string is required", isError: true)
    }

    guard case .string(let newString) = arguments["new_string"] else {
      return ToolResult(output: "Error: new_string is required", isError: true)
    }

    let replaceAll: Bool
    if case .bool(let flag) = arguments["replace_all"] {
      replaceAll = flag
    } else {
      replaceAll = false
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

    guard oldString != newString else {
      return ToolResult(
        output: "Error: old_string and new_string are identical",
        isError: true
      )
    }

    let occurrences = content.components(separatedBy: oldString).count - 1

    guard occurrences > 0 else {
      return ToolResult(
        output: "Error: old_string not found in file",
        isError: true
      )
    }

    if !replaceAll,
       occurrences > 1
    {
      return ToolResult(
        output: "Error: old_string appears \(occurrences) times. "
          + "Use replace_all: true or provide more context to make it unique.",
        isError: true
      )
    }

    let updated: String
    if replaceAll {
      updated = content.replacingOccurrences(of: oldString, with: newString)
    } else {
      guard let range = content.range(of: oldString) else {
        return ToolResult(output: "Error: old_string not found", isError: true)
      }
      updated = content.replacingCharacters(in: range, with: newString)
    }

    do {
      try updated.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      return ToolResult(
        output: "Error: Failed to write file: \(error.localizedDescription)",
        isError: true
      )
    }

    let replacedCount = replaceAll ? occurrences : 1
    return ToolResult(
      output: "Replaced \(replacedCount) occurrence(s) in \(path)"
    )
  }
}
