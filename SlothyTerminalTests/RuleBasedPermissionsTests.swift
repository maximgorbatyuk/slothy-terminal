import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("RuleBasedPermissions")
struct RuleBasedPermissionsTests {

  // MARK: - Allow rules

  @Test("Allow rule returns .once")
  func allowRule() async throws {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "bash", action: .allow)
      ],
      fallbackHandler: { _, _ in .reject }
    )

    let reply = try await perms.check(tool: "bash", path: nil)
    #expect(reply == .once)
  }

  @Test("Wildcard allow matches any tool")
  func wildcardAllow() async throws {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "*", action: .allow)
      ],
      fallbackHandler: { _, _ in .reject }
    )

    let reply = try await perms.check(tool: "anything", path: nil)
    #expect(reply == .once)
  }

  // MARK: - Deny rules

  @Test("Deny rule throws PermissionError.denied")
  func denyRule() async {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "bash", action: .deny)
      ],
      fallbackHandler: { _, _ in .once }
    )

    do {
      _ = try await perms.check(tool: "bash", path: nil)
      Issue.record("Expected PermissionError.denied")
    } catch let error as PermissionError {
      if case .denied(let tool, _) = error {
        #expect(tool == "bash")
      } else {
        Issue.record("Expected .denied, got \(error)")
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  // MARK: - Ask rules

  @Test("Ask rule invokes fallback handler")
  func askRule() async throws {
    var handlerCalled = false
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "edit", action: .ask)
      ],
      fallbackHandler: { tool, _ in
        handlerCalled = true
        return .always
      }
    )

    let reply = try await perms.check(tool: "edit", path: nil)
    #expect(handlerCalled)
    #expect(reply == .always)
  }

  // MARK: - Edit tool normalization

  @Test("Write tool normalizes to edit permission key")
  func writeNormalizesToEdit() async throws {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "edit", action: .allow)
      ],
      fallbackHandler: { _, _ in .reject }
    )

    let reply = try await perms.check(tool: "write", path: nil)
    #expect(reply == .once)
  }

  @Test("Patch tool normalizes to edit permission key")
  func patchNormalizesToEdit() async throws {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "edit", action: .allow)
      ],
      fallbackHandler: { _, _ in .reject }
    )

    let reply = try await perms.check(tool: "patch", path: nil)
    #expect(reply == .once)
  }

  // MARK: - Path patterns

  @Test("Path pattern restricts match to matching paths")
  func pathPatternMatch() async throws {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "bash", pathPattern: "/tmp/*", action: .allow)
      ],
      fallbackHandler: { _, _ in .reject }
    )

    let reply = try await perms.check(tool: "bash", path: "/tmp/test.sh")
    #expect(reply == .once)
  }

  @Test("Path pattern does not match different directory")
  func pathPatternNoMatch() async throws {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "bash", pathPattern: "/tmp/*", action: .allow)
      ],
      fallbackHandler: { _, _ in .reject }
    )

    let reply = try await perms.check(tool: "bash", path: "/etc/passwd")
    #expect(reply == .reject)
  }

  // MARK: - First-match semantics

  @Test("First matching rule wins")
  func firstMatchWins() async throws {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "bash", action: .allow),
        .init(toolPattern: "*", action: .deny),
      ],
      fallbackHandler: { _, _ in .reject }
    )

    let reply = try await perms.check(tool: "bash", path: nil)
    #expect(reply == .once)
  }

  // MARK: - Fallback

  @Test("No matching rule invokes fallback handler")
  func noMatchFallback() async throws {
    var fallbackTool: String?
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "bash", action: .allow)
      ],
      fallbackHandler: { tool, _ in
        fallbackTool = tool
        return .once
      }
    )

    let reply = try await perms.check(tool: "glob", path: nil)
    #expect(reply == .once)
    #expect(fallbackTool == "glob")
  }

  // MARK: - Suffix wildcard

  @Test("Suffix wildcard matches prefix")
  func suffixWildcard() async throws {
    let perms = RuleBasedPermissions(
      rules: [
        .init(toolPattern: "bash*", action: .allow)
      ],
      fallbackHandler: { _, _ in .reject }
    )

    let reply = try await perms.check(tool: "bash_extended", path: nil)
    #expect(reply == .once)
  }
}

// MARK: - PermissionReply Equatable

extension PermissionReply: @retroactive Equatable {
  public static func == (lhs: PermissionReply, rhs: PermissionReply) -> Bool {
    switch (lhs, rhs) {
    case (.once, .once):
      return true

    case (.always, .always):
      return true

    case (.reject, .reject):
      return true

    case (.corrected(let a), .corrected(let b)):
      return a == b

    default:
      return false
    }
  }
}
