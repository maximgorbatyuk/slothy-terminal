import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Claude Cooldown Service", .serialized)
struct ClaudeCooldownServiceTests {
  @Test("First submission is allowed")
  func firstSubmissionIsAllowed() {
    let service = ClaudeCooldownService()
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(service.attemptSubmission(at: now) == .allowed)
  }

  @Test("Second submission inside 180 seconds is blocked with rounded up remaining seconds")
  func secondSubmissionInsideCooldownIsBlocked() {
    let service = ClaudeCooldownService()
    let start = Date(timeIntervalSince1970: 1_000)
    let retry = Date(timeIntervalSince1970: 1_179.2)

    #expect(service.attemptSubmission(at: start) == .allowed)
    #expect(service.attemptSubmission(at: retry) == .blocked(remainingSeconds: 1))
  }

  @Test("Submission at the exact 180 second boundary is allowed")
  func exactBoundaryIsAllowed() {
    let service = ClaudeCooldownService()
    let start = Date(timeIntervalSince1970: 1_000)
    let retry = Date(timeIntervalSince1970: 1_180)

    #expect(service.attemptSubmission(at: start) == .allowed)
    #expect(service.attemptSubmission(at: retry) == .allowed)
  }

  @Test("Reset clears cooldown state")
  func resetClearsState() {
    let service = ClaudeCooldownService()
    let start = Date(timeIntervalSince1970: 1_000)
    let retry = Date(timeIntervalSince1970: 1_060)

    #expect(service.attemptSubmission(at: start) == .allowed)
    #expect(service.attemptSubmission(at: retry) == .blocked(remainingSeconds: 120))

    service.reset()

    #expect(service.attemptSubmission(at: retry) == .allowed)
  }

  @Test("Shared instance blocks submissions across callers")
  func sharedInstanceBlocksAcrossCallers() {
    let service = ClaudeCooldownService.shared
    let start = Date(timeIntervalSince1970: 1_000)
    let retry = Date(timeIntervalSince1970: 1_060)

    service.reset()
    defer {
      service.reset()
    }

    #expect(service.attemptSubmission(at: start) == .allowed)
    #expect(service.attemptSubmission(at: retry) == .blocked(remainingSeconds: 120))
  }

  @Test("Remaining time formatting is human readable")
  func remainingTimeFormattingIsHumanReadable() {
    #expect(ClaudeCooldownService.formatRemaining(seconds: 59) == "59s")
    #expect(ClaudeCooldownService.formatRemaining(seconds: 61) == "1m 1s")
    #expect(ClaudeCooldownService.formatRemaining(seconds: 180) == "3m 0s")
  }
}
