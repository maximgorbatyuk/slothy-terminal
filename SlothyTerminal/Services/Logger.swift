import OSLog

/// Centralized logging using Apple's OSLog framework.
/// Logs appear in Console.app and can be filtered by subsystem and category.
extension Logger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.slothyterminal.app"

  /// Logger for PTY operations (spawn, read, write, terminate).
  static let pty = Logger(subsystem: subsystem, category: "PTY")

  /// Logger for configuration operations (load, save, migrate).
  static let config = Logger(subsystem: subsystem, category: "Config")

  /// Logger for statistics parsing.
  static let stats = Logger(subsystem: subsystem, category: "Stats")

  /// Logger for terminal view operations.
  static let terminal = Logger(subsystem: subsystem, category: "Terminal")

  /// Logger for agent operations.
  static let agent = Logger(subsystem: subsystem, category: "Agent")

  /// Logger for general app operations.
  static let app = Logger(subsystem: subsystem, category: "App")
}
