import XCTest
@testable import SlothyTerminalLib

final class TelegramBotModelsTests: XCTestCase {

  // MARK: - TelegramBotMode

  func testBotModeDisplayNames() {
    XCTAssertEqual(TelegramBotMode.stopped.displayName, "Stopped")
    XCTAssertEqual(TelegramBotMode.execute.displayName, "Execute")
    XCTAssertEqual(TelegramBotMode.passive.displayName, "Listen Only")
  }

  func testBotModeCodable() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    for mode in TelegramBotMode.allCases {
      let data = try encoder.encode(mode)
      let decoded = try decoder.decode(TelegramBotMode.self, from: data)
      XCTAssertEqual(decoded, mode)
    }
  }

  // MARK: - TelegramBotStatus

  func testStatusDisplayNames() {
    XCTAssertEqual(TelegramBotStatus.idle.displayName, "Idle")
    XCTAssertEqual(TelegramBotStatus.running.displayName, "Running")
    XCTAssertEqual(TelegramBotStatus.error("test").displayName, "Error: test")
  }

  func testStatusEquatable() {
    XCTAssertEqual(TelegramBotStatus.idle, TelegramBotStatus.idle)
    XCTAssertEqual(TelegramBotStatus.running, TelegramBotStatus.running)
    XCTAssertNotEqual(TelegramBotStatus.idle, TelegramBotStatus.running)
    XCTAssertEqual(TelegramBotStatus.error("a"), TelegramBotStatus.error("a"))
    XCTAssertNotEqual(TelegramBotStatus.error("a"), TelegramBotStatus.error("b"))
  }

  // MARK: - TelegramBotStats

  func testStatsDefaults() {
    let stats = TelegramBotStats()

    XCTAssertEqual(stats.received, 0)
    XCTAssertEqual(stats.ignored, 0)
    XCTAssertEqual(stats.executed, 0)
    XCTAssertEqual(stats.failed, 0)
  }

  // MARK: - TelegramBotEvent

  func testEventInit() {
    let event = TelegramBotEvent(level: .warning, message: "test warning")

    XCTAssertEqual(event.level, .warning)
    XCTAssertEqual(event.message, "test warning")
    XCTAssertNotNil(event.id)
    XCTAssertNotNil(event.timestamp)
  }

  // MARK: - TelegramTimelineMessage

  func testTimelineMessageDirections() {
    let inbound = TelegramTimelineMessage(direction: .inbound, text: "hi")
    let outbound = TelegramTimelineMessage(direction: .outbound, text: "reply")
    let system = TelegramTimelineMessage(direction: .system, text: "started")

    XCTAssertFalse(inbound.isSystemMessage)
    XCTAssertFalse(outbound.isSystemMessage)
    XCTAssertTrue(system.isSystemMessage)
  }

  // MARK: - TelegramInteractionState

  func testInteractionStateEquatable() {
    XCTAssertEqual(TelegramInteractionState.idle, TelegramInteractionState.idle)
    XCTAssertEqual(TelegramInteractionState.awaitingNewTaskText, TelegramInteractionState.awaitingNewTaskText)
    XCTAssertEqual(
      TelegramInteractionState.awaitingNewTaskSchedule(taskText: "abc"),
      TelegramInteractionState.awaitingNewTaskSchedule(taskText: "abc")
    )
    XCTAssertNotEqual(
      TelegramInteractionState.awaitingNewTaskSchedule(taskText: "abc"),
      TelegramInteractionState.awaitingNewTaskSchedule(taskText: "xyz")
    )
  }

  func testInteractionStateNotEqualAcrossCases() {
    XCTAssertNotEqual(TelegramInteractionState.idle, TelegramInteractionState.awaitingNewTaskText)
    XCTAssertNotEqual(
      TelegramInteractionState.awaitingNewTaskText,
      TelegramInteractionState.awaitingNewTaskSchedule(taskText: "")
    )
  }

  // MARK: - TelegramBotStats Mutation

  func testStatsMutation() {
    var stats = TelegramBotStats()
    stats.received = 10
    stats.ignored = 3
    stats.executed = 5
    stats.failed = 2

    XCTAssertEqual(stats.received, 10)
    XCTAssertEqual(stats.ignored, 3)
    XCTAssertEqual(stats.executed, 5)
    XCTAssertEqual(stats.failed, 2)
  }

  // MARK: - TelegramBotMode Raw Values

  func testBotModeRawValues() {
    XCTAssertEqual(TelegramBotMode.stopped.rawValue, "stopped")
    XCTAssertEqual(TelegramBotMode.execute.rawValue, "execute")
    XCTAssertEqual(TelegramBotMode.passive.rawValue, "passive")
  }

  func testBotModeAllCases() {
    XCTAssertEqual(TelegramBotMode.allCases.count, 3)
    XCTAssertTrue(TelegramBotMode.allCases.contains(.stopped))
    XCTAssertTrue(TelegramBotMode.allCases.contains(.execute))
    XCTAssertTrue(TelegramBotMode.allCases.contains(.passive))
  }

  // MARK: - TelegramEventLevel

  func testEventLevelRawValues() {
    XCTAssertEqual(TelegramEventLevel.info.rawValue, "info")
    XCTAssertEqual(TelegramEventLevel.warning.rawValue, "warning")
    XCTAssertEqual(TelegramEventLevel.error.rawValue, "error")
  }

  func testEventLevelCodable() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    for level in [TelegramEventLevel.info, .warning, .error] {
      let data = try encoder.encode(level)
      let decoded = try decoder.decode(TelegramEventLevel.self, from: data)
      XCTAssertEqual(decoded, level)
    }
  }

  // MARK: - TelegramBotEvent Custom ID/Timestamp

  func testEventCustomIdAndTimestamp() {
    let fixedId = UUID()
    let fixedDate = Date(timeIntervalSince1970: 0)
    let event = TelegramBotEvent(
      id: fixedId,
      timestamp: fixedDate,
      level: .error,
      message: "custom event"
    )

    XCTAssertEqual(event.id, fixedId)
    XCTAssertEqual(event.timestamp, fixedDate)
    XCTAssertEqual(event.level, .error)
    XCTAssertEqual(event.message, "custom event")
  }

  // MARK: - TelegramTimelineMessage Custom ID/Timestamp

  func testTimelineMessageCustomInit() {
    let fixedId = UUID()
    let fixedDate = Date(timeIntervalSince1970: 1000)
    let message = TelegramTimelineMessage(
      id: fixedId,
      timestamp: fixedDate,
      direction: .outbound,
      text: "response"
    )

    XCTAssertEqual(message.id, fixedId)
    XCTAssertEqual(message.timestamp, fixedDate)
    XCTAssertEqual(message.direction, .outbound)
    XCTAssertEqual(message.text, "response")
    XCTAssertFalse(message.isSystemMessage)
  }

  // MARK: - TelegramDirectoryResult

  func testDirectoryResultSuccess() {
    let url = URL(fileURLWithPath: "/tmp")
    let result = TelegramDirectoryResult.success(url)

    if case .success(let resolved) = result {
      XCTAssertEqual(resolved.path, "/tmp")
    } else {
      XCTFail("Expected success")
    }
  }

  func testDirectoryResultFailure() {
    let result = TelegramDirectoryResult.failure("not found")

    if case .failure(let msg) = result {
      XCTAssertEqual(msg, "not found")
    } else {
      XCTFail("Expected failure")
    }
  }

  // MARK: - TelegramCommand Equatable

  func testCommandEquatable() {
    XCTAssertEqual(TelegramCommand.help, TelegramCommand.help)
    XCTAssertEqual(TelegramCommand.report, TelegramCommand.report)
    XCTAssertEqual(TelegramCommand.openDirectory, TelegramCommand.openDirectory)
    XCTAssertEqual(TelegramCommand.newTask, TelegramCommand.newTask)
    XCTAssertEqual(TelegramCommand.unknown("/foo"), TelegramCommand.unknown("/foo"))
    XCTAssertNotEqual(TelegramCommand.unknown("/foo"), TelegramCommand.unknown("/bar"))
    XCTAssertNotEqual(TelegramCommand.help, TelegramCommand.report)
  }
}
