// swift-tools-version:5.9
import PackageDescription

/// This Package.swift is used for running unit tests via SwiftPM.
/// The main app is still built via the Xcode project.
/// Run tests with: swift test

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
  dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.1"),
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")
  ],
  targets: [
    .target(
      name: "SlothyTerminalLib",
      dependencies: [
        "SwiftTerm",
        .product(name: "Sparkle", package: "Sparkle")
      ],
      path: "SlothyTerminal",
      exclude: [
        "Resources",
        "App/SlothyTerminalApp.swift",
        "App/AppDelegate.swift",
        "Views"
      ],
      sources: [
        "Services/StatsParser.swift",
        "Services/RecentFoldersManager.swift",
        "Services/ConfigManager.swift",
        "Services/BuildConfig.swift",
        "Services/Logger.swift",
        "Services/UpdateManager.swift",
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
