import Testing

@testable import SlothyTerminalLib

@Suite("Activity Detection Gate")
struct ActivityDetectionGateTests {
  @Test("Latest scheduled render version wins while work is pending")
  @MainActor
  func latestScheduledRenderVersionWins() {
    let gate = ActivityDetectionGate()

    #expect(gate.noteRender())
    #expect(gate.noteRender() == false)
    #expect(gate.beginScheduledCheck() == 2)
  }

  @Test("Render during in-flight work reschedules latest version")
  @MainActor
  func renderDuringInFlightWorkReschedulesLatestVersion() {
    let gate = ActivityDetectionGate()

    #expect(gate.noteRender())
    let version = gate.beginScheduledCheck()

    #expect(version == 1)
    #expect(gate.noteRender() == false)
    #expect(gate.completeScheduledCheck(for: 1))
    #expect(gate.beginScheduledCheck() == 2)
  }

  @Test("Cancel clears pending and in-flight state")
  @MainActor
  func cancelClearsPendingAndInFlightState() {
    let gate = ActivityDetectionGate()

    #expect(gate.noteRender())
    #expect(gate.beginScheduledCheck() == 1)

    gate.cancelAll()

    #expect(gate.beginScheduledCheck() == nil)
    #expect(gate.noteRender())
    #expect(gate.beginScheduledCheck() == 2)
  }

  @Test("Cancelling invalidates the old in-flight result")
  @MainActor
  func cancelInvalidatesOldInFlightResult() {
    let gate = ActivityDetectionGate()

    #expect(gate.noteRender())
    #expect(gate.beginScheduledCheck() == 1)
    #expect(gate.shouldAcceptResult(for: 1))

    gate.cancelAll()

    #expect(gate.shouldAcceptResult(for: 1) == false)
  }

  @Test("Completing stale version does not reopen scheduling")
  @MainActor
  func completingStaleVersionDoesNotReopenScheduling() {
    let gate = ActivityDetectionGate()

    #expect(gate.noteRender())
    #expect(gate.beginScheduledCheck() == 1)

    gate.cancelAll()

    #expect(gate.completeScheduledCheck(for: 1) == false)
    #expect(gate.beginScheduledCheck() == nil)
  }
}
