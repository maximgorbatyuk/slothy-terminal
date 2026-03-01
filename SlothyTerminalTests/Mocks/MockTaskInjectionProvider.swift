import Foundation
@testable import SlothyTerminalLib

/// Mock injection provider for TaskInjectionRouter tests.
@MainActor
class MockTaskInjectionProvider: TaskInjectionProvider {
  var candidates: [InjectableTabCandidate] = []
  var injectionResultStatus: InjectionStatus = .completed
  var submitReturnsNil = false

  private(set) var submitCalled = false
  private(set) var lastSubmittedRequest: InjectionRequest?
  private(set) var cancelCalled = false
  private(set) var lastCancelledRequestId: UUID?

  func injectableTabCandidates(agentType: AgentType) -> [InjectableTabCandidate] {
    candidates.filter { $0.agentType == agentType }
  }

  func submitInjection(_ request: InjectionRequest) -> InjectionRequest? {
    submitCalled = true
    lastSubmittedRequest = request

    if submitReturnsNil {
      return nil
    }

    var result = request
    result.status = injectionResultStatus
    return result
  }

  func cancelInjection(requestId: UUID) {
    cancelCalled = true
    lastCancelledRequestId = requestId
  }
}
