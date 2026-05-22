import Foundation

/// Errors surfaced when loading or saving a file for the editor tab.
enum EditorError: Error, Equatable {
  /// The file appears to be binary and cannot be opened as text.
  case binaryFile

  /// The file is larger than `FileEditorService.maxInlineSize` and needs explicit confirmation.
  case tooLarge(byteCount: UInt64)

  /// The file no longer exists on disk.
  case missing

  /// On load: the on-disk bytes could not be decoded under any tried text encoding.
  case undecodableOnLoad

  /// On save: the in-memory text contains characters the chosen encoding cannot represent.
  /// Carries the encoding so a Save-As prompt can offer an alternative.
  case unrepresentableOnSave(encoding: String.Encoding)

  /// The process lacks permission to read or write the file.
  case permissionDenied

  /// A lower-level read/write failure (network FS, EIO, etc.).
  case ioFailure(String)
}

/// Reads and writes text files for the editor tab, off the main thread.
///
/// Load path opens a single `FileHandle` and reads size, binary-sniff bytes,
/// and content from the same descriptor so concurrent rewriters can't slip
/// content past the guards.
///
/// Save path follows symlinks (so editing a symlinked dotfile preserves the
/// link), enforces the same size cap as load, and maps Cocoa permission
/// errors to a typed `.permissionDenied` case.
struct FileEditorService {
  /// Maximum file size (bytes) the editor opens or saves without explicit confirmation.
  static let maxInlineSize: Int = 10 * 1024 * 1024

  /// Bytes read from the head of a file when sniffing for binary content.
  static let binarySniffByteCount: Int = 8 * 1024

  /// Encodings the loader tries in order.
  ///
  /// Order matters: `.windowsCP1252` and `.macOSRoman` fail on a small set of
  /// undefined bytes (CP1252 fails on 0x81, 0x8D, 0x8F, 0x90, 0x9D), so they
  /// must come *before* `.isoLatin1`, which is a total mapping and would
  /// otherwise shadow them. `.isoLatin1` stays as the last-resort fallback.
  ///
  /// UTF-16 is intentionally absent — it accepts almost any even-length byte
  /// stream and would shadow the 8-bit fallbacks. UTF-16-with-BOM detection
  /// can be added explicitly later if needed.
  static let fallbackEncodings: [String.Encoding] = [
    .utf8,
    .windowsCP1252,
    .macOSRoman,
    .isoLatin1
  ]

  /// Loads the file at `url` as text. Performs file I/O on a background task.
  static func load(_ url: URL) async throws -> (text: String, encoding: String.Encoding) {
    try await Task.detached(priority: .userInitiated) {
      try loadSync(url)
    }.value
  }

  /// Writes `text` to `url`. Resolves symlinks before writing so editing a
  /// symlinked file does not detach it from its target. Performs file I/O on
  /// a background task.
  static func save(
    _ text: String,
    to url: URL,
    encoding: String.Encoding
  ) async throws {
    try await Task.detached(priority: .userInitiated) {
      try saveSync(text, to: url, encoding: encoding)
    }.value
  }

  /// Sniffs the head of `url` for NUL bytes to detect binary content.
  /// Empty files are treated as non-binary.
  static func isProbablyBinary(_ url: URL) async throws -> Bool {
    try await Task.detached(priority: .userInitiated) {
      try isProbablyBinarySync(url)
    }.value
  }

  // MARK: - Sync core (exposed for tests)

  /// Single-FileHandle load: size, binary sniff, and read all come from the
  /// same descriptor, closing the TOCTOU window between separate filesystem
  /// touches.
  static func loadSync(_ url: URL) throws -> (text: String, encoding: String.Encoding) {
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: url)
    } catch {
      throw mapReadError(error, url: url)
    }

    defer { try? handle.close() }

    let size: UInt64
    do {
      size = try handle.seekToEnd()
      try handle.seek(toOffset: 0)
    } catch {
      throw EditorError.ioFailure(error.localizedDescription)
    }

    if size > UInt64(maxInlineSize) {
      throw EditorError.tooLarge(byteCount: size)
    }

    let head: Data
    let rest: Data
    do {
      head = try handle.read(upToCount: binarySniffByteCount) ?? Data()
      if containsNULBytes(head) {
        throw EditorError.binaryFile
      }

      let remainingBudget = max(maxInlineSize - head.count, 0)
      rest = try handle.read(upToCount: remainingBudget) ?? Data()
    } catch let error as EditorError {
      throw error
    } catch {
      throw EditorError.ioFailure(error.localizedDescription)
    }

    let data = head + rest

    for encoding in fallbackEncodings {
      if let text = String(data: data, encoding: encoding) {
        return (text, encoding)
      }
    }

    throw EditorError.undecodableOnLoad
  }

  /// Resolves symlinks before writing so a symlinked dotfile keeps pointing
  /// at the same target after save. Enforces the same size cap as load.
  static func saveSync(
    _ text: String,
    to url: URL,
    encoding: String.Encoding
  ) throws {
    /// NUL-byte check operates on the SOURCE text (Unicode scalars), not on
    /// the encoded bytes — every ASCII character contains a 0x00 byte under
    /// UTF-16 / UTF-32, so checking encoded bytes would block legitimate
    /// UTF-16 saves. Checking U+0000 in the source means we reject only
    /// buffers that actually contain the NUL character.
    if text.unicodeScalars.contains(where: { $0.value == 0 }) {
      throw EditorError.unrepresentableOnSave(encoding: encoding)
    }

    guard let data = text.data(using: encoding, allowLossyConversion: false) else {
      throw EditorError.unrepresentableOnSave(encoding: encoding)
    }

    if data.count > maxInlineSize {
      throw EditorError.tooLarge(byteCount: UInt64(data.count))
    }

    let writeURL: URL = {
      let resolved = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
      return resolved ? url.resolvingSymlinksInPath() : url
    }()

    do {
      try data.write(to: writeURL, options: .atomic)
    } catch {
      throw mapWriteError(error)
    }
  }

  /// Returns true if `url` looks like a binary file. Throws on read failure
  /// (rather than returning a false negative) so callers fail closed.
  static func isProbablyBinarySync(_ url: URL) throws -> Bool {
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: url)
    } catch {
      throw mapReadError(error, url: url)
    }

    defer { try? handle.close() }

    let head: Data
    do {
      head = try handle.read(upToCount: binarySniffByteCount) ?? Data()
    } catch {
      throw EditorError.ioFailure(error.localizedDescription)
    }

    return containsNULBytes(head)
  }

  private static func containsNULBytes(_ data: Data) -> Bool {
    guard !data.isEmpty else {
      return false
    }

    return data.contains(0)
  }

  /// Maps an arbitrary read error to a typed `EditorError`. Cocoa and POSIX
  /// domains are both checked because Foundation surfaces either depending
  /// on the failure mode.
  private static func mapReadError(_ error: Error, url: URL) -> EditorError {
    if !FileManager.default.fileExists(atPath: url.path) {
      return .missing
    }

    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain {
      switch ns.code {
      case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
        return .missing

      case NSFileReadNoPermissionError:
        return .permissionDenied

      default:
        break
      }
    }

    if ns.domain == NSPOSIXErrorDomain {
      switch Int32(ns.code) {
      case ENOENT:
        return .missing

      case EACCES, EPERM:
        return .permissionDenied

      default:
        break
      }
    }

    return .ioFailure(error.localizedDescription)
  }

  private static func mapWriteError(_ error: Error) -> EditorError {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain {
      switch ns.code {
      case NSFileWriteNoPermissionError:
        return .permissionDenied

      default:
        break
      }
    }

    if ns.domain == NSPOSIXErrorDomain {
      switch Int32(ns.code) {
      case EACCES, EPERM, EROFS:
        return .permissionDenied

      default:
        break
      }
    }

    return .ioFailure(error.localizedDescription)
  }
}
