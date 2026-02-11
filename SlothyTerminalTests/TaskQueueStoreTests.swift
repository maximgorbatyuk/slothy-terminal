import XCTest
@testable import SlothyTerminalLib

final class TaskQueueStoreTests: XCTestCase {
  private var store: TaskQueueStore!
  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TQStoreTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    store = TaskQueueStore(baseDirectory: tempDir)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    store = nil
    tempDir = nil
    super.tearDown()
  }

  // MARK: - Roundtrip

  func testSaveAndLoadRoundtrip() {
    let task = makeTask(title: "Test task", prompt: "Do something")
    let snapshot = TaskQueueSnapshot(tasks: [task])

    store.save(snapshot: snapshot)
    store.saveImmediately()

    let loaded = store.load()

    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.tasks.count, 1)
    XCTAssertEqual(loaded?.tasks[0].title, "Test task")
    XCTAssertEqual(loaded?.tasks[0].prompt, "Do something")
    XCTAssertEqual(loaded?.tasks[0].status, .pending)
  }

  // MARK: - Recovery

  func testRecoveryOfInterruptedTasks() {
    var task = makeTask(title: "Running task")
    task.status = .running
    task.startedAt = Date()
    task.runAttemptId = UUID()

    let snapshot = TaskQueueSnapshot(tasks: [task])
    store.save(snapshot: snapshot)
    store.saveImmediately()

    let loaded = store.load()

    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.tasks[0].status, .pending)
    XCTAssertNotNil(loaded?.tasks[0].interruptedNote)
    XCTAssertNil(loaded?.tasks[0].startedAt)
  }

  // MARK: - Empty

  func testEmptyLoadReturnsNil() {
    let loaded = store.load()
    XCTAssertNil(loaded)
  }

  // MARK: - Corrupt File

  func testCorruptFileReturnsNil() throws {
    let queueFile = tempDir.appendingPathComponent("queue.json")
    try "not valid json {{{".write(to: queueFile, atomically: true, encoding: .utf8)

    let loaded = store.load()
    XCTAssertNil(loaded)
  }

  // MARK: - Helpers

  private func makeTask(
    title: String = "Task",
    prompt: String = "prompt"
  ) -> QueuedTask {
    QueuedTask(
      id: UUID(),
      title: title,
      prompt: prompt,
      repoPath: "/tmp",
      agentType: .claude,
      status: .pending,
      priority: .normal,
      retryCount: 0,
      maxRetries: 3,
      createdAt: Date(),
      approvalState: .none
    )
  }
}
