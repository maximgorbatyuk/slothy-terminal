import Foundation

/// Rule-based permission checker.
///
/// Evaluates rules top-to-bottom with first-match semantics.
/// Edit/write/patch tools are normalized to a single "edit" permission key.
/// If no rule matches, falls through to the async user prompt handler.
struct RuleBasedPermissions: PermissionDelegate, Sendable {

  /// A single permission rule.
  struct Rule: Sendable {
    /// Wildcard pattern for tool name (e.g. "edit", "bash", "*").
    let toolPattern: String

    /// Optional wildcard pattern for file path (e.g. "/tmp/*").
    let pathPattern: String?

    /// Action to take when this rule matches.
    let action: PermissionAction

    init(
      toolPattern: String,
      pathPattern: String? = nil,
      action: PermissionAction
    ) {
      self.toolPattern = toolPattern
      self.pathPattern = pathPattern
      self.action = action
    }
  }

  /// Tool IDs that normalize to the "edit" permission key.
  private static let editToolIDs: Set<String> = [
    "edit", "write", "patch", "multiedit"
  ]

  private let rules: [Rule]
  private let fallbackHandler: @Sendable (String, String?) async -> PermissionReply

  init(
    rules: [Rule],
    fallbackHandler: @escaping @Sendable (String, String?) async -> PermissionReply
  ) {
    self.rules = rules
    self.fallbackHandler = fallbackHandler
  }

  func check(tool: String, path: String?) async throws -> PermissionReply {
    /// Normalize edit-family tools to a single key.
    let permKey = Self.editToolIDs.contains(tool) ? "edit" : tool

    for rule in rules {
      guard matches(pattern: rule.toolPattern, value: permKey) else {
        continue
      }

      if let pathPattern = rule.pathPattern,
         let path
      {
        guard matches(pattern: pathPattern, value: path) else {
          continue
        }
      }

      switch rule.action {
      case .allow:
        return .once

      case .deny:
        throw PermissionError.denied(tool: tool, path: path)

      case .ask:
        return await fallbackHandler(tool, path)
      }
    }

    /// No rule matched — ask the user.
    return await fallbackHandler(tool, path)
  }

  // MARK: - Pattern Matching

  /// Simple pattern matcher supporting exact match and suffix wildcard.
  private func matches(pattern: String, value: String) -> Bool {
    if pattern == "*" {
      return true
    }

    if pattern == value {
      return true
    }

    if pattern.hasSuffix("*") {
      let prefix = String(pattern.dropLast())
      return value.hasPrefix(prefix)
    }

    return false
  }
}
