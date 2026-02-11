// swift-tools-version:5.9
import PackageDescription

/// This Package.swift is used for running unit tests via SwiftPM.
/// The main app is still built via the Xcode project.
/// Run tests with: swift test
///
/// Note: External dependencies (SwiftTerm, Sparkle) are excluded here
/// since the tested code doesn't require them. Views and UpdateManager
/// are excluded from the test target.

let package = Package(
  name: "SlothyTerminal",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(
      name: "SlothyTerminalLib",
      targets: ["SlothyTerminalLib"]
    )
  ],
  targets: [
    .target(
      name: "SlothyTerminalLib",
      path: "SlothyTerminal",
      exclude: [
        "Resources",
        "App/SlothyTerminalApp.swift",
        "App/AppDelegate.swift",
        "App/AppState.swift",
        "Views",
        "Chat/Views",
        "Assets.xcassets",
        "Info.plist",
        "Services/UpdateManager.swift",
        "Services/ExternalAppManager.swift",
        "Services/DirectoryTreeManager.swift",
        "Services/GitService.swift"
      ],
      sources: [
        "Services/StatsParser.swift",
        "Services/RecentFoldersManager.swift",
        "Services/ConfigManager.swift",
        "Services/BuildConfig.swift",
        "Services/Logger.swift",
        "Models/UsageStats.swift",
        "Models/AgentType.swift",
        "Models/Tab.swift",
        "Models/AppConfig.swift",
        "Agents/AIAgent.swift",
        "Agents/ClaudeAgent.swift",
        "Agents/OpenCodeAgent.swift",
        "Agents/TerminalAgent.swift",
        "Terminal/PTYController.swift",
        "Models/SavedPrompt.swift",

        /// Chat core (non-UI) — Engine, Models, Parser, Transport, State adapter.
        "Chat/Engine/ChatSessionState.swift",
        "Chat/Engine/ChatSessionEvent.swift",
        "Chat/Engine/ChatSessionError.swift",
        "Chat/Engine/ChatSessionCommand.swift",
        "Chat/Engine/ChatSessionEngine.swift",
        "Chat/Models/ChatMessage.swift",
        "Chat/Models/ChatConversation.swift",
        "Chat/Models/ToolInput.swift",
        "Chat/Models/ChatModelMode.swift",
        "Chat/Parser/StreamEvent.swift",
        "Chat/Parser/StreamEventParser.swift",
        "Chat/Transport/ChatTransport.swift",
        "Chat/Transport/ClaudeCLITransport.swift",
        "Chat/Storage/ChatSessionSnapshot.swift",
        "Chat/Storage/ChatSessionStore.swift",
        "Chat/OpenCode/OpenCodeStreamEvent.swift",
        "Chat/OpenCode/OpenCodeStreamEventParser.swift",
        "Chat/OpenCode/OpenCodeEventMapper.swift",
        "Chat/OpenCode/OpenCodeCLITransport.swift",
        "Chat/State/ChatState.swift",

        /// Task Queue — Models, Storage, State, Runner, Orchestrator.
        "TaskQueue/Models/QueuedTask.swift",
        "TaskQueue/Storage/TaskQueueSnapshot.swift",
        "TaskQueue/Storage/TaskQueueStore.swift",
        "TaskQueue/State/TaskQueueState.swift",
        "TaskQueue/Runner/TaskRunner.swift",
        "TaskQueue/Runner/ClaudeTaskRunner.swift",
        "TaskQueue/Runner/OpenCodeTaskRunner.swift",
        "TaskQueue/Runner/TaskLogCollector.swift",
        "TaskQueue/Orchestrator/TaskOrchestrator.swift",
        "TaskQueue/Orchestrator/TaskPreflight.swift",
      ]
    ),
    .testTarget(
      name: "SlothyTerminalTests",
      dependencies: ["SlothyTerminalLib"],
      path: "SlothyTerminalTests"
    )
  ]
)
