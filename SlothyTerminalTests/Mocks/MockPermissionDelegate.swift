import Foundation

@testable import SlothyTerminalLib

/// A mock permission delegate with configurable behavior.
///
/// Defaults to always allowing. Can be configured to deny specific tools
/// or return custom replies.
final class MockPermissionDelegate: PermissionDelegate, @unchecked Sendable {
  /// Custom handler. If nil, defaults to `.once`.
  var handler: (@Sendable (String, String?) async throws -> PermissionReply)?

  /// Tracks all check calls for assertions.
  private(set) var checkCalls: [(tool: String, path: String?)] = []

  init(
    handler: (@Sendable (String, String?) async throws -> PermissionReply)? = nil
  ) {
    self.handler = handler
  }

  func check(tool: String, path: String?) async throws -> PermissionReply {
    checkCalls.append((tool: tool, path: path))

    if let handler {
      return try await handler(tool, path)
    }

    return .once
  }
}
