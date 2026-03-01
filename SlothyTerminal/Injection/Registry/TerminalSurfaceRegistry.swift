import Foundation
import OSLog

/// A terminal surface that can receive programmatic input injection.
@MainActor
protocol InjectableSurface: AnyObject {
  /// Inject raw text into the terminal (no trailing newline).
  func injectText(_ text: String) -> Bool

  /// Inject a shell command, optionally pressing Enter.
  func injectCommand(_ command: String, submit: CommandSubmitMode) -> Bool

  /// Inject paste content with the specified mode.
  func injectPaste(_ text: String, mode: PasteMode) -> Bool

  /// Send a control signal (Ctrl+C, Ctrl+D, etc.).
  func injectControl(_ signal: ControlSignal) -> Bool

  /// Send a synthetic key event.
  func injectKey(keyCode: UInt32, modifiers: UInt32) -> Bool
}

/// Tracks tab-to-surface mappings so the injection system can find live terminal surfaces.
@MainActor
class TerminalSurfaceRegistry {
  static let shared = TerminalSurfaceRegistry()

  private var surfaces: [UUID: WeakSurface] = [:]

  init() {}

  /// Registers a surface for the given tab ID. Overwrites any previous registration.
  func register(tabId: UUID, surface: InjectableSurface) {
    surfaces[tabId] = WeakSurface(surface)
    Logger.injection.debug("Registered surface for tab \(tabId.uuidString)")
  }

  /// Removes the surface registration for the given tab ID.
  func unregister(tabId: UUID) {
    surfaces.removeValue(forKey: tabId)
    Logger.injection.debug("Unregistered surface for tab \(tabId.uuidString)")
  }

  /// Returns the live surface for the given tab, or nil if deallocated/unregistered.
  func surface(for tabId: UUID) -> InjectableSurface? {
    guard let weak = surfaces[tabId] else {
      return nil
    }

    guard let surface = weak.value else {
      /// Surface was deallocated — clean up the stale entry.
      surfaces.removeValue(forKey: tabId)
      return nil
    }

    return surface
  }

  /// Returns all tab IDs that have a live registered surface.
  func registeredTabIds() -> [UUID] {
    cleanupDeallocated()
    return Array(surfaces.keys)
  }

  /// Removes all registrations.
  func removeAll() {
    surfaces.removeAll()
  }

  /// Removes entries whose surface has been deallocated.
  private func cleanupDeallocated() {
    surfaces = surfaces.filter { $0.value.value != nil }
  }
}

/// Weak wrapper around an InjectableSurface to avoid retaining NSViews.
private final class WeakSurface {
  weak var value: (any InjectableSurface)?

  init(_ value: any InjectableSurface) {
    self.value = value
  }
}
