import Foundation

/// Permission decision for a tool execution rule.
enum PermissionAction: Sendable {
  /// Silently allow the tool execution.
  case allow

  /// Deny the tool execution.
  case deny

  /// Pause and prompt the user for a decision.
  case ask
}

/// User's reply when prompted for tool permission.
enum PermissionReply: Sendable {
  /// Allow for this session only.
  case once

  /// Persist as a permanent rule.
  case always

  /// Halt execution.
  case reject

  /// Reject with feedback message for the LLM.
  case corrected(String)
}

/// Errors thrown by the permission system.
enum PermissionError: Error, Sendable {
  case denied(tool: String, path: String?)
  case rejected(tool: String, path: String?)
  case corrected(tool: String, feedback: String)
}

/// Protocol for checking tool execution permissions.
///
/// Implementations wire up to the UI for user prompts when
/// the action is `.ask`. The rule-based implementation evaluates
/// rules top-to-bottom with first-match semantics.
protocol PermissionDelegate: Sendable {
  /// Check if a tool execution is allowed.
  ///
  /// For `ask` actions, this should pause and prompt the user.
  /// Throws `PermissionError.denied` if the tool is denied.
  func check(tool: String, path: String?) async throws -> PermissionReply
}
