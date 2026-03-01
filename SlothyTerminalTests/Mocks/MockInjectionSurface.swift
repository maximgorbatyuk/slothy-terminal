import Foundation
@testable import SlothyTerminalLib

/// Mock surface that records all injection calls.
@MainActor
class MockInjectionSurface: InjectableSurface {
  var shouldSucceed: Bool = true

  private(set) var textCalls: [String] = []
  private(set) var commandCalls: [(command: String, submit: CommandSubmitMode)] = []
  private(set) var pasteCalls: [(text: String, mode: PasteMode)] = []
  private(set) var controlCalls: [ControlSignal] = []
  private(set) var keyCalls: [(keyCode: UInt32, modifiers: UInt32)] = []

  var totalCallCount: Int {
    textCalls.count + commandCalls.count + pasteCalls.count + controlCalls.count + keyCalls.count
  }

  func injectText(_ text: String) -> Bool {
    textCalls.append(text)
    return shouldSucceed
  }

  func injectCommand(_ command: String, submit: CommandSubmitMode) -> Bool {
    commandCalls.append((command, submit))
    return shouldSucceed
  }

  func injectPaste(_ text: String, mode: PasteMode) -> Bool {
    pasteCalls.append((text, mode))
    return shouldSucceed
  }

  func injectControl(_ signal: ControlSignal) -> Bool {
    controlCalls.append(signal)
    return shouldSucceed
  }

  func injectKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
    keyCalls.append((keyCode, modifiers))
    return shouldSucceed
  }
}
