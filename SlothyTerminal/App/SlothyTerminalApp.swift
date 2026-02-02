import SwiftUI

@main
struct SlothyTerminalApp: App {
  @State private var appState = AppState()

  var body: some Scene {
    WindowGroup {
      MainView()
        .environment(appState)
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Claude Tab") {
          appState.showFolderSelector(for: .claude)
        }
        .keyboardShortcut("t", modifiers: .command)

        Button("New GLM Tab") {
          appState.showFolderSelector(for: .glm)
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
      }

      CommandGroup(after: .sidebar) {
        Button("Toggle Sidebar") {
          appState.toggleSidebar()
        }
        .keyboardShortcut("b", modifiers: .command)
      }
    }

    Settings {
      Text("Settings")
        .frame(width: 500, height: 400)
    }
  }
}
