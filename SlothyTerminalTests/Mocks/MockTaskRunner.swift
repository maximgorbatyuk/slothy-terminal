import Foundation
@testable import SlothyTerminalLib

/// Mock runner with configurable results for orchestrator tests.
class MockTaskRunner: TaskRunner {
  var executeResult: TaskRunResult?
  var executeError: Error?

  private(set) var executeCalled = false
  private(set) var cancelCalled = false
  private(set) var executedTask: QueuedTask?

  func execute(task: QueuedTask, logCollector: TaskLogCollector) async throws -> TaskRunResult {
    executeCalled = true
    executedTask = task

    if let error = executeError {
      throw error
    }

    guard let result = executeResult else {
      throw TaskRunError.cancelled
    }

    return result
  }

  func cancel() {
    cancelCalled = true
  }
}
