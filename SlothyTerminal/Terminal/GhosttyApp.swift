import AppKit
import GhosttyKit
import os

private let ghosttyCallbackLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "SlothyTerminal",
  category: "GhosttyApp"
)

/// Process-wide singleton managing the libghostty app instance.
/// Creates the ghostty config and app, implements the required runtime callbacks,
/// and dispatches actions (title changes, PWD updates, close requests, etc.)
/// back into the SlothyTerminal world.
@MainActor
class GhosttyApp {
  static let shared = GhosttyApp()

  private(set) var app: ghostty_app_t?
  fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SlothyTerminal", category: "GhosttyApp")

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

    /// Slothy terminal UI is currently dark-themed.
    ghostty_app_set_color_scheme(app, GHOSTTY_COLOR_SCHEME_DARK)
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
      guard let view = GhosttyApp.surfaceView(from: surface) else {
        return
      }

      view.onTitleChanged?(title)
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
      guard let view = GhosttyApp.surfaceView(from: surface) else {
        return
      }

      let url: URL
      if pwd.hasPrefix("file://"), let parsed = URL(string: pwd)
      {
        url = parsed
      } else {
        url = URL(fileURLWithPath: pwd)
      }

      view.onDirectoryChanged?(url)
    }

    return true

  case GHOSTTY_ACTION_RING_BELL:
    DispatchQueue.main.async {
      NSSound.beep()
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

  case GHOSTTY_ACTION_RENDERER_HEALTH:
    let health = action.action.renderer_health
    if health == GHOSTTY_RENDERER_HEALTH_UNHEALTHY {
      ghosttyCallbackLogger.error("Ghostty renderer health is UNHEALTHY")
    } else {
      ghosttyCallbackLogger.info("Ghostty renderer health is OK")
    }

    return true

  case GHOSTTY_ACTION_INITIAL_SIZE:
    let initialSize = action.action.initial_size
    ghosttyCallbackLogger.info("Ghostty initial size hint: \(initialSize.width)x\(initialSize.height)")
    return true

  case GHOSTTY_ACTION_CELL_SIZE:
    let cellSize = action.action.cell_size
    ghosttyCallbackLogger.info("Ghostty cell size: \(cellSize.width)x\(cellSize.height)")
    return true

  case GHOSTTY_ACTION_COMMAND_FINISHED:
    let finished = action.action.command_finished
    ghosttyCallbackLogger.info("Ghostty command finished: exit=\(finished.exit_code), durationNs=\(finished.duration)")
    return true

  case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
    let child = action.action.child_exited
    ghosttyCallbackLogger.info("Ghostty child exited: exit=\(child.exit_code), elapsedMs=\(child.timetime_ms)")
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
    /// Metal-backed surfaces present automatically in the normal render path.
    /// Treat this as a signal only; avoid forcing extra refresh/draw calls.
    return true

  case GHOSTTY_ACTION_CLOSE_WINDOW:
    /// In our app, closing the "window" for a surface means closing that surface's tab.
    if let surface {
      DispatchQueue.main.async {
        guard let view = GhosttyApp.surfaceView(from: surface) else {
          return
        }

        view.onClosed?()
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
  guard let userdata else {
    return
  }

  /// Read from the standard pasteboard.
  let str = NSPasteboard.general.string(forType: .string) ?? ""
  let surfaceView = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()

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
  guard let userdata else {
    return
  }

  /// Auto-approve clipboard reads for simplicity.
  let surfaceView = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()

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
  guard let userdata else {
    return
  }

  let surfaceView = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
  ghosttyCallbackLogger.info("Ghostty close surface requested (processAlive=\(processAlive))")

  DispatchQueue.main.async {
    surfaceView.onClosed?()
  }
}
