import AppKit
import Foundation
import os

/// Handles macOS Services menu invocations originating from Finder.
///
/// Selectors must match the `NSMessage` values in `Info.plist` exactly,
/// using the Objective-C signature `<message>:userData:error:`. A mismatch
/// causes macOS to silently drop the invocation.
final class FinderServicesProvider: NSObject {
  /// Selector: `newTabHere:userData:error:`
  @objc func newTabHere(
    _ pboard: NSPasteboard,
    userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    guard let folder = Self.firstFolder(from: pboard) else {
      Self.setError("No folder selected.", into: error)
      return
    }

    FinderServiceRequestQueue.shared.dispatchOrQueue(.newTab(folder: folder))
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  /// Selector: `newWindowHere:userData:error:`
  @objc func newWindowHere(
    _ pboard: NSPasteboard,
    userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    guard let folder = Self.firstFolder(from: pboard) else {
      Self.setError("No folder selected.", into: error)
      return
    }

    FinderServiceRequestQueue.shared.dispatchOrQueue(.newWindow(folder: folder))
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  /// Reads file URLs from the pasteboard and returns the first one that points
  /// to an existing directory. Multi-selection collapses to a single folder
  /// per the plan's §2a (predictable, matches Ghostty).
  static func firstFolder(from pboard: NSPasteboard) -> URL? {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]

    guard let urls = pboard.readObjects(
      forClasses: [NSURL.self],
      options: options
    ) as? [URL] else {
      return nil
    }

    let fileManager = FileManager.default

    return urls.first { url in
      var isDirectory: ObjCBool = false
      let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      return exists && isDirectory.boolValue
    }
  }

  static func setError(_ message: String, into pointer: AutoreleasingUnsafeMutablePointer<NSString>) {
    pointer.pointee = message as NSString
    Logger.app.error("Finder service: \(message, privacy: .public)")
  }
}
