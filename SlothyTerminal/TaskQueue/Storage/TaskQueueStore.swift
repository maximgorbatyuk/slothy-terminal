import Foundation
import OSLog

/// Persists the task queue to disk as a single JSON file.
///
/// Queue is stored at:
/// `~/Library/Application Support/SlothyTerminal/tasks/queue.json`
///
/// On load, any tasks with `status == .running` are recovered to `.pending`
/// with an `interruptedNote` — the app likely crashed or was force-quit.
class TaskQueueStore {
  static let shared = TaskQueueStore()

  private let fileManager = FileManager.default
  private var saveTimer: Timer?
  private let saveDebounceInterval: TimeInterval = 1.0

  /// Pending snapshot to be saved on next debounce tick.
  private var pendingSnapshot: TaskQueueSnapshot?

  /// Base directory for task queue files.
  private let baseDirectory: URL

  /// Path to the queue snapshot file.
  private var queueFileURL: URL {
    baseDirectory.appendingPathComponent("queue.json")
  }

  private init() {
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
    else {
      self.baseDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SlothyTerminal", isDirectory: true)
        .appendingPathComponent("tasks", isDirectory: true)
      return
    }

    self.baseDirectory = appSupport
      .appendingPathComponent("SlothyTerminal", isDirectory: true)
      .appendingPathComponent("tasks", isDirectory: true)
  }

  /// Creates a store with a custom base directory. Used for testing.
  init(baseDirectory: URL) {
    self.baseDirectory = baseDirectory
  }

  // MARK: - Public API

  /// Saves a queue snapshot with debouncing.
  ///
  /// The actual write happens after `saveDebounceInterval` of inactivity.
  /// Call `saveImmediately()` when the app is quitting to flush pending saves.
  func save(snapshot: TaskQueueSnapshot) {
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

  /// Loads the queue snapshot from disk with crash recovery.
  ///
  /// Any tasks found with `status == .running` are reset to `.pending`
  /// and annotated with an `interruptedNote`.
  func load() -> TaskQueueSnapshot? {
    guard fileManager.fileExists(atPath: queueFileURL.path) else {
      return nil
    }

    do {
      let data = try Data(contentsOf: queueFileURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      var snapshot = try decoder.decode(TaskQueueSnapshot.self, from: data)
      snapshot = recoverInterruptedTasks(in: snapshot)
      return snapshot
    } catch {
      Logger.taskQueue.error("Failed to load task queue: \(error)")
      return nil
    }
  }

  // MARK: - Private

  private func flushPendingSnapshot() {
    guard let snapshot = pendingSnapshot else {
      return
    }

    pendingSnapshot = nil
    writeSnapshot(snapshot)
  }

  private func writeSnapshot(_ snapshot: TaskQueueSnapshot) {
    ensureDirectoryExists()

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(snapshot)
      try data.write(to: queueFileURL, options: .atomic)
    } catch {
      Logger.taskQueue.error("Failed to save task queue: \(error)")
    }
  }

  /// Resets any running tasks to pending — they were interrupted by a crash or force-quit.
  private func recoverInterruptedTasks(in snapshot: TaskQueueSnapshot) -> TaskQueueSnapshot {
    var recovered = snapshot
    var didRecover = false

    for i in recovered.tasks.indices {
      if recovered.tasks[i].status == .running {
        recovered.tasks[i].status = .pending
        recovered.tasks[i].startedAt = nil
        recovered.tasks[i].runAttemptId = nil
        recovered.tasks[i].interruptedNote = "Recovered after app restart — task was running when the app exited."
        didRecover = true
        Logger.taskQueue.info("Recovered interrupted task: \(recovered.tasks[i].id)")
      }
    }

    if didRecover {
      writeSnapshot(recovered)
    }

    return recovered
  }

  private func ensureDirectoryExists() {
    if !fileManager.fileExists(atPath: baseDirectory.path) {
      try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
  }
}
