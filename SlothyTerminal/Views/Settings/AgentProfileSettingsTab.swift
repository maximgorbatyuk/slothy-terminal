import SwiftUI

/// Settings tab for configuring the native agent's user profile.
///
/// Controls what context the agent receives in its system prompt:
/// preferred IDE, known project directories, preferred apps,
/// and custom instructions.
struct AgentProfileSettingsTab: View {
  private var configManager = ConfigManager.shared

  /// Ephemeral state for adding new entries.
  @State private var newProjectRoot = ""
  @State private var newAppPurpose = ""
  @State private var newAppName = ""

  var body: some View {
    Form {
      Section("Preferred IDE") {
        TextField(
          "IDE or editor name",
          text: Binding(
            get: { configManager.config.agentProfile.preferredIDE ?? "" },
            set: {
              configManager.config.agentProfile.preferredIDE = $0.isEmpty ? nil : $0
            }
          ),
          prompt: Text("e.g. Xcode, Visual Studio Code, Cursor")
        )
        .textFieldStyle(.roundedBorder)

        Text(
          "The agent will use this app when opening projects or code files. "
          + "If empty, the system default is used."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Project Directories") {
        if configManager.config.agentProfile.projectRoots.isEmpty {
          Text("No project directories configured.")
            .foregroundColor(.secondary)
            .font(.caption)
        } else {
          ForEach(
            Array(configManager.config.agentProfile.projectRoots.enumerated()),
            id: \.offset
          ) { index, path in
            HStack {
              Image(systemName: "folder")
                .foregroundColor(.secondary)

              Text(path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

              Spacer()

              Button {
                configManager.config.agentProfile.projectRoots.remove(at: index)
              } label: {
                Image(systemName: "minus.circle")
                  .foregroundColor(.red)
              }
              .buttonStyle(.plain)
              .help("Remove this directory")
            }
          }
        }

        HStack {
          TextField(
            "Add directory path",
            text: $newProjectRoot,
            prompt: Text("/Users/you/projects")
          )
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            addProjectRoot()
          }

          Button("Add") {
            addProjectRoot()
          }
          .disabled(newProjectRoot.trimmingCharacters(in: .whitespaces).isEmpty)

          Button {
            selectDirectoryViaPanel()
          } label: {
            Image(systemName: "folder.badge.plus")
          }
          .help("Browse for a directory")
        }

        Text(
          "Directories the agent knows about. When you say "
          + "\"open my project\", the agent can look here."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Preferred Apps") {
        if configManager.config.agentProfile.preferredApps.isEmpty {
          Text("No preferred apps configured.")
            .foregroundColor(.secondary)
            .font(.caption)
        } else {
          ForEach(
            configManager.config.agentProfile.preferredApps.sorted(by: { $0.key < $1.key }),
            id: \.key
          ) { purpose, appName in
            HStack {
              Text(purpose)
                .font(.system(.body, design: .monospaced))
                .frame(width: 100, alignment: .leading)

              Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.caption)

              Text(appName)

              Spacer()

              Button {
                configManager.config.agentProfile.preferredApps.removeValue(forKey: purpose)
              } label: {
                Image(systemName: "minus.circle")
                  .foregroundColor(.red)
              }
              .buttonStyle(.plain)
              .help("Remove this mapping")
            }
          }
        }

        HStack(spacing: 8) {
          TextField("Purpose", text: $newAppPurpose, prompt: Text("e.g. browser"))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 140)

          TextField("App name", text: $newAppName, prompt: Text("e.g. Arc"))
            .textFieldStyle(.roundedBorder)
            .onSubmit {
              addPreferredApp()
            }

          Button("Add") {
            addPreferredApp()
          }
          .disabled(
            newAppPurpose.trimmingCharacters(in: .whitespaces).isEmpty
            || newAppName.trimmingCharacters(in: .whitespaces).isEmpty
          )
        }

        Text(
          "Map a purpose to an app name. The agent will prefer these apps "
          + "for the given task (e.g., browser -> Arc, notes -> Obsidian)."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Custom Instructions") {
        TextEditor(
          text: Binding(
            get: { configManager.config.agentProfile.customInstructions ?? "" },
            set: {
              configManager.config.agentProfile.customInstructions = $0.isEmpty ? nil : $0
            }
          )
        )
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 120, maxHeight: 240)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )

        Text(
          "Free-form instructions appended to every agent system prompt. "
          + "Use this for personal coding preferences, workflow rules, "
          + "or project-specific context."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Preview") {
        previewSection
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
  }

  // MARK: - Preview

  @ViewBuilder
  private var previewSection: some View {
    let profile = configManager.config.agentProfile
    let hasContent = profile.preferredIDE != nil
      || !profile.projectRoots.isEmpty
      || !profile.preferredApps.isEmpty
      || profile.customInstructions != nil

    if hasContent {
      VStack(alignment: .leading, spacing: 4) {
        if let ide = profile.preferredIDE {
          Label("IDE: \(ide)", systemImage: "hammer")
            .font(.caption)
        }

        if !profile.projectRoots.isEmpty {
          Label(
            "\(profile.projectRoots.count) project director\(profile.projectRoots.count == 1 ? "y" : "ies")",
            systemImage: "folder"
          )
          .font(.caption)
        }

        if !profile.preferredApps.isEmpty {
          Label(
            "\(profile.preferredApps.count) preferred app\(profile.preferredApps.count == 1 ? "" : "s")",
            systemImage: "app"
          )
          .font(.caption)
        }

        if profile.customInstructions != nil {
          Label("Custom instructions set", systemImage: "text.alignleft")
            .font(.caption)
        }
      }
      .foregroundColor(.secondary)
    } else {
      Text("No profile configured. The agent will use default behavior.")
        .font(.caption)
        .foregroundColor(.secondary)
    }

    Text(
      "This profile is injected into the agent's system prompt for every "
      + "native agent conversation. Changes take effect on the next new session."
    )
    .font(.caption)
    .foregroundColor(.secondary)
  }

  // MARK: - Actions

  private func addProjectRoot() {
    let path = newProjectRoot.trimmingCharacters(in: .whitespaces)

    guard !path.isEmpty else {
      return
    }

    guard !configManager.config.agentProfile.projectRoots.contains(path) else {
      newProjectRoot = ""
      return
    }

    configManager.config.agentProfile.projectRoots.append(path)
    newProjectRoot = ""
  }

  private func addPreferredApp() {
    let purpose = newAppPurpose.trimmingCharacters(in: .whitespaces)
    let name = newAppName.trimmingCharacters(in: .whitespaces)

    guard !purpose.isEmpty,
          !name.isEmpty
    else {
      return
    }

    configManager.config.agentProfile.preferredApps[purpose] = name
    newAppPurpose = ""
    newAppName = ""
  }

  private func selectDirectoryViaPanel() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Select"
    panel.message = "Choose a project directory"

    if panel.runModal() == .OK,
       let url = panel.url
    {
      let path = url.path

      guard !configManager.config.agentProfile.projectRoots.contains(path) else {
        return
      }

      configManager.config.agentProfile.projectRoots.append(path)
    }
  }
}
