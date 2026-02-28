import SwiftUI

/// Scrolling timeline of inbound, outbound, and system messages.
struct TelegramMessageTimeline: View {
  let messages: [TelegramTimelineMessage]

  private static let timeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    return fmt
  }()

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          if messages.isEmpty {
            Text("No messages yet.")
              .font(.system(size: 12))
              .foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.top, 40)
          }

          ForEach(messages) { message in
            MessageRow(message: message, timeFormatter: Self.timeFormatter)
              .id(message.id)
          }
        }
        .padding(12)
      }
      .onChange(of: messages.count) {
        if let lastMessage = messages.last {
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
          }
        }
      }
    }
  }
}

/// A single message row in the timeline.
private struct MessageRow: View {
  let message: TelegramTimelineMessage
  let timeFormatter: DateFormatter

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(timeFormatter.string(from: message.timestamp))
        .font(.system(size: 9, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(width: 55, alignment: .leading)

      directionBadge

      Text(message.text)
        .font(.system(size: 12))
        .foregroundColor(textColor)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(backgroundColor)
    .cornerRadius(4)
  }

  private var directionBadge: some View {
    Text(badgeText)
      .font(.system(size: 9, weight: .bold, design: .monospaced))
      .foregroundColor(badgeColor)
      .frame(width: 30)
  }

  private var badgeText: String {
    switch message.direction {
    case .inbound:
      return "IN"

    case .outbound:
      return "OUT"

    case .system:
      return "SYS"
    }
  }

  private var badgeColor: Color {
    switch message.direction {
    case .inbound:
      return .blue

    case .outbound:
      return .green

    case .system:
      return .orange
    }
  }

  private var textColor: Color {
    message.isSystemMessage ? .secondary : .primary
  }

  private var backgroundColor: Color {
    switch message.direction {
    case .inbound:
      return Color.blue.opacity(0.05)

    case .outbound:
      return Color.green.opacity(0.05)

    case .system:
      return Color.orange.opacity(0.05)
    }
  }
}
