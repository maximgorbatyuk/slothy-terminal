import Testing

@testable import SlothyTerminalLib

@Suite("Activity Detection Gate")
struct ActivityDetectionGateTests {
  @Test("Repeated schedule attempts are ignored while a check is pending")
  @MainActor
  func repeatedScheduleAttemptsWhilePending() {
    let gate = ActivityDetectionGate()

    #expect(gate.beginSchedule())
    #expect(gate.beginSchedule() == false)
  }

  @Test("Finishing a pending check allows the next schedule")
  @MainActor
  func finishingPendingCheckAllowsNextSchedule() {
    let gate = ActivityDetectionGate()

    #expect(gate.beginSchedule())

    gate.finishSchedule()

    #expect(gate.beginSchedule())
  }

  @Test("Cancelling a pending check allows the next schedule")
  @MainActor
  func cancelingPendingCheckAllowsNextSchedule() {
    let gate = ActivityDetectionGate()

    #expect(gate.beginSchedule())

    gate.cancelSchedule()

    #expect(gate.beginSchedule())
  }
}
