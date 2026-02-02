import Foundation

/// Build-time configuration that differs between development and release builds.
/// Values are loaded from Config.debug.json or Config.release.json based on build type.
struct BuildConfig: Codable {
  /// Shared instance with the current build configuration.
  static let current: BuildConfig = {
    #if DEBUG
    let configName = "Config.debug"
    #else
    let configName = "Config.release"
    #endif

    guard let url = Bundle.main.url(forResource: configName, withExtension: "json") else {
      fatalError("Missing config file: \(configName).json")
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      return try decoder.decode(BuildConfig.self, from: data)
    } catch {
      fatalError("Failed to load config: \(error)")
    }
  }()

  // MARK: - Properties

  /// The current environment (development/production).
  let environment: Environment

  /// Display name for the app.
  let appName: String

  /// Logging level.
  let logLevel: LogLevel

  /// Developer name.
  let developerName: String

  /// GitHub repository URL.
  let githubUrl: String

  /// Feature flags.
  let features: Features

  // MARK: - Computed Properties

  /// Whether this is a development build.
  var isDevelopment: Bool {
    environment == .development
  }

  /// Whether this is a production build.
  var isProduction: Bool {
    environment == .production
  }

  // MARK: - Static Convenience Accessors

  static var features: Features { current.features }
  static var logLevel: LogLevel { current.logLevel }
  static var developerName: String { current.developerName }
  static var githubUrl: String { current.githubUrl }
  static var isDevelopment: Bool { current.isDevelopment }
  static var isProduction: Bool { current.isProduction }

  // MARK: - Nested Types

  enum Environment: String, Codable {
    case development
    case production
  }

  enum LogLevel: String, Codable {
    case debug
    case info
    case warning
    case error

    var isVerbose: Bool {
      self == .debug || self == .info
    }
  }

  struct Features: Codable {
    let enableDebugMenu: Bool
    let enableCrashReporting: Bool
    let enableAnalytics: Bool
  }
}
