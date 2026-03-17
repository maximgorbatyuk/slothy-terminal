import SwiftUI

/// Bundles chat appearance preferences for threading through views.
struct ChatAppearance {
  var renderAsMarkdown: Bool = true
  var textSize: ChatMessageTextSize = .medium
  var showTimestamps: Bool = true
  var showTokenMetadata: Bool = true
}

/// Scrollable list of chat messages with auto-scroll to bottom on new content.
struct ChatMessageListView: View {
  let conversation: ChatConversation
  let isLoading: Bool
  var assistantName: String = "Claude"
  var appearance: ChatAppearance = ChatAppearance()
  var currentToolName: String?
  var retryAction: (() -> Void)?

  /// Throttle streaming auto-scroll to avoid per-character animation overhead.
  @State private var lastAutoScrollDate = Date.distantPast

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(conversation.messages) { message in
            MessageBubbleView(
              message: message,
              assistantName: assistantName,
              appearance: appearance,
              currentToolName: message.isStreaming ? currentToolName : nil,
              retryAction: isLastAssistantMessage(message) ? retryAction : nil
            )
            .id(message.id)

            if message.id != conversation.messages.last?.id {
              Divider()
                .padding(.horizontal, 16)
            }
          }

          /// Invisible anchor for scrolling.
          Color.clear
            .frame(height: 1)
            .id("bottom")
        }
      }
      .onChange(of: conversation.messages.count) {
        proxy.scrollTo("bottom", anchor: .bottom)
      }
      .onChange(of: lastMessageText) {
        let now = Date()

        guard now.timeIntervalSince(lastAutoScrollDate) > 0.1 else {
          return
        }

        lastAutoScrollDate = now
        proxy.scrollTo("bottom", anchor: .bottom)
      }
    }
  }

  /// Track the last message's text content to trigger scroll on streaming updates.
  private var lastMessageText: String {
    conversation.messages.last?.textContent ?? ""
  }

  /// Whether this message is the last assistant message (retry target).
  private func isLastAssistantMessage(_ message: ChatMessage) -> Bool {
    guard message.role == .assistant,
          !message.isStreaming
    else {
      return false
    }

    return conversation.messages.last(where: { $0.role == .assistant })?.id == message.id
  }
}
