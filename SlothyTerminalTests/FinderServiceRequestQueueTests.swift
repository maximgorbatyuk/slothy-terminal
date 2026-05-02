import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Finder Service Request Queue", .serialized)
struct FinderServiceRequestQueueTests {
  private let folderA = URL(fileURLWithPath: "/tmp/finder-service-a")
  private let folderB = URL(fileURLWithPath: "/tmp/finder-service-b")

  private func freshQueue() -> FinderServiceRequestQueue {
    let queue = FinderServiceRequestQueue.shared
    queue.resetForTesting()
    return queue
  }

  @Test("Attaching after dispatch drains pending requests in order")
  func attachAfterDispatch_drainsInOrder() async {
    let queue = freshQueue()

    queue.dispatchOrQueue(.newTab(folder: folderA))
    queue.dispatchOrQueue(.newWindow(folder: folderB))

    let received = await withCheckedContinuation { (continuation: CheckedContinuation<[FinderServiceRequest], Never>) in
      let collector = DispatchedRequestCollector(expected: 2) { result in
        continuation.resume(returning: result)
      }

      queue.attach { request in
        collector.append(request)
      }
    }

    #expect(received == [.newTab(folder: folderA), .newWindow(folder: folderB)])
    #expect(queue.pendingCountForTesting == 0)
  }

  @Test("Dispatching after attach routes immediately, no buffering")
  func dispatchAfterAttach_routesImmediately() async {
    let queue = freshQueue()

    let received = await withCheckedContinuation { (continuation: CheckedContinuation<FinderServiceRequest, Never>) in
      queue.attach { request in
        continuation.resume(returning: request)
      }

      queue.dispatchOrQueue(.newTab(folder: folderA))
    }

    #expect(received == .newTab(folder: folderA))
    #expect(queue.pendingCountForTesting == 0)
  }

  @Test("Repeated attach is a no-op; first sink wins")
  func attachIsIdempotent() async {
    let queue = freshQueue()

    let firstSinkReceived = await withCheckedContinuation { (continuation: CheckedContinuation<FinderServiceRequest, Never>) in
      queue.attach { request in
        continuation.resume(returning: request)
      }

      /// A second attach must NOT replace the first sink.
      queue.attach { _ in
        Issue.record("Second sink must not be invoked")
      }

      queue.dispatchOrQueue(.newTab(folder: folderA))
    }

    #expect(firstSinkReceived == .newTab(folder: folderA))
  }

  @Test("FinderServiceRequest equality distinguishes case and folder")
  func requestEquality() {
    #expect(FinderServiceRequest.newTab(folder: folderA) == .newTab(folder: folderA))
    #expect(FinderServiceRequest.newTab(folder: folderA) != .newTab(folder: folderB))
    #expect(FinderServiceRequest.newTab(folder: folderA) != .newWindow(folder: folderA))
  }
}

/// Collects requests delivered through a sink and resumes a continuation
/// once the expected count is reached. Mutations are single-threaded by
/// construction — only the `@MainActor` sink invokes `append`.
private final class DispatchedRequestCollector {
  private var collected: [FinderServiceRequest] = []
  private let expected: Int
  private let onComplete: ([FinderServiceRequest]) -> Void
  private var hasCompleted = false

  init(expected: Int, onComplete: @escaping ([FinderServiceRequest]) -> Void) {
    self.expected = expected
    self.onComplete = onComplete
  }

  func append(_ request: FinderServiceRequest) {
    collected.append(request)

    guard !hasCompleted, collected.count == expected else {
      return
    }

    hasCompleted = true
    onComplete(collected)
  }
}
