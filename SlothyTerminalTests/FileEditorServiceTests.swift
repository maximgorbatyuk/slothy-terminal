import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("FileEditorService")
struct FileEditorServiceTests {
  @Test("Loads and saves UTF-8 round-trip")
  func loadsAndSavesUtf8RoundTrip() throws {
    let url = try makeTempFileURL(extension: "txt")
    let original = "hello\nфыва\n中文\nemoji 🦥\n"

    try FileEditorService.saveSync(original, to: url, encoding: .utf8)
    let (text, encoding) = try FileEditorService.loadSync(url)

    #expect(text == original)
    #expect(encoding == .utf8)

    try? FileManager.default.removeItem(at: url)
  }

  @Test("Refuses files with NUL bytes as binary")
  func refusesBinaryFiles() throws {
    let url = try makeTempFileURL(extension: "bin")
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    bytes.append(contentsOf: Array(repeating: 0x00, count: 32))
    try Data(bytes).write(to: url)

    #expect(throws: EditorError.binaryFile) {
      _ = try FileEditorService.loadSync(url)
    }

    try? FileManager.default.removeItem(at: url)
  }

  @Test("Refuses files above the inline size threshold")
  func refusesOversizeFiles() throws {
    let url = try makeTempFileURL(extension: "txt")
    let byteCount = FileEditorService.maxInlineSize + 1024
    let payload = Data(repeating: 0x41, count: byteCount)
    try payload.write(to: url)

    do {
      _ = try FileEditorService.loadSync(url)
      Issue.record("Expected tooLarge to be thrown")
    } catch let EditorError.tooLarge(size) {
      #expect(size >= UInt64(byteCount))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    try? FileManager.default.removeItem(at: url)
  }

  @Test("Throws missing for a non-existent path")
  func throwsMissingForNonExistentFile() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("slothy-editor-missing-\(UUID().uuidString).txt")

    #expect(throws: EditorError.missing) {
      _ = try FileEditorService.loadSync(url)
    }
  }

  @Test("Empty file loads as empty UTF-8 string")
  func emptyFileLoadsAsEmpty() throws {
    let url = try makeTempFileURL(extension: "txt")
    try Data().write(to: url)

    let (text, encoding) = try FileEditorService.loadSync(url)

    #expect(text.isEmpty)
    #expect(encoding == .utf8)

    try? FileManager.default.removeItem(at: url)
  }

  @Test("Non-UTF-8 bytes decode under windowsCP1252 before isoLatin1")
  func fallsBackToCP1252ForLatin1ValidBytes() throws {
    let url = try makeTempFileURL(extension: "txt")
    /// "Hello é\n" — 0xE9 is é in both CP1252 and Latin-1, but CP1252 is
    /// the first non-UTF-8 fallback and must win.
    let payload = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0xE9, 0x0A])
    try payload.write(to: url)

    let (text, encoding) = try FileEditorService.loadSync(url)

    #expect(text == "Hello \u{00E9}\n")
    #expect(encoding == .windowsCP1252)

    try? FileManager.default.removeItem(at: url)
  }

  @Test("CP1252-specific bytes (smart quotes) decode correctly")
  func decodesCP1252SmartQuotes() throws {
    let url = try makeTempFileURL(extension: "txt")
    /// 0x91/0x92/0x93/0x94 are curly quotes in CP1252 (U+2018..U+201D)
    /// but undefined C1 control characters in Latin-1.
    let payload = Data([0x91, 0x68, 0x69, 0x92])
    try payload.write(to: url)

    let (text, encoding) = try FileEditorService.loadSync(url)

    #expect(encoding == .windowsCP1252)
    #expect(text == "\u{2018}hi\u{2019}")

    try? FileManager.default.removeItem(at: url)
  }

  @Test("saveSync throws unrepresentableOnSave for chars that don't fit the encoding")
  func saveSyncRejectsUnrepresentableChars() throws {
    let url = try makeTempFileURL(extension: "txt")
    let emoji = "Привет 🦥"

    do {
      try FileEditorService.saveSync(emoji, to: url, encoding: .isoLatin1)
      Issue.record("Expected unrepresentableOnSave")
    } catch let EditorError.unrepresentableOnSave(encoding) {
      #expect(encoding == .isoLatin1)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    try? FileManager.default.removeItem(at: url)
  }

  @Test("saveSync rejects buffers containing NUL bytes")
  func saveSyncRejectsNULBytes() throws {
    let url = try makeTempFileURL(extension: "txt")
    let withNUL = "abc\u{0000}def"

    do {
      try FileEditorService.saveSync(withNUL, to: url, encoding: .utf8)
      Issue.record("Expected unrepresentableOnSave")
    } catch let EditorError.unrepresentableOnSave(encoding) {
      #expect(encoding == .utf8)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    try? FileManager.default.removeItem(at: url)
  }

  @Test("saveSync writes through symlinks instead of replacing them")
  func saveSyncFollowsSymlinks() throws {
    let target = try makeTempFileURL(extension: "txt")
    let link = try makeTempFileURL(extension: "txt")

    try "original\n".data(using: .utf8)!.write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    try FileEditorService.saveSync("updated\n", to: link, encoding: .utf8)

    /// The symlink at `link` should still be a symlink — not replaced by a regular file.
    let linkValues = try link.resourceValues(forKeys: [.isSymbolicLinkKey])
    #expect(linkValues.isSymbolicLink == true)

    /// The target file should now contain the updated content.
    let resolvedContent = try String(contentsOf: target, encoding: .utf8)
    #expect(resolvedContent == "updated\n")

    try? FileManager.default.removeItem(at: link)
    try? FileManager.default.removeItem(at: target)
  }

  @Test("saveSync refuses payloads above the inline size threshold")
  func saveSyncRefusesOversizePayloads() throws {
    let url = try makeTempFileURL(extension: "txt")
    /// String repeating 'A' enough to exceed maxInlineSize in UTF-8.
    let huge = String(repeating: "A", count: FileEditorService.maxInlineSize + 16)

    do {
      try FileEditorService.saveSync(huge, to: url, encoding: .utf8)
      Issue.record("Expected tooLarge on save")
    } catch let EditorError.tooLarge(size) {
      #expect(size > UInt64(FileEditorService.maxInlineSize))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    try? FileManager.default.removeItem(at: url)
  }

  @Test("Binary sniff returns false for empty files")
  func binarySniffEmptyFile() throws {
    let url = try makeTempFileURL(extension: "txt")
    try Data().write(to: url)

    #expect(try FileEditorService.isProbablyBinarySync(url) == false)

    try? FileManager.default.removeItem(at: url)
  }

  @Test("Binary sniff throws missing for non-existent file")
  func binarySniffMissingFile() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("slothy-editor-missing-\(UUID().uuidString).txt")

    #expect(throws: EditorError.missing) {
      _ = try FileEditorService.isProbablyBinarySync(url)
    }
  }

  // MARK: - Helpers

  private func makeTempFileURL(extension ext: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
    let name = "slothy-editor-\(UUID().uuidString).\(ext)"
    return directory.appendingPathComponent(name)
  }
}
