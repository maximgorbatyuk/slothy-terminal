import Foundation
import OSLog

/// Task runner that wraps `ClaudeCLITransport` for headless execution.
///
/// Single-use: creates a transport, sends one prompt, waits for the terminal
/// `.result` event, and returns the result. The transport is terminated after.
class ClaudeTaskRunner: TaskRunner {
  private var transport: ClaudeCLITransport?
  private var isCancelled = false
  private var forceKillTask: Task<Void, Never>?

  private let workingDirectory: URL
  private let selectedModel: ChatModelSelection?

  init(workingDirectory: URL, selectedModel: ChatModelSelection?) {
    self.workingDirectory = workingDirectory
    self.selectedModel = selectedModel
  }

  func execute(task: QueuedTask, logCollector: TaskLogCollector) async throws -> TaskRunResult {
    guard !task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TaskRunError.promptEmpty
    }

    let transport = ClaudeCLITransport(
      workingDirectory: workingDirectory,
      resumeSessionId: nil,
      selectedModel: selectedModel
    )
    self.transport = transport

    logCollector.append("Starting Claude CLI transport")
    logCollector.append("Working directory: \(workingDirectory.path)")
    if let selectedModel {
      logCollector.append("Model: \(selectedModel.modelID)")
    }

    return try await withCheckedThrowingContinuation { continuation in
      var resumed = false
      var capturedSessionId: String?
      var riskyDetections: [String] = []
      var currentToolName: String?
      var currentToolInput = ""

      transport.start(
        onEvent: { [weak self] event in
          guard let self,
                !self.isCancelled
          else {
            return
          }

          self.logEvent(event, collector: logCollector)

          /// Track tool use for risky operation detection.
          switch event {
          case .contentBlockStart(_, let blockType, _, let name):
            if blockType == "tool_use" {
              currentToolName = name
              currentToolInput = ""
            }

          case .contentBlockDelta(_, let deltaType, let text):
            if deltaType == "input_json_delta" {
              currentToolInput += text
            }

          case .contentBlockStop:
            if let toolName = currentToolName {
              let detections = RiskyToolDetector.check(toolName: toolName, input: currentToolInput)
              for detection in detections {
                riskyDetections.append(detection.reason)
                logCollector.append("RISKY: \(detection.reason)")
              }
            }
            currentToolName = nil
            currentToolInput = ""

          default:
            break
          }

          if case .result(let text, _, _) = event {
            guard !resumed else {
              return
            }

            resumed = true
            transport.terminate()
            let logPath = logCollector.flush()

            continuation.resume(returning: TaskRunResult(
              exitReason: .completed,
              resultSummary: String(text.prefix(2000)),
              logArtifactPath: logPath,
              sessionId: capturedSessionId,
              failureKind: nil,
              errorMessage: nil,
              detectedRiskyOperations: riskyDetections
            ))
          }
        },
        onReady: { sessionId in
          capturedSessionId = sessionId
          logCollector.append("Transport ready, sessionId=\(sessionId)")
          logCollector.append("Sending prompt (\(task.prompt.count) chars)")
          transport.send(message: task.prompt)
        },
        onError: { error in
          logCollector.append("Transport error: \(error.localizedDescription)")

          guard !resumed else {
            return
          }

          resumed = true
          let logPath = logCollector.flush()

          continuation.resume(throwing: TaskRunError.transportNotAvailable(
            error.localizedDescription
          ))
          _ = logPath
        },
        onTerminated: { reason in
          logCollector.append("Transport terminated: \(reason)")

          guard !resumed else {
            return
          }

          resumed = true
          let logPath = logCollector.flush()

          switch reason {
          case .normal, .cancelled:
            /// Normal termination without a result means cancelled.
            continuation.resume(throwing: TaskRunError.cancelled)

          case .crash(let exitCode, let stderr):
            continuation.resume(throwing: TaskRunError.transportCrashed(
              exitCode: exitCode,
              stderr: stderr
            ))
          }

          _ = logPath
        }
      )
    }
  }

  func cancel() {
    guard !isCancelled else {
      return
    }

    isCancelled = true
    Logger.taskQueue.info("ClaudeTaskRunner: cancelling")

    transport?.interrupt()

    /// Force-kill after 10 seconds if still running.
    forceKillTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 10_000_000_000)

      guard !Task.isCancelled,
            let self,
            let transport = self.transport,
            transport.isRunning
      else {
        return
      }

      Logger.taskQueue.warning("ClaudeTaskRunner: force-killing after 10s")
      transport.terminate()
    }
  }

  // MARK: - Private

  private func logEvent(_ event: StreamEvent, collector: TaskLogCollector) {
    switch event {
    case .messageStart(let inputTokens):
      collector.append("messageStart (inputTokens=\(inputTokens))")

    case .contentBlockStart(let index, let blockType, _, let name):
      let nameStr = name.map { " name=\($0)" } ?? ""
      collector.append("contentBlockStart idx=\(index) type=\(blockType)\(nameStr)")

    case .contentBlockDelta(let index, let deltaType, let text):
      collector.append("delta idx=\(index) type=\(deltaType) len=\(text.count)")

    case .contentBlockStop(let index):
      collector.append("contentBlockStop idx=\(index)")

    case .messageDelta(let stopReason, let outputTokens):
      collector.append("messageDelta stop=\(stopReason ?? "nil") outputTokens=\(outputTokens)")

    case .messageStop:
      collector.append("messageStop")

    case .result(let text, let inputTokens, let outputTokens):
      collector.append("result (in=\(inputTokens), out=\(outputTokens), len=\(text.count))")

    case .system(let sessionId):
      collector.append("system sessionId=\(sessionId)")

    case .userToolResult(let toolUseId, _, let isError):
      collector.append("userToolResult id=\(toolUseId) isError=\(isError)")

    case .assistant(_, let inputTokens, let outputTokens):
      collector.append("assistant (in=\(inputTokens), out=\(outputTokens))")

    case .unknown:
      collector.append("unknown event")
    }
  }
}
