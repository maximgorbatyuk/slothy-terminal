import Foundation

/// Result type for directory resolution.
enum TelegramDirectoryResult {
  case success(URL)
  case failure(String)
}

/// Generates responses for bot slash commands.
enum TelegramCommandHandler {
  /// Returns the help text listing available commands.
  static func helpText() -> String {
    """
    Available commands:
    /help - Show this message
    /report - Show current tab/session status
    /open_directory - Open a tab for the configured directory
    /new_task - Create a task via guided flow
    /relay_tabs - List terminal tabs available for relay
    /relay_start - Start relaying to a terminal tab
    /relay_stop - Stop the active relay
    /relay_status - Show relay session info
    /relay_interrupt - Send Ctrl+C to the relay tab

    Send any other text to execute it in the active AI terminal tab (Claude/OpenCode).
    If no AI tab is active, relay session is used as fallback.
    /new_task scheduling accepts: immediately | queue
    """
  }

  /// Resolves and validates the directory for the /open-directory command.
  static func resolveOpenDirectory(
    rootPath: String?,
    subpath: String?
  ) -> TelegramDirectoryResult {
    guard let rootPath,
          !rootPath.isEmpty
    else {
      return .failure("No root directory configured in Telegram settings.")
    }

    let expandedRoot = NSString(string: rootPath).expandingTildeInPath
    let rootURL = URL(fileURLWithPath: expandedRoot)
      .standardizedFileURL
      .resolvingSymlinksInPath()

    var rootIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &rootIsDirectory),
          rootIsDirectory.boolValue
    else {
      return .failure("Root directory not found: \(rootURL.path)")
    }

    var directoryURL = rootURL

    if let subpath,
       !subpath.isEmpty
    {
      if subpath.hasPrefix("/") {
        return .failure("Subfolder must be a relative path.")
      }

      directoryURL = directoryURL.appendingPathComponent(subpath)
    }

    directoryURL = directoryURL
      .standardizedFileURL
      .resolvingSymlinksInPath()

    /// Verify the directory exists.
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)

    guard exists,
          isDirectory.boolValue
    else {
      return .failure("Directory not found: \(directoryURL.path)")
    }

    /// Safety check: resolved path must be under the root.
    let resolvedRootComponents = rootURL.pathComponents
    let resolvedDirectoryComponents = directoryURL.pathComponents

    guard resolvedDirectoryComponents.starts(with: resolvedRootComponents) else {
      return .failure("Path traversal blocked: resolved path is outside root directory.")
    }

    return .success(directoryURL)
  }
}
