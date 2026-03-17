import Foundation

/// The mode a tab operates in.
enum TabMode: String, Codable, CaseIterable {
  case terminal
  case chat
  case git

  /// Modes available as a default startup option in settings.
  static var defaultOptions: [TabMode] {
    [.terminal, .chat]
  }

  var displayName: String {
    switch self {
    case .terminal:
      return "Terminal"

    case .chat:
      return "Chat"

    case .git:
      return "Git client"
    }
  }
}

/// Represents a single terminal tab with an AI agent session.
@MainActor
@Observable
class Tab: Identifiable {
  let id: UUID
  let workspaceID: UUID
  let agentType: AgentType?
  let mode: TabMode
  var workingDirectory: URL
  var title: String
  var lastSubmittedCommandLabel: String?
  var isActive: Bool = false
  var hasBackgroundActivity: Bool = false
  var usageStats: UsageStats
  var isTerminalBusy: Bool = false
  private var terminalActivityResetTask: Task<Void, Never>?
  private let terminalActivityIdleDelayNanoseconds: UInt64 = 800_000_000

  /// The saved prompt to pass as the first message to the AI agent.
  let initialPrompt: SavedPrompt?

  /// Optional launch arguments override for terminal tabs.
  /// When set, replaces the agent's default argument construction.
  let launchArgumentsOverride: [String]?

  /// The AI agent for this tab (nil for non-agent modes like `.git`).
  let agent: AIAgent?

  /// The chat state for chat-mode tabs.
  var chatState: ChatState?

  init(
    id: UUID = UUID(),
    workspaceID: UUID,
    agentType: AgentType? = nil,
    workingDirectory: URL,
    title: String? = nil,
    initialPrompt: SavedPrompt? = nil,
    launchArgumentsOverride: [String]? = nil,
    mode: TabMode = .terminal,
    resumeSessionId: String? = nil
  ) {
    assert(
      mode != .git || agentType == nil,
      "Git tabs must not have an agentType"
    )

    self.id = id
    self.workspaceID = workspaceID
    self.agentType = agentType
    self.mode = mode
    self.workingDirectory = workingDirectory
    self.title = title ?? workingDirectory.lastPathComponent
    self.lastSubmittedCommandLabel = nil
    self.initialPrompt = initialPrompt
    self.launchArgumentsOverride = launchArgumentsOverride
    self.usageStats = UsageStats()

    if let agentType {
      let createdAgent = AgentFactory.createAgent(for: agentType)
      self.agent = createdAgent
      self.usageStats.contextWindowLimit = createdAgent.contextWindowLimit
    } else {
      self.agent = nil
    }

    if mode == .chat, let agentType {
      if let resumeSessionId {
        self.chatState = ChatState(
          workingDirectory: workingDirectory,
          agentType: agentType,
          resumeSessionId: resumeSessionId
        )
      } else {
        self.chatState = ChatState(
          workingDirectory: workingDirectory,
          agentType: agentType
        )
      }
    }
  }

  /// Creates a display title combining agent type and directory.
  var displayTitle: String {
    tabName
  }

  /// Stable tab label shown in the tab bar.
  /// Examples: "Claude | chat", "Opencode | cli", "Git client".
  var tabName: String {
    if mode == .git {
      return "Git client"
    }

    if let submittedCommandLabel = submittedCommandLabelForTab {
      return "\(submittedCommandLabel) | \(modeNameForTab)"
    }

    return "\(agentNameForTab) | \(modeNameForTab)"
  }

  nonisolated static func commandLabel(from rawCommandLine: String) -> String? {
    let trimmedCommand = rawCommandLine.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedCommand.isEmpty else {
      return nil
    }

    let tokens = commandTokens(from: trimmedCommand)

    guard !tokens.isEmpty else {
      return nil
    }

    var currentIndex = 0

    while currentIndex < tokens.count {
      let token = tokens[currentIndex]
      let loweredToken = token.lowercased()

      if isEnvironmentAssignment(token) {
        currentIndex += 1
        continue
      }

      if wrapperCommands.contains(loweredToken) {
        currentIndex = nextCommandIndex(afterWrapper: loweredToken, start: currentIndex + 1, in: tokens)
        continue
      }

      return normalizedCommandLabel(from: token)
    }

    return nil
  }

  private nonisolated static let wrapperCommands: Set<String> = ["command", "env", "sudo"]
  private nonisolated static let sudoOptionsRequiringValue: Set<String> = ["-c", "-g", "-h", "-p", "-r", "-t", "-u"]

  private nonisolated static func normalizedCommandLabel(from token: String) -> String {
    if token.contains("/") {
      return URL(fileURLWithPath: token).lastPathComponent
    }

    return token
  }

  private nonisolated static func commandTokens(from commandLine: String) -> [String] {
    var tokens: [String] = []
    var currentToken = ""
    var activeQuote: Character?
    var isEscaping = false

    for character in commandLine {
      if isEscaping {
        currentToken.append(character)
        isEscaping = false
        continue
      }

      if let currentQuote = activeQuote {
        if character == currentQuote {
          activeQuote = nil
        } else if character == "\\" && currentQuote != "'" {
          isEscaping = true
        } else {
          currentToken.append(character)
        }

        continue
      }

      if character == "'" || character == "\"" {
        activeQuote = character
        continue
      }

      if character == "\\" {
        isEscaping = true
        continue
      }

      if character.isWhitespace {
        if !currentToken.isEmpty {
          tokens.append(currentToken)
          currentToken.removeAll(keepingCapacity: true)
        }

        continue
      }

      currentToken.append(character)
    }

    if isEscaping {
      currentToken.append("\\")
    }

    if !currentToken.isEmpty {
      tokens.append(currentToken)
    }

    return tokens
  }

  private nonisolated static func isEnvironmentAssignment(_ token: String) -> Bool {
    guard let separatorIndex = token.firstIndex(of: "="),
          separatorIndex != token.startIndex
    else {
      return false
    }

    let variableName = token[..<separatorIndex]

    guard let firstCharacter = variableName.first,
          firstCharacter == "_" || firstCharacter.isLetter
    else {
      return false
    }

    return variableName.dropFirst().allSatisfy { character in
      character == "_" || character.isLetter || character.isNumber
    }
  }

  private nonisolated static func nextCommandIndex(afterWrapper wrapper: String, start index: Int, in tokens: [String]) -> Int {
    var currentIndex = index

    while currentIndex < tokens.count {
      let token = tokens[currentIndex]
      let loweredToken = token.lowercased()

      if token == "--" {
        return currentIndex + 1
      }

      switch wrapper {
      case "command":
        if token.hasPrefix("-") {
          currentIndex += 1
          continue
        }

      case "env":
        if token.hasPrefix("-") || isEnvironmentAssignment(token) {
          currentIndex += 1
          continue
        }

      case "sudo":
        if token.hasPrefix("-") {
          currentIndex += 1

          if sudoOptionsRequiringValue.contains(loweredToken), currentIndex < tokens.count {
            currentIndex += 1
          }

          continue
        }

      default:
        break
      }

      return currentIndex
    }

    return currentIndex
  }

  func updateLastSubmittedCommandLabel(from rawCommandLine: String) {
    guard mode == .terminal,
          agentType == .terminal,
          let label = Self.commandLabel(from: rawCommandLine)
    else {
      return
    }

    lastSubmittedCommandLabel = label
  }

  /// Agent label used in tab/window titles.
  private var agentNameForTab: String {
    switch agentType {
    case .claude:
      return "Claude"

    case .opencode:
      return "Opencode"

    case .terminal:
      return "Terminal"

    case nil:
      return ""
    }
  }

  private var submittedCommandLabelForTab: String? {
    guard mode == .terminal,
          agentType == .terminal,
          let lastSubmittedCommandLabel
    else {
      return nil
    }

    return lastSubmittedCommandLabel
  }

  /// Mode label used in tab/window titles.
  private var modeNameForTab: String {
    switch mode {
    case .chat:
      return "chat"

    case .terminal:
      return "cli"

    case .git:
      return "git"
    }
  }

  /// The command to execute for this tab's agent.
  var command: String {
    agent?.command ?? ""
  }

  /// The arguments to pass to the agent command.
  /// Uses launch override if set, otherwise delegates to the agent.
  var arguments: [String] {
    guard let agent else {
      return []
    }

    if let launchArgumentsOverride {
      return launchArgumentsOverride
    }

    if let prompt = initialPrompt {
      return agent.argsWithPrompt(prompt.promptText)
    }

    return agent.defaultArgs
  }

  /// The environment variables for the agent process.
  var environment: [String: String] {
    agent?.environmentVariables ?? [:]
  }

  /// Checks if the agent is available (installed).
  var isAgentAvailable: Bool {
    agent?.isAvailable() ?? false
  }

  /// Whether this tab is actively executing work.
  var isExecuting: Bool {
    switch mode {
    case .chat:
      return chatState?.isLoading ?? false

    case .terminal:
      return isTerminalBusy

    case .git:
      return false
    }
  }

  /// Marks the terminal tab as busy.
  /// Driven by Ghostty command lifecycle events.
  func markTerminalBusy() {
    guard !isTerminalBusy else {
      return
    }

    isTerminalBusy = true
  }

  /// Records that a terminal command has started running.
  func handleTerminalCommandEntered() {
    usageStats.incrementCommandCount()
    recordTerminalActivity()
  }

  /// Marks auto-run terminal sessions as busy as soon as they launch.
  func handleTerminalLaunch(shouldAutoRunCommand: Bool) {
    guard shouldAutoRunCommand else {
      return
    }

    recordTerminalActivity()
  }

  /// Records terminal activity and clears the busy state after a short idle window.
  func recordTerminalActivity() {
    let idleDelayNanoseconds = terminalActivityIdleDelayNanoseconds

    markTerminalBusy()
    terminalActivityResetTask?.cancel()

    terminalActivityResetTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: idleDelayNanoseconds)

      guard !Task.isCancelled else {
        return
      }

      self?.markTerminalIdle()
    }
  }

  /// Marks the terminal tab as idle.
  func markTerminalIdle() {
    terminalActivityResetTask?.cancel()
    terminalActivityResetTask = nil

    guard isTerminalBusy else {
      return
    }

    isTerminalBusy = false
  }

  /// Marks the tab as having unseen background terminal output.
  func markBackgroundActivity() {
    guard !isActive,
          !hasBackgroundActivity
    else {
      return
    }

    hasBackgroundActivity = true
  }

  /// Clears the unseen background terminal output indicator.
  func clearBackgroundActivity() {
    guard hasBackgroundActivity else {
      return
    }

    hasBackgroundActivity = false
  }
}
