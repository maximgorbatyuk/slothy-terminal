import SwiftUI

/// Scrollable list of chat messages with auto-scroll to bottom on new content.
struct ChatMessageListView: View {
  let conversation: ChatConversation
  let isLoading: Bool
  var renderAsMarkdown: Bool = true

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(conversation.messages) { message in
            MessageBubbleView(message: message, renderAsMarkdown: renderAsMarkdown)
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
        withAnimation(.easeOut(duration: 0.2)) {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      }
      .onChange(of: lastMessageText) {
        withAnimation(.easeOut(duration: 0.1)) {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      }
    }
  }

  /// Track the last message's text content to trigger scroll on streaming updates.
  private var lastMessageText: String {
    conversation.messages.last?.textContent ?? ""
  }
}
