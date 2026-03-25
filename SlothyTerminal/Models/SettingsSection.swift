import Foundation

/// Settings navigation sections.
enum SettingsSection: String, CaseIterable, Identifiable {
  case general
  case agents
  case appearance
  case shortcuts
  case prompts
  case usage
  case licenses

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .general:
      return "General"

    case .agents:
      return "Agents"

    case .appearance:
      return "Appearance"

    case .shortcuts:
      return "Shortcuts"

    case .prompts:
      return "Prompts"

    case .usage:
      return "Usage"

    case .licenses:
      return "Licenses"
    }
  }

  var icon: String {
    switch self {
    case .general:
      return "gear"

    case .agents:
      return "cpu"

    case .appearance:
      return "paintbrush"

    case .shortcuts:
      return "keyboard"

    case .prompts:
      return "text.bubble"

    case .usage:
      return "chart.bar"

    case .licenses:
      return "doc.text"
    }
  }
}
