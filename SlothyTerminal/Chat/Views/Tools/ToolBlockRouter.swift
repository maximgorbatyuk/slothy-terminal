import SwiftUI

/// Groups a tool_use block with its optional tool_result and routes
/// to a specialized view based on the tool name.
struct ToolBlockRouter: View {
  let name: String
  let input: String
  let resultContent: String?

  private var parsedInput: ToolInput {
    ToolInput.parse(name: name, jsonString: input)
  }

  var body: some View {
    switch parsedInput {
    case .bash(let command):
      BashToolView(command: command, output: resultContent)

    case .read(let path, _, _):
      FileToolView(action: "Read", filePath: path, content: resultContent)

    case .edit(let path, let old, let new):
      EditToolView(filePath: path, oldString: old, newString: new)

    case .write(let path, let content):
      FileToolView(action: "Write", filePath: path, content: content)

    case .glob(let pattern, _):
      SearchToolView(type: "Glob", pattern: pattern, results: resultContent)

    case .grep(let pattern, _, _):
      SearchToolView(type: "Grep", pattern: pattern, results: resultContent)

    case .generic(let name, let rawJSON):
      GenericToolView(name: name, input: rawJSON, output: resultContent)
    }
  }
}
