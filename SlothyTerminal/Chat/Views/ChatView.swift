import SwiftUI

/// Main chat interface combining message list and input field.
struct ChatView: View {
  let chatState: ChatState

  /// Local override for render mode toggle in the status bar.
  /// Initialized from persisted config, can be toggled per-session.
  @State private var renderAsMarkdown = true

  private var configManager: ConfigManager { ConfigManager.shared }

  /// Whether the retry button should be shown on the last message.
  private var canRetry: Bool {
    let state = chatState.sessionState

    switch state {
    case .ready, .failed:
      return true

    default:
      return false
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      if !chatState.conversation.messages.isEmpty || chatState.isLoading {
        ChatStatusBar(
          renderAsMarkdown: $renderAsMarkdown,
          chatState: chatState
        )
        Divider()
      }

      if chatState.conversation.messages.isEmpty && !chatState.isLoading {
        ChatEmptyStateView { suggestion in
          chatState.sendMessage(suggestion)
        }
      } else {
        ChatMessageListView(
          conversation: chatState.conversation,
          isLoading: chatState.isLoading,
          assistantName: assistantDisplayName,
          appearance: chatAppearance,
          currentToolName: chatState.currentToolName,
          retryAction: canRetry ? { chatState.retryLastMessage() } : nil
        )
      }

      if let error = chatState.error {
        ChatErrorBanner(
          error: error,
          onReconnect: canRetry ? { chatState.retryLastMessage() } : nil,
          onDismiss: { chatState.error = nil }
        )
      }

      if chatState.isLoading {
        ChatActivityBar(
          sessionState: chatState.sessionState,
          toolName: chatState.currentToolName
        )
      }

      Divider()

      ChatInputView(
        isLoading: chatState.isLoading,
        askModeBadgeText: askModeBadgeText,
        onSend: { text in
          chatState.sendMessage(text)
        },
        onStop: {
          chatState.cancelResponse()
        }
      )

      ChatComposerStatusBar(
        chatState: chatState,
        agentType: chatState.agentType
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(appBackgroundColor)
    .onAppear {
      renderAsMarkdown = configManager.config.chatRenderMode == .markdown
    }
  }

  private var chatAppearance: ChatAppearance {
    ChatAppearance(
      renderAsMarkdown: renderAsMarkdown,
      textSize: configManager.config.chatMessageTextSize,
      showTimestamps: configManager.config.chatShowTimestamps,
      showTokenMetadata: configManager.config.chatShowTokenMetadata
    )
  }

  private var assistantDisplayName: String {
    guard chatState.agentType == .opencode else {
      return "Claude"
    }

    let modelName = chatState.resolvedMetadata?.resolvedModelID
      ?? chatState.selectedModel?.modelID
      ?? "default"

    return "Opencode / \(modelName)"
  }

  private var askModeBadgeText: String? {
    guard chatState.agentType == .opencode,
          chatState.isOpenCodeAskModeEnabled
    else {
      return nil
    }

    return "Ask mode active: agent asks clarifying questions first"
  }
}

/// Status bar at the top of the chat with connection state, tokens, and controls.
struct ChatStatusBar: View {
  @Binding var renderAsMarkdown: Bool
  let chatState: ChatState

  var body: some View {
    HStack(spacing: 8) {
      /// Connection state indicator.
      Circle()
        .fill(connectionColor)
        .frame(width: 6, height: 6)

      Text(connectionLabel)
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      /// Token totals.
      if totalTokens > 0 {
        Text("\(totalTokens) tokens")
          .font(.system(size: 10))
          .foregroundColor(.secondary.opacity(0.7))
      }

      Spacer()

      /// Clear conversation button.
      if !chatState.conversation.messages.isEmpty {
        Button {
          chatState.clearConversation()
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear conversation")
      }

      /// Markdown/plain toggle.
      Button {
        renderAsMarkdown.toggle()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: renderAsMarkdown ? "doc.richtext" : "doc.plaintext")
            .font(.system(size: 10))

          Text(renderAsMarkdown ? "Markdown" : "Plain text")
            .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(4)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
  }

  private var totalTokens: Int {
    chatState.conversation.totalInputTokens + chatState.conversation.totalOutputTokens
  }

  private var connectionColor: Color {
    switch chatState.sessionState {
    case .ready, .sending, .streaming:
      return .green

    case .starting:
      return .yellow

    case .recovering:
      return .yellow

    case .failed:
      return .red

    case .idle, .terminated, .cancelling:
      return .secondary
    }
  }

  private var connectionLabel: String {
    switch chatState.sessionState {
    case .idle:
      return "Idle"

    case .starting:
      return "Starting..."

    case .ready:
      return "Connected"

    case .sending:
      return "Sending..."

    case .streaming:
      if let tool = chatState.currentToolName {
        return "Running \(tool)..."
      }
      return "Streaming..."

    case .cancelling:
      return "Cancelling..."

    case .recovering(let attempt):
      return "Reconnecting (\(attempt)/3)..."

    case .failed:
      return "Disconnected"

    case .terminated:
      return "Terminated"
    }
  }
}

/// Compact activity indicator shown between messages and input during processing.
struct ChatActivityBar: View {
  let sessionState: ChatSessionState
  let toolName: String?

  var body: some View {
    HStack(spacing: 6) {
      ProgressView()
        .controlSize(.small)

      Text(statusText)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .lineLimit(1)

      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
    .background(Color.secondary.opacity(0.04))
  }

  private var statusText: String {
    switch sessionState {
    case .starting:
      return "Connecting..."

    case .sending:
      return "Sending message..."

    case .streaming:
      if let toolName, !toolName.isEmpty {
        return "Running \(toolName)..."
      }
      return "Generating response..."

    case .recovering(let attempt):
      return "Reconnecting (attempt \(attempt))..."

    default:
      return "Working..."
    }
  }
}

/// Empty state shown before any messages are sent.
struct ChatEmptyStateView: View {
  let onSuggestionTap: (String) -> Void

  private var sendKey: ChatSendKey {
    ConfigManager.shared.config.chatSendKey
  }

  private let suggestions = [
    "Review this codebase",
    "Fix the failing tests",
    "Explain the architecture",
    "Help me refactor",
  ]

  var body: some View {
    VStack(spacing: 16) {
      Spacer()

      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 40))
        .foregroundColor(.secondary.opacity(0.5))

      Text("Start a conversation with Claude")
        .font(.system(size: 14))
        .foregroundColor(.secondary)

      Text("Type a message below to begin. \(sendKey.displayName) to send.")
        .font(.system(size: 12))
        .foregroundColor(.secondary.opacity(0.7))

      /// Suggestion chips.
      HStack(spacing: 8) {
        ForEach(suggestions, id: \.self) { suggestion in
          Button {
            onSuggestionTap(suggestion)
          } label: {
            Text(suggestion)
              .font(.system(size: 11))
              .foregroundColor(.secondary)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Color.secondary.opacity(0.1))
              .cornerRadius(12)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.top, 4)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Banner showing an error message with optional reconnect and dismiss buttons.
struct ChatErrorBanner: View {
  let error: ChatSessionError
  var onReconnect: (() -> Void)?
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 12))
        .foregroundColor(.orange)

      Text(error.localizedDescription)
        .font(.system(size: 12))
        .foregroundColor(.orange)
        .lineLimit(2)

      Spacer()

      if let onReconnect {
        Button {
          onReconnect()
        } label: {
          Text("Reconnect")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
      }

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.orange.opacity(0.1))
  }
}
