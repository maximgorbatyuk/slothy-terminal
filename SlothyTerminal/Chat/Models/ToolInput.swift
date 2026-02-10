import Foundation

/// Parsed tool input for specialized rendering.
enum ToolInput {
  case bash(command: String)
  case read(filePath: String, offset: Int?, limit: Int?)
  case edit(filePath: String, oldString: String, newString: String)
  case write(filePath: String, content: String)
  case glob(pattern: String, path: String?)
  case grep(pattern: String, path: String?, glob: String?)
  case generic(name: String, rawJSON: String)

  /// Parse tool input JSON by tool name.
  static func parse(name: String, jsonString: String) -> ToolInput {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return .generic(name: name, rawJSON: jsonString)
    }

    switch name {
    case "Bash":
      return .bash(command: json["command"] as? String ?? jsonString)

    case "Read":
      return .read(
        filePath: json["file_path"] as? String ?? "",
        offset: json["offset"] as? Int,
        limit: json["limit"] as? Int
      )

    case "Edit":
      return .edit(
        filePath: json["file_path"] as? String ?? "",
        oldString: json["old_string"] as? String ?? "",
        newString: json["new_string"] as? String ?? ""
      )

    case "Write":
      return .write(
        filePath: json["file_path"] as? String ?? "",
        content: json["content"] as? String ?? ""
      )

    case "Glob":
      return .glob(
        pattern: json["pattern"] as? String ?? "",
        path: json["path"] as? String
      )

    case "Grep":
      return .grep(
        pattern: json["pattern"] as? String ?? "",
        path: json["path"] as? String,
        glob: json["glob"] as? String
      )

    default:
      return .generic(name: name, rawJSON: jsonString)
    }
  }
}
