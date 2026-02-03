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
        "Views",
        "Services/UpdateManager.swift"
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
        "Terminal/PTYController.swift"
      ]
    ),
    .testTarget(
      name: "SlothyTerminalTests",
      dependencies: ["SlothyTerminalLib"],
      path: "SlothyTerminalTests"
    )
  ]
)
