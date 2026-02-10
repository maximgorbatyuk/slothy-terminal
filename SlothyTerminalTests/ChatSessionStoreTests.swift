import XCTest
@testable import SlothyTerminalLib

final class ChatSessionStoreTests: XCTestCase {
  private var store: ChatSessionStore!
  private var tempDirectory: URL!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SlothyTerminalTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: tempDirectory,
      withIntermediateDirectories: true
    )
    store = ChatSessionStore(baseDirectory: tempDirectory)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    store = nil
    tempDirectory = nil
    super.tearDown()
  }

  // MARK: - Roundtrip

  func testSaveAndLoadRoundtrip() {
    let snapshot = makeSnapshot(
      sessionId: "session-1",
      workingDirectory: "/Users/test/project",
      messages: [
        SerializedMessage(
          id: UUID(),
          role: "user",
          contentBlocks: [.text("Hello")],
          timestamp: Date(),
          inputTokens: 0,
          outputTokens: 0
        ),
        SerializedMessage(
          id: UUID(),
          role: "assistant",
          contentBlocks: [
            .thinking("Let me help"),
            .text("Hi there!"),
            .toolUse(id: "t1", name: "Bash", input: "{\"command\":\"ls\"}"),
            .toolResult(toolUseId: "t1", content: "file.txt"),
          ],
          timestamp: Date(),
          inputTokens: 100,
          outputTokens: 50
        ),
      ],
      totalInputTokens: 100,
      totalOutputTokens: 50
    )

    /// Save and immediately flush.
    store.save(snapshot: snapshot)
    store.saveImmediately()

    /// Load by working directory.
    let loaded = store.loadLatestSession(
      for: URL(fileURLWithPath: "/Users/test/project")
    )

    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.sessionId, "session-1")
    XCTAssertEqual(loaded?.workingDirectory, "/Users/test/project")
    XCTAssertEqual(loaded?.messages.count, 2)
    XCTAssertEqual(loaded?.totalInputTokens, 100)
    XCTAssertEqual(loaded?.totalOutputTokens, 50)

    /// Verify content blocks roundtrip.
    let assistantBlocks = loaded?.messages[1].contentBlocks ?? []
    XCTAssertEqual(assistantBlocks.count, 4)
    XCTAssertEqual(assistantBlocks[0], .thinking("Let me help"))
    XCTAssertEqual(assistantBlocks[1], .text("Hi there!"))
    XCTAssertEqual(assistantBlocks[2], .toolUse(id: "t1", name: "Bash", input: "{\"command\":\"ls\"}"))
    XCTAssertEqual(assistantBlocks[3], .toolResult(toolUseId: "t1", content: "file.txt"))
  }

  // MARK: - Nonexistent Session

  func testLoadNonexistentSession() {
    let result = store.loadLatestSession(
      for: URL(fileURLWithPath: "/nonexistent/path")
    )

    XCTAssertNil(result)
  }

  func testLoadNonexistentSessionById() {
    let result = store.loadSnapshot(sessionId: "does-not-exist")

    XCTAssertNil(result)
  }

  // MARK: - Delete

  func testDeleteSession() {
    let snapshot = makeSnapshot(
      sessionId: "session-to-delete",
      workingDirectory: "/Users/test/delete-me"
    )

    store.save(snapshot: snapshot)
    store.saveImmediately()

    /// Verify it's saved.
    XCTAssertNotNil(store.loadSnapshot(sessionId: "session-to-delete"))

    /// Delete it.
    store.deleteSession(sessionId: "session-to-delete")

    /// Verify it's gone.
    XCTAssertNil(store.loadSnapshot(sessionId: "session-to-delete"))
    XCTAssertNil(store.loadLatestSession(
      for: URL(fileURLWithPath: "/Users/test/delete-me")
    ))
  }

  // MARK: - Helpers

  private func makeSnapshot(
    sessionId: String,
    workingDirectory: String,
    messages: [SerializedMessage] = [],
    totalInputTokens: Int = 0,
    totalOutputTokens: Int = 0
  ) -> ChatSessionSnapshot {
    ChatSessionSnapshot(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
      messages: messages,
      totalInputTokens: totalInputTokens,
      totalOutputTokens: totalOutputTokens,
      savedAt: Date()
    )
  }
}
