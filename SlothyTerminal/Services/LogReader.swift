import Foundation
import OSLog

/// Reads log entries that this process emitted via `os.Logger`, scoped to the
/// app's subsystem. Backs the Logs settings tab; no file or persistence of
/// our own — `OSLogStore` is the source of truth.
enum LogReader {
  /// A simplified, value-typed log entry suitable for SwiftUI display.
  struct Entry: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let level: Level
    let category: String
    let message: String
  }

  /// Levels supported by the viewer, ordered ascending in severity so that
  /// `>=` works for "minimum level" filtering.
  enum Level: Int, CaseIterable, Comparable, Sendable {
    case debug = 1
    case info = 2
    case notice = 3
    case error = 4
    case fault = 5

    var displayName: String {
      switch self {
      case .debug:
        return "Debug"

      case .info:
        return "Info"

      case .notice:
        return "Notice"

      case .error:
        return "Error"

      case .fault:
        return "Fault"
      }
    }

    static func < (lhs: Level, rhs: Level) -> Bool {
      lhs.rawValue < rhs.rawValue
    }

    fileprivate init(_ osLogLevel: OSLogEntryLog.Level) {
      switch osLogLevel {
      case .debug:
        self = .debug

      case .info:
        self = .info

      case .notice:
        self = .notice

      case .error:
        self = .error

      case .fault:
        self = .fault

      case .undefined:
        self = .notice

      @unknown default:
        self = .notice
      }
    }
  }

  /// Fetches log entries from the current process at or above `minLevel`,
  /// since the given date, restricted to this app's subsystem.
  static func fetch(minLevel: Level, since: Date) throws -> [Entry] {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let position = store.position(date: since)
    let subsystem = Bundle.main.bundleIdentifier ?? "com.slothyterminal.app"
    let predicate = NSPredicate(format: "subsystem == %@", subsystem)

    let raw = try store.getEntries(at: position, matching: predicate)

    var entries: [Entry] = []
    for case let log as OSLogEntryLog in raw {
      let level = Level(log.level)

      guard level >= minLevel else {
        continue
      }

      entries.append(
        Entry(
          id: UUID(),
          date: log.date,
          level: level,
          category: log.category,
          message: log.composedMessage
        )
      )
    }
    return entries
  }
}
