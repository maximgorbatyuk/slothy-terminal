import XCTest
@testable import SlothyTerminalLib

final class TelegramCommandHandlerTests: XCTestCase {

  // MARK: - Help Text

  func testHelpTextContainsCommands() {
    let help = TelegramCommandHandler.helpText()

    XCTAssertTrue(help.contains("/help"))
    XCTAssertTrue(help.contains("/report"))
    XCTAssertTrue(help.contains("/open-directory"))
    XCTAssertTrue(help.contains("/new-task"))
  }

  // MARK: - Open Directory Resolution

  func testResolveOpenDirectoryNoRoot() {
    let result = TelegramCommandHandler.resolveOpenDirectory(rootPath: nil, subpath: nil)

    if case .failure(let message) = result {
      XCTAssertTrue(message.contains("No root directory"))
    } else {
      XCTFail("Expected failure")
    }
  }

  func testResolveOpenDirectoryEmptyRoot() {
    let result = TelegramCommandHandler.resolveOpenDirectory(rootPath: "", subpath: nil)

    if case .failure(let message) = result {
      XCTAssertTrue(message.contains("No root directory"))
    } else {
      XCTFail("Expected failure")
    }
  }

  func testResolveOpenDirectoryValidPath() {
    /// Use /tmp which always exists.
    let result = TelegramCommandHandler.resolveOpenDirectory(rootPath: "/tmp", subpath: nil)

    if case .success(let url) = result {
      XCTAssertEqual(url.path, "/tmp")
    } else {
      XCTFail("Expected success, got \(result)")
    }
  }

  func testResolveOpenDirectoryWithSubpath() {
    /// Create a temp subdirectory.
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("telegram-test-\(UUID().uuidString)")
    let sub = root.appendingPathComponent("myrepo")

    try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let result = TelegramCommandHandler.resolveOpenDirectory(
      rootPath: root.path,
      subpath: "myrepo"
    )

    if case .success(let url) = result {
      XCTAssertTrue(url.path.hasSuffix("myrepo"))
    } else {
      XCTFail("Expected success, got \(result)")
    }
  }

  func testResolveOpenDirectoryNonexistent() {
    let result = TelegramCommandHandler.resolveOpenDirectory(
      rootPath: "/nonexistent-path-abc123",
      subpath: nil
    )

    if case .failure(let message) = result {
      XCTAssertTrue(message.contains("not found"))
    } else {
      XCTFail("Expected failure")
    }
  }

  func testResolveOpenDirectoryPathTraversal() {
    /// Create a temp root.
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("telegram-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let result = TelegramCommandHandler.resolveOpenDirectory(
      rootPath: root.path,
      subpath: "../../.."
    )

    if case .failure(let message) = result {
      XCTAssertTrue(message.contains("traversal") || message.contains("outside"))
    } else {
      XCTFail("Expected failure for path traversal")
    }
  }

  func testResolveOpenDirectorySiblingPrefixBlocked() {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("telegram-prefix-test-\(UUID().uuidString)")
    let root = base.appendingPathComponent("root")
    let sibling = base.appendingPathComponent("root2")

    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let result = TelegramCommandHandler.resolveOpenDirectory(
      rootPath: root.path,
      subpath: "../root2"
    )

    if case .failure(let message) = result {
      XCTAssertTrue(message.contains("outside root") || message.contains("traversal"))
    } else {
      XCTFail("Expected failure for sibling prefix traversal")
    }
  }
}
