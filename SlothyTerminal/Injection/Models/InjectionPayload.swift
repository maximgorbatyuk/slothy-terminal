import Foundation

/// How a command should be submitted to the terminal.
enum CommandSubmitMode: String, Codable, Equatable, Sendable {
  /// Append newline to execute immediately.
  case execute

  /// Insert text without pressing Enter.
  case insert
}

/// How pasted content should be delivered.
enum PasteMode: String, Codable, Equatable, Sendable {
  /// Use bracketed paste escape sequences (\e[200~ ... \e[201~).
  case bracketed

  /// Send raw text without bracketing.
  case plain
}

/// Control signals that can be injected into a terminal.
enum ControlSignal: String, Codable, Equatable, CaseIterable, Sendable {
  case ctrlC
  case ctrlD
  case ctrlZ
  case ctrlL

  /// The ASCII byte value for this control signal.
  var asciiValue: UInt8 {
    switch self {
    case .ctrlC: return 3
    case .ctrlD: return 4
    case .ctrlZ: return 26
    case .ctrlL: return 12
    }
  }
}

/// The content to inject into a terminal surface.
enum InjectionPayload: Codable, Equatable, Sendable {
  /// Raw text insertion (no trailing newline).
  case text(String)

  /// Shell command with configurable submit behavior.
  case command(String, submit: CommandSubmitMode)

  /// Paste content with mode selection.
  case paste(String, mode: PasteMode)

  /// Send a control signal (Ctrl+C, Ctrl+D, etc.).
  case control(ControlSignal)

  /// Synthetic key event (keyCode + modifier flags).
  case key(keyCode: UInt32, modifiers: UInt32)
}
