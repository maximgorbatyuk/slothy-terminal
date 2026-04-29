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
        "Views",
        "Assets.xcassets",
        "Info.plist",
        "Services/UpdateManager.swift",
        "Services/ExternalAppManager.swift",
        "Services/DirectoryTreeManager.swift",
        "Terminal/GhosttyApp.swift",
        "Terminal/GhosttySurfaceView.swift"
      ],
      sources: [
        "Services/RecentFoldersManager.swift",
        "Services/ConfigManager.swift",
        "Services/BuildConfig.swift",
        "Services/Logger.swift",
        "Services/ActivityDetectionGate.swift",
        "Services/ClaudeCooldownService.swift",
        "Services/DirectoryTreeScanner.swift",

        "Services/OpenCodeCLIService.swift",
        "Services/PromptFilesScanner.swift",
        "Services/PythonScriptScanner.swift",
        "Services/GitProcessRunner.swift",
        "Services/GitService.swift",
        "Services/GitWorkingTreeService.swift",
        "Services/GitStatsService.swift",
        "Services/GraphLaneCalculator.swift",
        "Services/ANSIStripper.swift",
        "Services/UsageKeychainStore.swift",
        "Services/UsageService.swift",
        "Services/CursorUsageProvider.swift",
        "Models/AgentType.swift",
        "Models/GitDiffModels.swift",
        "Models/GitWorkingTreeModels.swift",
        "Models/MakeCommitComposerState.swift",
        "Models/GitStats.swift",
        "Models/CommitFileChange.swift",
        "Models/GitTab.swift",
        "Models/Tab.swift",
        "Models/TerminalCommandCaptureBuffer.swift",
        "Models/AppConfig.swift",
        "Models/SettingsSection.swift",
        "Models/Workspace.swift",
        "Models/WorkspaceSplitState.swift",
        "App/AppState.swift",
        "Agents/AIAgent.swift",
        "Agents/ClaudeAgent.swift",
        "Agents/OpenCodeAgent.swift",
        "Agents/TerminalAgent.swift",
        "Models/PromptFile.swift",
        "Models/SavedPrompt.swift",
        "Models/LaunchType.swift",
        "Models/ChatModelMode.swift",
        "Models/UsageModels.swift",

        /// Injection — Models, Registry, Orchestrator.
        "Injection/Models/InjectionPayload.swift",
        "Injection/Models/InjectionTarget.swift",
        "Injection/Models/InjectionRequest.swift",
        "Injection/Models/InjectionResult.swift",
        "Injection/Models/InjectionEvent.swift",
        "Injection/Registry/TerminalSurfaceRegistry.swift",
        "Injection/Orchestrator/InjectionOrchestrator.swift",
      ]
    ),
    .testTarget(
      name: "SlothyTerminalTests",
      dependencies: ["SlothyTerminalLib"],
      path: "SlothyTerminalTests"
    )
  ]
)
