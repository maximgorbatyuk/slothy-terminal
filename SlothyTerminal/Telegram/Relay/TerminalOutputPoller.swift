import Foundation
import OSLog

/// Polls a terminal surface's viewport for new output and emits batched text chunks.
///
/// Checks the surface's dirty flag every ~800ms. When dirty, reads the viewport,
/// diffs against the previous snapshot, and accumulates new lines. Flushes when
/// the buffer exceeds 400 chars, 1.5s have elapsed, or the poller stops.
@MainActor
class TerminalOutputPoller {
  private let tabId: UUID
  private let registry: TerminalSurfaceRegistry
  private var previousLines: [String] = []
  private var buffer: String = ""
  private var bufferFirstAppendTime: Date?
  private var pollingTask: Task<Void, Never>?
  private var onOutput: ((String) -> Void)?
  private var onSurfaceLost: (() -> Void)?

  private let pollInterval: UInt64 = 800_000_000
  private let flushCharThreshold = 400
  private let flushTimeThreshold: TimeInterval = 1.5

  init(tabId: UUID, registry: TerminalSurfaceRegistry? = nil) {
    self.tabId = tabId
    self.registry = registry ?? .shared
  }

  /// Starts polling. Calls `handler` with batched output text and `surfaceLost` if the surface disappears.
  func start(handler: @escaping (String) -> Void, surfaceLost: @escaping () -> Void) {
    guard pollingTask == nil else {
      return
    }

    onOutput = handler
    onSurfaceLost = surfaceLost

    // Take initial snapshot so we don't emit existing viewport content.
    if let surface = registry.surface(for: tabId) {
      surface.clearRenderDirty()

      if let text = surface.readViewportText() {
        previousLines = ANSIStripper.strip(text).split(
          separator: "\n",
          omittingEmptySubsequences: false
        ).map(String.init)
      }
    }

    pollingTask = Task { [weak self] in
      await self?.pollLoop()
    }
  }

  /// Stops polling and flushes any remaining buffered output.
  func stop() {
    pollingTask?.cancel()
    pollingTask = nil
    flushBuffer()
    onOutput = nil
    onSurfaceLost = nil
  }

  // MARK: - Polling

  private func pollLoop() async {
    while !Task.isCancelled {
      do {
        try await Task.sleep(nanoseconds: pollInterval)
      } catch {
        break
      }

      guard let surface = registry.surface(for: tabId) else {
        Logger.telegram.info("Relay surface lost for tab \(self.tabId.uuidString)")
        flushBuffer()
        onSurfaceLost?()
        return
      }

      guard surface.hasNewRenderSinceLastRead else {
        flushIfTimedOut()
        continue
      }

      surface.clearRenderDirty()

      guard let text = surface.readViewportText() else {
        flushIfTimedOut()
        continue
      }

      let stripped = ANSIStripper.strip(text)
      let currentLines = stripped.split(
        separator: "\n",
        omittingEmptySubsequences: false
      ).map(String.init)

      let newContent = diffLines(previous: previousLines, current: currentLines)
      previousLines = currentLines

      if !newContent.isEmpty {
        appendToBuffer(newContent)
      }

      flushIfNeeded()
    }
  }

  // MARK: - Line Diffing

  private func diffLines(previous: [String], current: [String]) -> String {
    ViewportDiffer.diffLines(previous: previous, current: current)
  }

  // MARK: - Output Batching

  private func appendToBuffer(_ text: String) {
    if buffer.isEmpty {
      bufferFirstAppendTime = Date()
    }

    if !buffer.isEmpty {
      buffer += "\n"
    }

    buffer += text
  }

  private func flushIfNeeded() {
    if buffer.count >= flushCharThreshold {
      flushBuffer()
      return
    }

    flushIfTimedOut()
  }

  private func flushIfTimedOut() {
    guard let firstAppend = bufferFirstAppendTime,
          Date().timeIntervalSince(firstAppend) >= flushTimeThreshold
    else {
      return
    }

    flushBuffer()
  }

  private func flushBuffer() {
    guard !buffer.isEmpty else {
      return
    }

    let text = buffer
    buffer = ""
    bufferFirstAppendTime = nil
    onOutput?(text)
  }
}
