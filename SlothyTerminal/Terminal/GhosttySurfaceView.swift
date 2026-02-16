import AppKit
import Carbon.HIToolbox
import GhosttyKit
import os

/// NSView subclass that hosts a single libghostty terminal surface.
/// Handles keyboard/mouse input, sizing, focus, and lifecycle.
/// One instance per terminal tab.
class GhosttySurfaceView: NSView, NSTextInputClient {
  private(set) var surface: ghostty_surface_t?
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SlothyTerminal", category: "GhosttySurface")

  /// Accumulated text from `insertText` during key interpretation.
  private var keyTextAccumulator: [String]?

  /// Whether we are in a marked-text (IME composing) state.
  private var markedTextStorage: NSMutableAttributedString = NSMutableAttributedString()
  private var markedRange_: NSRange = NSRange(location: NSNotFound, length: 0)
  private var selectedRange_: NSRange = NSRange(location: 0, length: 0)

  /// Callbacks for integration with Tab.
  var onTitleChanged: ((String) -> Void)?
  var onDirectoryChanged: ((URL) -> Void)?
  var onClosed: (() -> Void)?

  // MARK: - Initialization

  init() {
    super.init(frame: NSMakeRect(0, 0, 800, 600))

    /// Metal rendering requires a layer-backed view.
    wantsLayer = true
    layer?.isOpaque = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    destroySurface()
  }

  // MARK: - Surface Lifecycle

  /// Creates the ghostty surface for this view.
  /// Call this after the view has been added to the view hierarchy.
  func createSurface(
    command: String? = nil,
    args: [String] = [],
    workingDirectory: URL? = nil,
    environment: [String: String] = [:]
  ) {
    guard let app = GhosttyApp.shared.app else {
      logger.error("Cannot create surface: GhosttyApp not initialized")
      return
    }

    guard surface == nil else {
      return
    }

    /// Build the full command string (command + args).
    let fullCommand: String?
    if let command {
      if args.isEmpty {
        fullCommand = command
      } else {
        fullCommand = ([command] + args).joined(separator: " ")
      }
    } else {
      fullCommand = nil
    }

    /// Build environment array.
    let envKeys = Array(environment.keys)
    let envValues = Array(environment.values)

    /// Create the surface config.
    var config = ghostty_surface_config_new()
    config.userdata = Unmanaged.passUnretained(self).toOpaque()
    config.platform_tag = GHOSTTY_PLATFORM_MACOS
    config.platform = ghostty_platform_u(
      macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque())
    )
    config.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
    config.font_size = 0
    config.context = GHOSTTY_SURFACE_CONTEXT_TAB

    /// Use nested withCString calls to keep C string pointers alive.
    let wd = workingDirectory?.path ?? ""
    let cmd = fullCommand ?? ""

    wd.withCString { cWd in
      config.working_directory = cWd.pointee == 0 ? nil : cWd

      cmd.withCString { cCmd in
        config.command = cCmd.pointee == 0 ? nil : cCmd

        /// Build env vars array.
        var envVars: [ghostty_env_var_s] = []
        envVars.reserveCapacity(envKeys.count)

        /// We need to keep C strings alive, so we use a helper.
        withExtendedLifetime(envKeys.map { $0.utf8CString }) { keyCStrings in
          withExtendedLifetime(envValues.map { $0.utf8CString }) { valueCStrings in
            for i in 0..<envKeys.count {
              keyCStrings[i].withUnsafeBufferPointer { keyBuf in
                valueCStrings[i].withUnsafeBufferPointer { valBuf in
                  envVars.append(ghostty_env_var_s(
                    key: keyBuf.baseAddress,
                    value: valBuf.baseAddress
                  ))
                }
              }
            }

            envVars.withUnsafeMutableBufferPointer { buffer in
              config.env_vars = buffer.baseAddress
              config.env_var_count = envKeys.count

              self.surface = ghostty_surface_new(app, &config)
            }
          }
        }
      }
    }

    if surface == nil {
      logger.error("ghostty_surface_new failed")
    }

    /// Register for action callbacks.
    registerActionCallbacks()
  }

  /// Destroys the surface and cleans up resources.
  func destroySurface() {
    unregisterActionCallbacks()

    if let surface {
      ghostty_surface_free(surface)
      self.surface = nil
    }
  }

  // MARK: - Action Callback Registration

  private func registerActionCallbacks() {
    GhosttyApp.shared.onTitleChanged = { [weak self] surface, title in
      guard let self,
            self.surface == surface
      else {
        return
      }

      self.onTitleChanged?(title)
    }

    GhosttyApp.shared.onPwdChanged = { [weak self] surface, pwd in
      guard let self,
            self.surface == surface
      else {
        return
      }

      let url: URL
      if pwd.hasPrefix("file://") {
        guard let parsed = URL(string: pwd) else {
          return
        }
        url = parsed
      } else {
        url = URL(fileURLWithPath: pwd)
      }
      self.onDirectoryChanged?(url)
    }

    GhosttyApp.shared.onSurfaceClosed = { [weak self] surface in
      guard let self,
            self.surface == surface
      else {
        return
      }

      self.onClosed?()
    }
  }

  private func unregisterActionCallbacks() {
    /// Only clear if we are the one who registered.
    GhosttyApp.shared.onTitleChanged = nil
    GhosttyApp.shared.onPwdChanged = nil
    GhosttyApp.shared.onSurfaceClosed = nil
  }

  // MARK: - View Lifecycle

  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }
  override var isFlipped: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateTrackingAreas()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)

    guard let surface else {
      return
    }

    let backing = convertToBacking(newSize)
    ghostty_surface_set_size(surface, UInt32(backing.width), UInt32(backing.height))
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()

    guard let surface else {
      return
    }

    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    ghostty_surface_set_content_scale(surface, scale, scale)
  }

  override func updateTrackingAreas() {
    /// Remove existing tracking areas.
    trackingAreas.forEach { removeTrackingArea($0) }

    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)

    super.updateTrackingAreas()
  }

  // MARK: - Focus

  func setFocused(_ focused: Bool) {
    guard let surface else {
      return
    }

    ghostty_surface_set_focus(surface, focused)

    if focused {
      ghostty_surface_set_occlusion(surface, false)
    }
  }

  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    if result {
      setFocused(true)
    }
    return result
  }

  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result {
      setFocused(false)
    }
    return result
  }

  // MARK: - Mouse Cursor

  func updateMouseCursor(_ shape: ghostty_action_mouse_shape_e) {
    let cursor: NSCursor
    switch shape {
    case GHOSTTY_MOUSE_SHAPE_TEXT:
      cursor = .iBeam

    case GHOSTTY_MOUSE_SHAPE_POINTER:
      cursor = .pointingHand

    case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
      cursor = .crosshair

    case GHOSTTY_MOUSE_SHAPE_GRAB:
      cursor = .openHand

    case GHOSTTY_MOUSE_SHAPE_GRABBING:
      cursor = .closedHand

    case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED, GHOSTTY_MOUSE_SHAPE_NO_DROP:
      cursor = .operationNotAllowed

    case GHOSTTY_MOUSE_SHAPE_EW_RESIZE, GHOSTTY_MOUSE_SHAPE_COL_RESIZE:
      cursor = .resizeLeftRight

    case GHOSTTY_MOUSE_SHAPE_NS_RESIZE, GHOSTTY_MOUSE_SHAPE_ROW_RESIZE:
      cursor = .resizeUpDown

    default:
      cursor = .arrow
    }

    cursor.set()
  }

  // MARK: - Keyboard Input

  override func keyDown(with event: NSEvent) {
    guard surface != nil else {
      self.interpretKeyEvents([event])
      return
    }

    let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
    keyTextAccumulator = []

    /// Let the input manager handle IME composition.
    self.interpretKeyEvents([event])

    /// Send accumulated text or raw key event.
    if let list = keyTextAccumulator, !list.isEmpty {
      for text in list {
        _ = sendKeyAction(action, event: event, text: text)
      }
    } else {
      _ = sendKeyAction(action, event: event, text: event.ghosttyCharacters)
    }

    keyTextAccumulator = nil
  }

  override func keyUp(with event: NSEvent) {
    _ = sendKeyAction(GHOSTTY_ACTION_RELEASE, event: event)
  }

  override func flagsChanged(with event: NSEvent) {
    let mod: UInt32
    switch event.keyCode {
    case 0x39:
      mod = GHOSTTY_MODS_CAPS.rawValue

    case 0x38, 0x3C:
      mod = GHOSTTY_MODS_SHIFT.rawValue

    case 0x3B, 0x3E:
      mod = GHOSTTY_MODS_CTRL.rawValue

    case 0x3A, 0x3D:
      mod = GHOSTTY_MODS_ALT.rawValue

    case 0x37, 0x36:
      mod = GHOSTTY_MODS_SUPER.rawValue

    default:
      return
    }

    if hasMarkedText() {
      return
    }

    let mods = Self.ghosttyMods(event.modifierFlags)
    var action: ghostty_input_action_e = GHOSTTY_ACTION_RELEASE
    if mods.rawValue & mod != 0 {
      action = GHOSTTY_ACTION_PRESS
    }

    _ = sendKeyAction(action, event: event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard let surface else {
      return super.performKeyEquivalent(with: event)
    }

    /// Check if Ghostty considers this a binding.
    var keyEvent = Self.makeKeyEvent(GHOSTTY_ACTION_PRESS, event: event)
    var flags: ghostty_binding_flags_e = .init(0)
    let isBinding = ghostty_surface_key_is_binding(surface, keyEvent, &flags)

    /// If it's a consumed binding, handle it ourselves.
    if isBinding && (flags.rawValue & GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue != 0) {
      keyEvent.text = nil
      _ = ghostty_surface_key(surface, keyEvent)
      return true
    }

    /// Let Cmd+C with selection do copy, Cmd+V do paste.
    let cmdOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command

    guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
      return super.performKeyEquivalent(with: event)
    }

    if cmdOnly {
      if chars == "c" && ghostty_surface_has_selection(surface) {
        /// Copy selection to clipboard.
        var text = ghostty_text_s()
        if ghostty_surface_read_selection(surface, &text) {
          if let ptr = text.text, text.text_len > 0 {
            let str = String(cString: ptr)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
          }
          ghostty_surface_free_text(surface, &text)
        }
        return true
      }

      if chars == "v" {
        /// Paste from clipboard via ghostty binding action.
        let action = "paste_from_clipboard"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.count))
        return true
      }
    }

    return super.performKeyEquivalent(with: event)
  }

  private func sendKeyAction(
    _ action: ghostty_input_action_e,
    event: NSEvent,
    text: String? = nil,
    composing: Bool = false
  ) -> Bool {
    guard let surface else {
      return false
    }

    var keyEvent = Self.makeKeyEvent(action, event: event)
    keyEvent.composing = composing

    if let text,
       !text.isEmpty,
       let first = text.utf8.first,
       first >= 0x20
    {
      return text.withCString { ptr in
        keyEvent.text = ptr
        return ghostty_surface_key(surface, keyEvent)
      }
    } else {
      return ghostty_surface_key(surface, keyEvent)
    }
  }

  static func makeKeyEvent(
    _ action: ghostty_input_action_e,
    event: NSEvent
  ) -> ghostty_input_key_s {
    var keyEvent = ghostty_input_key_s()
    keyEvent.action = action
    keyEvent.keycode = UInt32(event.keyCode)
    keyEvent.text = nil
    keyEvent.composing = false
    keyEvent.mods = ghosttyMods(event.modifierFlags)

    /// consumed_mods: remove ctrl and super from what we report.
    keyEvent.consumed_mods = ghosttyMods(
      event.modifierFlags.subtracting([.control, .command])
    )

    /// Unshifted codepoint for physical key identification.
    keyEvent.unshifted_codepoint = 0
    if event.type == .keyDown || event.type == .keyUp {
      if let chars = event.characters(byApplyingModifiers: []),
         let scalar = chars.unicodeScalars.first
      {
        keyEvent.unshifted_codepoint = scalar.value
      }
    }

    return keyEvent
  }

  // MARK: - Modifier Conversion

  static func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue

    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

    let raw = flags.rawValue
    if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

    return ghostty_input_mods_e(mods)
  }

  // MARK: - Mouse Input

  override func mouseDown(with event: NSEvent) {
    guard let surface else {
      return
    }

    let mods = Self.ghosttyMods(event.modifierFlags)
    _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
  }

  override func mouseUp(with event: NSEvent) {
    guard let surface else {
      return
    }

    let mods = Self.ghosttyMods(event.modifierFlags)
    _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    ghostty_surface_mouse_pressure(surface, 0, 0)
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let surface else {
      super.rightMouseDown(with: event)
      return
    }

    let mods = Self.ghosttyMods(event.modifierFlags)
    if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods) {
      super.rightMouseDown(with: event)
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    guard let surface else {
      super.rightMouseUp(with: event)
      return
    }

    let mods = Self.ghosttyMods(event.modifierFlags)
    if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods) {
      super.rightMouseUp(with: event)
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    guard let surface else {
      super.otherMouseDown(with: event)
      return
    }

    let mods = Self.ghosttyMods(event.modifierFlags)
    let button = mapMouseButton(event.buttonNumber)
    _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, button, mods)
  }

  override func otherMouseUp(with event: NSEvent) {
    guard let surface else {
      super.otherMouseUp(with: event)
      return
    }

    let mods = Self.ghosttyMods(event.modifierFlags)
    let button = mapMouseButton(event.buttonNumber)
    _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, button, mods)
  }

  override func mouseMoved(with event: NSEvent) {
    sendMousePos(event)
  }

  override func mouseDragged(with event: NSEvent) {
    sendMousePos(event)
  }

  override func rightMouseDragged(with event: NSEvent) {
    sendMousePos(event)
  }

  override func otherMouseDragged(with event: NSEvent) {
    sendMousePos(event)
  }

  override func scrollWheel(with event: NSEvent) {
    guard let surface else {
      return
    }

    var x = event.scrollingDeltaX
    var y = event.scrollingDeltaY
    if event.hasPreciseScrollingDeltas {
      x *= 2
      y *= 2
    }

    /// Build scroll mods as packed int.
    var scrollMods: Int32 = 0
    if event.hasPreciseScrollingDeltas {
      scrollMods |= 1  /// precision bit
    }

    ghostty_surface_mouse_scroll(surface, x, y, scrollMods)
  }

  override func pressureChange(with event: NSEvent) {
    guard let surface else {
      return
    }

    ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure))
  }

  private func sendMousePos(_ event: NSEvent) {
    guard let surface else {
      return
    }

    let pos = convert(event.locationInWindow, from: nil)
    let mods = Self.ghosttyMods(event.modifierFlags)

    /// Flip Y: AppKit origin is bottom-left, ghostty expects top-left.
    ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
  }

  private func mapMouseButton(_ buttonNumber: Int) -> ghostty_input_mouse_button_e {
    switch buttonNumber {
    case 0: return GHOSTTY_MOUSE_LEFT
    case 1: return GHOSTTY_MOUSE_RIGHT
    case 2: return GHOSTTY_MOUSE_MIDDLE
    case 3: return GHOSTTY_MOUSE_FOUR
    case 4: return GHOSTTY_MOUSE_FIVE
    default: return GHOSTTY_MOUSE_UNKNOWN
    }
  }

  // MARK: - NSTextInputClient

  func insertText(_ string: Any, replacementRange: NSRange) {
    let str: String
    if let attrStr = string as? NSAttributedString {
      str = attrStr.string
    } else if let s = string as? String {
      str = s
    } else {
      return
    }

    /// If we're accumulating for keyDown, add to the list.
    if keyTextAccumulator != nil {
      keyTextAccumulator?.append(str)
      return
    }

    /// Direct text input (e.g. from IME finalization).
    guard let surface else {
      return
    }

    str.withCString { ptr in
      ghostty_surface_text(surface, ptr, UInt(str.utf8.count))
    }
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    let attrStr: NSAttributedString
    if let a = string as? NSAttributedString {
      attrStr = a
    } else if let s = string as? String {
      attrStr = NSAttributedString(string: s)
    } else {
      return
    }

    markedTextStorage = NSMutableAttributedString(attributedString: attrStr)
    if attrStr.length > 0 {
      markedRange_ = NSRange(location: 0, length: attrStr.length)
    } else {
      markedRange_ = NSRange(location: NSNotFound, length: 0)
    }
    selectedRange_ = selectedRange

    /// Send preedit string to ghostty.
    guard let surface else {
      return
    }

    let text = attrStr.string
    text.withCString { ptr in
      ghostty_surface_preedit(surface, ptr, UInt(text.utf8.count))
    }
  }

  func unmarkText() {
    markedTextStorage = NSMutableAttributedString()
    markedRange_ = NSRange(location: NSNotFound, length: 0)

    guard let surface else {
      return
    }

    ghostty_surface_preedit(surface, nil, 0)
  }

  func selectedRange() -> NSRange {
    selectedRange_
  }

  func markedRange() -> NSRange {
    markedRange_
  }

  func hasMarkedText() -> Bool {
    markedRange_.location != NSNotFound
  }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
    nil
  }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] {
    []
  }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    guard let surface else {
      return .zero
    }

    var x: Double = 0
    var y: Double = 0
    var w: Double = 0
    var h: Double = 0
    ghostty_surface_ime_point(surface, &x, &y, &w, &h)

    let pointInView = NSPoint(x: x, y: y)
    let sizeInView = NSSize(width: w, height: h)

    guard let window else {
      return NSRect(origin: pointInView, size: sizeInView)
    }

    let pointInWindow = convert(pointInView, to: nil)
    let screenRect = window.convertToScreen(NSRect(origin: pointInWindow, size: sizeInView))
    return screenRect
  }

  func characterIndex(for point: NSPoint) -> Int {
    0
  }
}

// MARK: - NSEvent Extension

extension NSEvent {
  /// Returns the characters suitable for sending to ghostty, filtering out
  /// control characters and PUA range (function keys).
  var ghosttyCharacters: String? {
    guard let characters else {
      return nil
    }

    if characters.count == 1,
       let scalar = characters.unicodeScalars.first
    {
      /// Skip control characters.
      if scalar.value < 0x20 {
        return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
      }

      /// Skip PUA range (macOS function key codes).
      if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
        return nil
      }
    }

    return characters
  }
}
