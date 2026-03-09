import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Tab Activity")
struct TabActivityTests {
  private let activityIdleWait: UInt64 = 1_200_000_000

  @Test("Terminal command entry marks tab busy and increments command count")
  @MainActor
  func terminalCommandEntryMarksBusy() {
    let tab = Tab(
      workspaceID: UUID(),
      agentType: .terminal,
      workingDirectory: URL(fileURLWithPath: "/tmp")
    )

    #expect(tab.isExecuting == false)
    #expect(tab.usageStats.commandCount == 0)

    tab.handleTerminalCommandEntered()

    #expect(tab.isExecuting)
    #expect(tab.usageStats.commandCount == 1)
  }

  @Test("Auto-run terminal launch settles back to idle after inactivity")
  @MainActor
  func autoRunTerminalLaunchSettlesIdle() async {
    let tab = Tab(
      workspaceID: UUID(),
      agentType: .claude,
      workingDirectory: URL(fileURLWithPath: "/tmp")
    )

    #expect(tab.isExecuting == false)

    tab.handleTerminalLaunch(shouldAutoRunCommand: true)

    #expect(tab.isExecuting)

    try? await Task.sleep(nanoseconds: activityIdleWait)

    #expect(tab.isExecuting == false)
  }

  @Test("Interactive terminal launch stays idle until a command starts")
  @MainActor
  func interactiveTerminalLaunchStaysIdle() {
    let tab = Tab(
      workspaceID: UUID(),
      agentType: .terminal,
      workingDirectory: URL(fileURLWithPath: "/tmp")
    )

    tab.handleTerminalLaunch(shouldAutoRunCommand: false)

    #expect(tab.isExecuting == false)
    #expect(tab.usageStats.commandCount == 0)
  }

  @Test("Terminal activity refresh keeps tab active until output stops")
  @MainActor
  func terminalActivityRefreshExtendsBusyWindow() async {
    let tab = Tab(
      workspaceID: UUID(),
      agentType: .claude,
      workingDirectory: URL(fileURLWithPath: "/tmp")
    )

    tab.recordTerminalActivity()

    #expect(tab.isExecuting)

    try? await Task.sleep(nanoseconds: 400_000_000)
    tab.recordTerminalActivity()

    try? await Task.sleep(nanoseconds: 400_000_000)

    #expect(tab.isExecuting)

    try? await Task.sleep(nanoseconds: activityIdleWait)

    #expect(tab.isExecuting == false)
  }
}
