import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Tab Labels")
struct TabLabelTests {
  private let dirA = URL(fileURLWithPath: "/tmp/workspace-a")

  @Test("Plain terminal tab uses default label before any command is submitted")
  @MainActor
  func plainTerminalTabUsesDefaultLabelBeforeCommand() {
    let tab = Tab(
      workspaceID: UUID(),
      agentType: .terminal,
      workingDirectory: dirA
    )

    #expect(tab.tabName == "Terminal | cli")
  }

  @Test("Plain terminal tab label reflects the last submitted command")
  @MainActor
  func plainTerminalTabLabelReflectsLastSubmittedCommand() {
    let tab = Tab(
      workspaceID: UUID(),
      agentType: .terminal,
      workingDirectory: dirA
    )

    tab.updateLastSubmittedCommandLabel(from: "npm run dev")

    #expect(tab.tabName == "npm | cli")
  }

  @Test("AI terminal tabs keep their static labels")
  @MainActor
  func aiTerminalTabsKeepStaticLabels() {
    let tab = Tab(
      workspaceID: UUID(),
      agentType: .claude,
      workingDirectory: dirA
    )

    tab.updateLastSubmittedCommandLabel(from: "npm run dev")

    #expect(tab.tabName == "Claude | cli")
  }

  @Test("Submitted command parser extracts the first token")
  func submittedCommandParserExtractsFirstToken() {
    #expect(Tab.commandLabel(from: "git status") == "git")
  }

  @Test("Submitted command parser normalizes executable paths")
  func submittedCommandParserNormalizesExecutablePaths() {
    #expect(Tab.commandLabel(from: "/opt/homebrew/bin/npm run dev") == "npm")
  }

  @Test("Submitted command parser ignores empty input")
  func submittedCommandParserIgnoresEmptyInput() {
    #expect(Tab.commandLabel(from: "   ") == nil)
  }

  @Test("Submitted command parser skips leading environment assignments")
  func submittedCommandParserSkipsLeadingEnvironmentAssignments() {
    #expect(Tab.commandLabel(from: "FOO=1 npm run dev") == "npm")
  }

  @Test("Submitted command parser skips a leading sudo wrapper")
  func submittedCommandParserSkipsLeadingSudoWrapper() {
    #expect(Tab.commandLabel(from: "sudo npm run dev") == "npm")
  }

  @Test("Submitted command parser supports quoted executable paths")
  func submittedCommandParserSupportsQuotedExecutablePaths() {
    #expect(
      Tab.commandLabel(from: "\"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code\" .") == "code"
    )
  }

  @Test("Submitted command parser skips sudo options before the real command")
  func submittedCommandParserSkipsSudoOptionsBeforeTheRealCommand() {
    #expect(Tab.commandLabel(from: "sudo -u root npm install") == "npm")
  }

  @Test("Submitted command parser skips env options before the real command")
  func submittedCommandParserSkipsEnvOptionsBeforeTheRealCommand() {
    #expect(Tab.commandLabel(from: "env -i npm run dev") == "npm")
  }
}
