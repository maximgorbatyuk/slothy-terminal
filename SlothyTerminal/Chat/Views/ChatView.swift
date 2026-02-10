import SwiftUI

/// Main chat interface combining message list and input field.
struct ChatView: View {
  let chatState: ChatState
  @State private var renderAsMarkdown = true

  var body: some View {
    VStack(spacing: 0) {
      if !chatState.conversation.messages.isEmpty || chatState.isLoading {
        ChatStatusBar(renderAsMarkdown: $renderAsMarkdown)
        Divider()
      }

      if chatState.conversation.messages.isEmpty && !chatState.isLoading {
        ChatEmptyStateView()
      } else {
        ChatMessageListView(
          conversation: chatState.conversation,
          isLoading: chatState.isLoading,
          renderAsMarkdown: renderAsMarkdown
        )
      }

      if let error = chatState.error {
        ChatErrorBanner(error: error) {
          chatState.error = nil
        }
      }

      Divider()

      ChatInputView(
        isLoading: chatState.isLoading,
        onSend: { text in
          chatState.sendMessage(text)
        },
        onStop: {
          chatState.cancelResponse()
        }
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(appBackgroundColor)
  }
}

/// Small status bar at the top of the chat with render mode toggle.
struct ChatStatusBar: View {
  @Binding var renderAsMarkdown: Bool

  var body: some View {
    HStack {
      Spacer()

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
}

/// Empty state shown before any messages are sent.
struct ChatEmptyStateView: View {
  private var sendKey: ChatSendKey {
    ConfigManager.shared.config.chatSendKey
  }

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

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Banner showing an error message with dismiss button.
struct ChatErrorBanner: View {
  let error: ChatSessionError
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
