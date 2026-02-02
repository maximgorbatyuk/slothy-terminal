import Foundation
import SwiftUI

/// Manages application configuration persistence.
@Observable
class ConfigManager {
  /// Shared singleton instance.
  static let shared = ConfigManager()

  /// The current configuration.
  var config: AppConfig {
    didSet {
      if config != oldValue {
        saveDebounced()
      }
    }
  }

  /// Whether the config has unsaved changes.
  private(set) var hasUnsavedChanges: Bool = false

  /// Debounce timer for saving.
  private var saveTimer: Timer?
  private let saveDebounceInterval: TimeInterval = 0.5

  /// URL for the config file.
  private var configFileURL: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!

    let appFolder = appSupport.appendingPathComponent("SlothyTerminal", isDirectory: true)
    return appFolder.appendingPathComponent("config.json")
  }

  private init() {
    self.config = AppConfig.default
    load()
  }

  /// Loads configuration from disk.
  func load() {
    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: configFileURL.path) else {
      /// No config file exists, use defaults.
      return
    }

    do {
      let data = try Data(contentsOf: configFileURL)
      let decoder = JSONDecoder()
      config = try decoder.decode(AppConfig.self, from: data)
      hasUnsavedChanges = false
    } catch {
      print("Failed to load config: \(error)")
      /// Use default config on error.
      config = AppConfig.default
    }
  }

  /// Saves configuration to disk.
  func save() {
    saveTimer?.invalidate()
    saveTimer = nil

    let fileManager = FileManager.default
    let folder = configFileURL.deletingLastPathComponent()

    do {
      /// Create directory if needed.
      if !fileManager.fileExists(atPath: folder.path) {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      }

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(config)
      try data.write(to: configFileURL, options: .atomic)
      hasUnsavedChanges = false
    } catch {
      print("Failed to save config: \(error)")
    }
  }

  /// Saves configuration after a short debounce delay.
  private func saveDebounced() {
    hasUnsavedChanges = true
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { [weak self] _ in
      self?.save()
    }
  }

  /// Resets configuration to defaults.
  func reset() {
    config = AppConfig.default
    save()
  }

  /// Returns the custom path for an agent, if set.
  func customPath(for agentType: AgentType) -> String? {
    switch agentType {
    case .terminal:
      return nil
    case .claude:
      return config.claudePath
    case .opencode:
      return config.opencodePath
    }
  }

  /// Sets a custom path for an agent.
  func setCustomPath(_ path: String?, for agentType: AgentType) {
    switch agentType {
    case .terminal:
      break
    case .claude:
      config.claudePath = path
    case .opencode:
      config.opencodePath = path
    }
  }

  /// Returns the accent color for an agent.
  func accentColor(for agentType: AgentType) -> Color {
    switch agentType {
    case .terminal:
      return agentType.accentColor
    case .claude:
      if let customColor = config.claudeAccentColor {
        return customColor.color
      }
      return agentType.accentColor
    case .opencode:
      if let customColor = config.opencodeAccentColor {
        return customColor.color
      }
      return agentType.accentColor
    }
  }

  /// Sets a custom accent color for an agent.
  func setAccentColor(_ color: Color?, for agentType: AgentType) {
    let codableColor = color.map { CodableColor($0) }
    switch agentType {
    case .terminal:
      break
    case .claude:
      config.claudeAccentColor = codableColor
    case .opencode:
      config.opencodeAccentColor = codableColor
    }
  }

  /// Gets the terminal font.
  var terminalFont: NSFont {
    NSFont(name: config.terminalFontName, size: config.terminalFontSize)
      ?? NSFont.monospacedSystemFont(ofSize: config.terminalFontSize, weight: .regular)
  }

  /// Gets available monospaced fonts.
  static var availableMonospacedFonts: [String] {
    let fontManager = NSFontManager.shared
    let monospacedFonts = fontManager.availableFontFamilies.filter { family in
      guard let font = NSFont(name: family, size: 12) else {
        return false
      }

      return font.isFixedPitch
    }

    /// Add common monospaced fonts that might not be detected.
    var fonts = Set(monospacedFonts)
    fonts.insert("SF Mono")
    fonts.insert("Menlo")
    fonts.insert("Monaco")
    fonts.insert("Courier New")

    return fonts.sorted()
  }
}
