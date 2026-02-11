import Foundation
import OSLog

/// Accumulates timestamped log lines during task execution and writes
/// them to a per-attempt artifact file on disk.
///
/// Enforces a 5MB cap — once exceeded, further lines are discarded and
/// a truncation marker is appended on `flush()`.
class TaskLogCollector {
  /// Maximum log size in bytes before truncation.
  static let maxLogSize = 5 * 1024 * 1024

  private let taskId: UUID
  private let attemptId: UUID
  private var lines: [String] = []
  private var currentSize = 0
  private var truncated = false

  private static let timestampFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss.SSS"
    fmt.locale = Locale(identifier: "en_US_POSIX")
    return fmt
  }()

  init(taskId: UUID, attemptId: UUID) {
    self.taskId = taskId
    self.attemptId = attemptId
  }

  /// Appends a timestamped log line.
  func append(_ text: String) {
    guard !truncated else {
      return
    }

    let timestamp = Self.timestampFormatter.string(from: Date())
    let line = "[\(timestamp)] \(text)"
    let lineSize = line.utf8.count + 1

    if currentSize + lineSize > Self.maxLogSize {
      truncated = true
      return
    }

    lines.append(line)
    currentSize += lineSize
  }

  /// Writes accumulated log lines to disk and returns the file path.
  ///
  /// Returns `nil` if the log is empty or writing fails.
  func flush() -> String? {
    if truncated {
      lines.append("[LOG TRUNCATED — 5MB limit reached]")
    }

    guard !lines.isEmpty else {
      return nil
    }

    let logsDir = Self.logsDirectory
    do {
      try FileManager.default.createDirectory(
        at: logsDir,
        withIntermediateDirectories: true
      )
    } catch {
      Logger.taskQueue.error("Failed to create task logs directory: \(error.localizedDescription)")
      return nil
    }

    let filename = "\(taskId.uuidString)-\(attemptId.uuidString).log"
    let fileURL = logsDir.appendingPathComponent(filename)
    let content = lines.joined(separator: "\n")

    do {
      try content.write(to: fileURL, atomically: true, encoding: .utf8)
      Logger.taskQueue.info("Wrote task log (\(self.lines.count) lines) to \(fileURL.path)")
      return fileURL.path
    } catch {
      Logger.taskQueue.error("Failed to write task log: \(error.localizedDescription)")
      return nil
    }
  }

  // MARK: - Private

  private static var logsDirectory: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!

    return appSupport
      .appendingPathComponent("SlothyTerminal")
      .appendingPathComponent("tasks")
      .appendingPathComponent("logs")
  }
}
