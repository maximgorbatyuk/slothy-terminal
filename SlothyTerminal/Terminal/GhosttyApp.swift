import AppKit
import GhosttyKit
import os

/// Process-wide singleton managing the libghostty app instance.
/// Creates the ghostty config and app, implements the required runtime callbacks,
/// and dispatches actions (title changes, PWD updates, close requests, etc.)
/// back into the SlothyTerminal world.
@MainActor
class GhosttyApp {
  static let shared = GhosttyApp()

  private(set) var app: ghostty_app_t?
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SlothyTerminal", category: "GhosttyApp")

  /// Callbacks that surface views register to receive actions.
  var onTitleChanged: ((_ surface: ghostty_surface_t, _ title: String) -> Void)?
  var onPwdChanged: ((_ surface: ghostty_surface_t, _ pwd: String) -> Void)?
  var onSurfaceClosed: ((_ surface: ghostty_surface_t) -> Void)?
  var onBell: ((_ surface: ghostty_surface_t) -> Void)?

  private init() {
    initializeGhostty()
  }

  private func initializeGhostty() {
    /// Initialize the global ghostty state.
    guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
      logger.error("ghostty_init failed")
      return
    }

    /// Create and load config.
    guard let config = ghostty_config_new() else {
      logger.error("ghostty_config_new failed")
      return
    }

    ghostty_config_load_default_files(config)
    ghostty_config_load_recursive_files(config)
    ghostty_config_finalize(config)

    /// Log any config diagnostics.
    let diagCount = ghostty_config_diagnostics_count(config)
    for i in 0..<diagCount {
      let diag = ghostty_config_get_diagnostic(config, i)
      if let msg = diag.message {
        logger.warning("ghostty config: \(String(cString: msg))")
      }
    }

    /// Create the runtime config with our callbacks.
    var runtimeConfig = ghostty_runtime_config_s(
      userdata: Unmanaged.passUnretained(self).toOpaque(),
      supports_selection_clipboard: false,
      wakeup_cb: ghosttyWakeup,
      action_cb: ghosttyAction,
      read_clipboard_cb: ghosttyReadClipboard,
      confirm_read_clipboard_cb: ghosttyConfirmReadClipboard,
      write_clipboard_cb: ghosttyWriteClipboard,
      close_surface_cb: ghosttyCloseSurface
    )

    /// Create the app.
    guard let newApp = ghostty_app_new(&runtimeConfig, config) else {
      logger.error("ghostty_app_new failed")
      ghostty_config_free(config)
      return
    }

    self.app = newApp

    /// Set initial focus/color scheme.
    ghostty_app_set_focus(newApp, NSApp.isActive)
    updateColorScheme()

    /// Observe app activation changes.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidResignActive),
      name: NSApplication.didResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(inputSourceChanged),
      name: NSTextInputContext.keyboardSelectionDidChangeNotification,
      object: nil
    )

    /// Config is owned by the app now; don't free it.
    logger.info("GhosttyApp initialized successfully")
  }

  func tick() {
    guard let app else {
      return
    }

    ghostty_app_tick(app)
  }

  func updateColorScheme() {
    guard let app else {
      return
    }

    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    ghostty_app_set_color_scheme(app, isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)
  }

  // MARK: - Notification Handlers

  @objc private func appDidBecomeActive(_ notification: Notification) {
    guard let app else {
      return
    }

    ghostty_app_set_focus(app, true)
  }

  @objc private func appDidResignActive(_ notification: Notification) {
    guard let app else {
      return
    }

    ghostty_app_set_focus(app, false)
  }

  @objc private func inputSourceChanged(_ notification: Notification) {
    guard let app else {
      return
    }

    ghostty_app_keyboard_changed(app)
  }

  // MARK: - Surface Lookup Helper

  /// Extracts the SurfaceView from a surface's userdata.
  static func surfaceView(from surface: ghostty_surface_t) -> GhosttySurfaceView? {
    guard let ud = ghostty_surface_userdata(surface) else {
      return nil
    }

    return Unmanaged<GhosttySurfaceView>.fromOpaque(ud).takeUnretainedValue()
  }
}

// MARK: - C Callback Trampolines

/// These are free functions (not closures that capture `self`) so they can be
/// passed as C function pointers in `ghostty_runtime_config_s`.

private func ghosttyWakeup(_ userdata: UnsafeMutableRawPointer?) {
  DispatchQueue.main.async {
    let app = Unmanaged<GhosttyApp>.fromOpaque(userdata!).takeUnretainedValue()
    app.tick()
  }
}

private func ghosttyAction(
  _ app: ghostty_app_t?,
  target: ghostty_target_s,
  action: ghostty_action_s
) -> Bool {
  /// Get the surface if the target is a surface.
  let surface: ghostty_surface_t?
  switch target.tag {
  case GHOSTTY_TARGET_SURFACE:
    surface = target.target.surface

  default:
    surface = nil
  }

  switch action.tag {
  case GHOSTTY_ACTION_SET_TITLE:
    guard let surface,
          let cTitle = action.action.set_title.title
    else {
      return false
    }

    let title = String(cString: cTitle)
    DispatchQueue.main.async {
      GhosttyApp.shared.onTitleChanged?(surface, title)
    }
    return true

  case GHOSTTY_ACTION_PWD:
    guard let surface,
          let cPwd = action.action.pwd.pwd
    else {
      return false
    }

    let pwd = String(cString: cPwd)
    DispatchQueue.main.async {
      GhosttyApp.shared.onPwdChanged?(surface, pwd)
    }
    return true

  case GHOSTTY_ACTION_RING_BELL:
    if let surface {
      DispatchQueue.main.async {
        GhosttyApp.shared.onBell?(surface)
      }
    }
    return true

  case GHOSTTY_ACTION_MOUSE_SHAPE:
    guard let surface else {
      return false
    }

    let shape = action.action.mouse_shape
    DispatchQueue.main.async {
      guard let view = GhosttyApp.surfaceView(from: surface) else {
        return
      }

      view.updateMouseCursor(shape)
    }
    return true

  case GHOSTTY_ACTION_MOUSE_VISIBILITY:
    let visible = action.action.mouse_visibility == GHOSTTY_MOUSE_VISIBLE
    DispatchQueue.main.async {
      if visible {
        NSCursor.unhide()
      } else {
        NSCursor.hide()
      }
    }
    return true

  case GHOSTTY_ACTION_QUIT:
    DispatchQueue.main.async {
      NSApp.terminate(nil)
    }
    return true

  case GHOSTTY_ACTION_OPEN_CONFIG:
    DispatchQueue.main.async {
      let configPath = ghostty_config_open_path()
      defer { ghostty_string_free(configPath) }

      if let ptr = configPath.ptr, configPath.len > 0 {
        let path = String(cString: ptr)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
      }
    }
    return true

  case GHOSTTY_ACTION_RENDER:
    /// Trigger a redraw of the surface's view.
    if let surface {
      DispatchQueue.main.async {
        guard let view = GhosttyApp.surfaceView(from: surface) else {
          return
        }

        view.needsDisplay = true
      }
    }
    return true

  case GHOSTTY_ACTION_CLOSE_WINDOW:
    /// In our app, closing the "window" for a surface means closing that surface's tab.
    if let surface {
      DispatchQueue.main.async {
        GhosttyApp.shared.onSurfaceClosed?(surface)
      }
    }
    return true

  default:
    /// Actions we don't handle (splits, new tabs, etc.) — we manage tabs ourselves.
    return false
  }
}

private func ghosttyReadClipboard(
  _ userdata: UnsafeMutableRawPointer?,
  location: ghostty_clipboard_e,
  state: UnsafeMutableRawPointer?
) {
  /// Read from the standard pasteboard.
  let str = NSPasteboard.general.string(forType: .string) ?? ""
  let surfaceView = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata!).takeUnretainedValue()

  guard let surface = surfaceView.surface else {
    return
  }

  str.withCString { ptr in
    ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
  }
}

private func ghosttyConfirmReadClipboard(
  _ userdata: UnsafeMutableRawPointer?,
  string: UnsafePointer<CChar>?,
  state: UnsafeMutableRawPointer?,
  request: ghostty_clipboard_request_e
) {
  /// Auto-approve clipboard reads for simplicity.
  let surfaceView = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata!).takeUnretainedValue()

  guard let surface = surfaceView.surface else {
    return
  }

  let str = NSPasteboard.general.string(forType: .string) ?? ""
  str.withCString { ptr in
    ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
  }
}

private func ghosttyWriteClipboard(
  _ userdata: UnsafeMutableRawPointer?,
  location: ghostty_clipboard_e,
  content: UnsafePointer<ghostty_clipboard_content_s>?,
  len: Int,
  confirm: Bool
) {
  guard let content,
        len > 0
  else {
    return
  }

  /// Find the text/plain entry and write it to the pasteboard.
  for i in 0..<len {
    let item = content[i]

    guard let mime = item.mime,
          String(cString: mime) == "text/plain",
          let data = item.data
    else {
      continue
    }

    let str = String(cString: data)
    DispatchQueue.main.async {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(str, forType: .string)
    }
    break
  }
}

private func ghosttyCloseSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
  let surfaceView = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata!).takeUnretainedValue()

  guard let surface = surfaceView.surface else {
    return
  }

  DispatchQueue.main.async {
    GhosttyApp.shared.onSurfaceClosed?(surface)
  }
}
