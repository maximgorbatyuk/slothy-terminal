import Foundation
import OSLog

/// Persists chat sessions to disk and manages the session index.
///
/// Sessions are stored as individual JSON files in:
/// `~/Library/Application Support/SlothyTerminal/chats/`
///
/// An index file maps working directory paths to their most recent session ID,
/// enabling quick lookup without scanning all session files.
class ChatSessionStore {
  static let shared = ChatSessionStore()

  private let fileManager = FileManager.default
  private var saveTimer: Timer?
  private let saveDebounceInterval: TimeInterval = 1.0

  /// Pending snapshot to be saved on next debounce tick.
  private var pendingSnapshot: ChatSessionSnapshot?

  /// Base directory for all chat session files.
  private let baseDirectory: URL

  /// Path to the session index file.
  private var indexFileURL: URL {
    baseDirectory.appendingPathComponent("index.json")
  }

  private init() {
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
    else {
      self.baseDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SlothyTerminal", isDirectory: true)
        .appendingPathComponent("chats", isDirectory: true)
      return
    }

    self.baseDirectory = appSupport
      .appendingPathComponent("SlothyTerminal", isDirectory: true)
      .appendingPathComponent("chats", isDirectory: true)
  }

  /// Creates a store with a custom base directory. Used for testing.
  init(baseDirectory: URL) {
    self.baseDirectory = baseDirectory
  }

  // MARK: - Public API

  /// Saves a session snapshot with debouncing.
  ///
  /// The actual write happens after `saveDebounceInterval` of inactivity.
  /// Call `saveImmediately()` when the app is quitting to flush pending saves.
  func save(snapshot: ChatSessionSnapshot) {
    pendingSnapshot = snapshot
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(
      withTimeInterval: saveDebounceInterval,
      repeats: false
    ) { [weak self] _ in
      self?.flushPendingSnapshot()
    }
  }

  /// Writes any pending snapshot to disk immediately.
  ///
  /// Call this during app termination to ensure the final state is persisted.
  func saveImmediately() {
    saveTimer?.invalidate()
    saveTimer = nil
    flushPendingSnapshot()
  }

  /// Loads the most recent session snapshot for a working directory.
  ///
  /// Returns `nil` if no session exists for this directory.
  func loadLatestSession(for workingDirectory: URL) -> ChatSessionSnapshot? {
    let index = loadIndex()
    let key = workingDirectory.path

    guard let entry = index.entries[key] else {
      return nil
    }

    return loadSnapshot(sessionId: entry.sessionId)
  }

  /// Loads a specific session snapshot by its ID.
  func loadSnapshot(sessionId: String) -> ChatSessionSnapshot? {
    let fileURL = sessionFileURL(for: sessionId)

    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }

    do {
      let data = try Data(contentsOf: fileURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(ChatSessionSnapshot.self, from: data)
    } catch {
      Logger.chat.error("Failed to load session \(sessionId): \(error)")
      return nil
    }
  }

  /// Deletes a session and removes it from the index.
  func deleteSession(sessionId: String) {
    let fileURL = sessionFileURL(for: sessionId)

    try? fileManager.removeItem(at: fileURL)

    /// Remove from index.
    var index = loadIndex()
    index.entries = index.entries.filter { $0.value.sessionId != sessionId }
    saveIndex(index)
  }

  /// Lists all saved session IDs from the index.
  func listSessions() -> [SessionIndexEntry] {
    let index = loadIndex()
    return Array(index.entries.values).sorted { $0.savedAt > $1.savedAt }
  }

  // MARK: - Private

  private func flushPendingSnapshot() {
    guard let snapshot = pendingSnapshot else {
      return
    }

    pendingSnapshot = nil
    writeSnapshot(snapshot)
    updateIndex(for: snapshot)
  }

  private func writeSnapshot(_ snapshot: ChatSessionSnapshot) {
    ensureDirectoryExists()

    let fileURL = sessionFileURL(for: snapshot.sessionId)

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(snapshot)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      Logger.chat.error("Failed to save session \(snapshot.sessionId): \(error)")
    }
  }

  private func updateIndex(for snapshot: ChatSessionSnapshot) {
    var index = loadIndex()

    index.entries[snapshot.workingDirectory] = SessionIndexEntry(
      sessionId: snapshot.sessionId,
      savedAt: snapshot.savedAt
    )

    saveIndex(index)
  }

  private func loadIndex() -> ChatSessionIndex {
    guard fileManager.fileExists(atPath: indexFileURL.path) else {
      return ChatSessionIndex()
    }

    do {
      let data = try Data(contentsOf: indexFileURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(ChatSessionIndex.self, from: data)
    } catch {
      Logger.chat.error("Failed to load session index: \(error)")
      return ChatSessionIndex()
    }
  }

  private func saveIndex(_ index: ChatSessionIndex) {
    ensureDirectoryExists()

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(index)
      try data.write(to: indexFileURL, options: .atomic)
    } catch {
      Logger.chat.error("Failed to save session index: \(error)")
    }
  }

  private func sessionFileURL(for sessionId: String) -> URL {
    baseDirectory.appendingPathComponent("\(sessionId).json")
  }

  private func ensureDirectoryExists() {
    if !fileManager.fileExists(atPath: baseDirectory.path) {
      try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
  }
}
