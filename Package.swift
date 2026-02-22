// swift-tools-version:5.9
import PackageDescription

/// This Package.swift is used for running unit tests via SwiftPM.
/// The main app is still built via the Xcode project.
/// Run tests with: swift test
///
/// Note: External dependencies (Sparkle) are excluded here
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
        "Models/GitModifiedFile.swift",
        "Services/UpdateManager.swift",
        "Services/ExternalAppManager.swift",
        "Services/DirectoryTreeManager.swift",
        "Services/GitService.swift",
        "Terminal/GhosttyApp.swift",
        "Terminal/GhosttySurfaceView.swift"
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
        "Models/SavedPrompt.swift",
        "Models/LaunchType.swift",

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

        /// Telegram Bot — Models, API, Runtime.
        "Telegram/Models/TelegramModels.swift",
        "Telegram/Models/TelegramAPIModels.swift",
        "Telegram/Models/TelegramTimelineMessage.swift",
        "Telegram/Models/TelegramCommand.swift",
        "Telegram/API/TelegramBotAPIClient.swift",
        "Telegram/API/TelegramMessageChunker.swift",
        "Telegram/Runtime/TelegramBotRuntime.swift",
        "Telegram/Runtime/TelegramCommandHandler.swift",
        "Telegram/Runtime/TelegramPromptExecutor.swift",

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
        "TaskQueue/Runner/RiskyToolDetector.swift",
        "TaskQueue/Orchestrator/TaskPreflight.swift",

        /// Agent — Core models and protocols for native multi-provider agent system.
        "Agent/Core/Models/ProviderID.swift",
        "Agent/Core/Models/ModelDescriptor.swift",
        "Agent/Core/Models/AuthState.swift",
        "Agent/Core/Models/ReasoningVariant.swift",
        "Agent/Core/Models/JSONValue.swift",
        "Agent/Core/Models/AgentMode.swift",
        "Agent/Core/Protocols/TokenStore.swift",
        "Agent/Core/Protocols/OAuthClient.swift",
        "Agent/Core/Protocols/ProviderAdapter.swift",
        "Agent/Core/Protocols/VariantMapper.swift",
        "Agent/Core/Protocols/AgentToolProtocol.swift",
        "Agent/Core/Protocols/PermissionDelegate.swift",
        "Agent/Storage/KeychainTokenStore.swift",
        "Agent/Adapters/Claude/ClaudeAdapter.swift",
        "Agent/Adapters/Claude/ClaudeOAuthClient.swift",
        "Agent/Adapters/Codex/CodexAdapter.swift",
        "Agent/Adapters/Codex/CodexOAuthClient.swift",
        "Agent/Adapters/ZAI/ZAIAdapter.swift",
        "Agent/Adapters/Variants/DefaultVariantMapper.swift",

        /// Agent — Tool system for native agent execution.
        "Agent/Tools/ToolRegistry.swift",
        "Agent/Tools/BashTool.swift",
        "Agent/Tools/ReadFileTool.swift",
        "Agent/Tools/WriteFileTool.swift",
        "Agent/Tools/EditFileTool.swift",
        "Agent/Tools/GlobTool.swift",
        "Agent/Tools/GrepTool.swift",
        "Agent/Tools/WebFetchTool.swift",

        /// Agent — SSE streaming, HTTP transport, request builder, stream parser.
        "Agent/Transport/SSEParser.swift",
        "Agent/Transport/URLSessionHTTPTransport.swift",
        "Agent/Runtime/RequestBuilder.swift",
        "Agent/Runtime/ProviderStreamParser.swift",

        /// Agent — Runtime, loop, permissions, definitions.
        "Agent/Runtime/AgentRuntime.swift",
        "Agent/Runtime/AgentLoop.swift",
        "Agent/Runtime/AgentLoopError.swift",
        "Agent/Permission/RuleBasedPermissions.swift",
        "Agent/Definitions/AgentDefinition.swift",

        /// Agent — NativeAgentTransport (ChatTransport bridge).
        "Agent/Transport/NativeAgentTransport.swift",

        /// Agent — Factory for assembling runtime components.
        "Agent/AgentRuntimeFactory.swift",

        /// Agent — OAuth callback server and flow manager for authorization flows.
        "Agent/Auth/OAuthCallbackServer.swift",
        "Agent/Auth/OAuthFlowManager.swift",

        /// Agent — Context compaction, system prompt, token estimation, subagents.
        "Agent/Runtime/ContextCompactor.swift",
        "Agent/Runtime/SystemPromptBuilder.swift",
        "Agent/Runtime/TokenEstimator.swift",
        "Agent/Tools/TaskTool.swift",
      ]
    ),
    .testTarget(
      name: "SlothyTerminalTests",
      dependencies: ["SlothyTerminalLib"],
      path: "SlothyTerminalTests"
    )
  ]
)
