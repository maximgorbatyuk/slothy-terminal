import Foundation
import Sparkle

/// Manages automatic updates using the Sparkle framework.
@Observable
class UpdateManager {
  /// Shared singleton instance.
  static let shared = UpdateManager()

  /// The Sparkle updater controller.
  private let updaterController: SPUStandardUpdaterController

  /// Whether the app can check for updates.
  var canCheckForUpdates: Bool {
    updaterController.updater.canCheckForUpdates
  }

  /// The date of the last update check.
  var lastUpdateCheckDate: Date? {
    updaterController.updater.lastUpdateCheckDate
  }

  /// Whether automatic update checks are enabled.
  var automaticallyChecksForUpdates: Bool {
    get {
      updaterController.updater.automaticallyChecksForUpdates
    }
    set {
      updaterController.updater.automaticallyChecksForUpdates = newValue
    }
  }

  /// The interval between automatic update checks.
  var updateCheckInterval: TimeInterval {
    get {
      updaterController.updater.updateCheckInterval
    }
    set {
      updaterController.updater.updateCheckInterval = newValue
    }
  }

  private init() {
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  /// Checks for updates and shows UI if an update is available.
  func checkForUpdates() {
    updaterController.checkForUpdates(nil)
  }

  /// Checks for updates silently in the background.
  func checkForUpdatesInBackground() {
    updaterController.updater.checkForUpdatesInBackground()
  }
}
