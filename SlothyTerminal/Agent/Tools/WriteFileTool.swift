import Foundation

/// Writes content to a file, creating intermediate directories if needed.
struct WriteFileTool: AgentTool {
  let id = "write"

  let toolDescription = """
    Write content to a file at the given path. \
    Creates intermediate directories if they don't exist. \
    Overwrites the file if it already exists.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "file_path": .init(
        type: "string",
        description: "Absolute path to the file to write",
        enumValues: nil
      ),
      "content": .init(
        type: "string",
        description: "The content to write to the file",
        enumValues: nil
      ),
    ],
    required: ["file_path", "content"]
  )

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let path) = arguments["file_path"] else {
      return ToolResult(output: "Error: file_path is required", isError: true)
    }

    guard case .string(let content) = arguments["content"] else {
      return ToolResult(output: "Error: content is required", isError: true)
    }

    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent()

    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    } catch {
      return ToolResult(
        output: "Error: Failed to create directory: \(error.localizedDescription)",
        isError: true
      )
    }

    do {
      try content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      return ToolResult(
        output: "Error: Failed to write file: \(error.localizedDescription)",
        isError: true
      )
    }

    let lineCount = content.components(separatedBy: "\n").count
    return ToolResult(output: "Wrote \(lineCount) lines to \(path)")
  }
}
