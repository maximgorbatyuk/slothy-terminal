import Foundation

/// Single-folder request originating from a Finder Services menu invocation.
enum FinderServiceRequest: Equatable {
  case newTab(folder: URL)
  case newWindow(folder: URL)
}

/// Sink invoked on the main actor with each Finder service request.
typealias FinderServiceSink = @MainActor (FinderServiceRequest) -> Void

/// Buffers Finder service requests that arrive before the SwiftUI scene is
/// ready to dispatch them (cold-launch case), then flushes the queue once
/// the scene attaches a sink in `.onAppear`.
///
/// Thread-safe: callbacks from `NSApp.servicesProvider` may run on any thread,
/// while the sink is invoked on the main actor.
final class FinderServiceRequestQueue {
  static let shared = FinderServiceRequestQueue()

  private var pending: [FinderServiceRequest] = []
  private var sink: FinderServiceSink?
  private let lock = NSLock()

  private init() {}

  /// Routes a request to the sink if attached; otherwise queues it for later.
  func dispatchOrQueue(_ request: FinderServiceRequest) {
    lock.lock()
    let activeSink = sink
    if activeSink == nil {
      pending.append(request)
    }
    lock.unlock()

    if let activeSink {
      Task { @MainActor in
        activeSink(request)
      }
    }
  }

  /// First attach wins; subsequent calls are no-ops. Guards against repeated
  /// SwiftUI `.onAppear` firings replacing the sink and re-driving the (already
  /// drained) pending buffer. Drains pending requests on the main actor.
  func attach(_ sink: @escaping FinderServiceSink) {
    lock.lock()
    guard self.sink == nil else {
      lock.unlock()
      return
    }
    let drained = pending
    pending.removeAll()
    self.sink = sink
    lock.unlock()

    guard !drained.isEmpty else {
      return
    }

    Task { @MainActor in
      for request in drained {
        sink(request)
      }
    }
  }

  /// Test seam — clears state between unit tests.
  func resetForTesting() {
    lock.lock()
    pending.removeAll()
    sink = nil
    lock.unlock()
  }

  /// Test seam — exposes pending count without dispatching.
  var pendingCountForTesting: Int {
    lock.lock()
    defer { lock.unlock() }
    return pending.count
  }
}
