import SwiftUI

/// Displays a single chat message with role indicator and content blocks.
struct MessageBubbleView: View {
  let message: ChatMessage
  var renderAsMarkdown: Bool = true

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RoleAvatarView(role: message.role)

      VStack(alignment: .leading, spacing: 8) {
        Text(message.role == .user ? "You" : "Claude")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.secondary)

        ForEach(Array(message.contentBlocks.enumerated()), id: \.offset) { _, block in
          ContentBlockView(block: block, renderAsMarkdown: renderAsMarkdown)
        }

        if message.isStreaming && message.contentBlocks.isEmpty {
          StreamingIndicatorView()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

/// Displays the role avatar icon.
struct RoleAvatarView: View {
  let role: ChatRole

  var body: some View {
    ZStack {
      Circle()
        .fill(role == .user ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
        .frame(width: 28, height: 28)

      Image(systemName: role == .user ? "person.fill" : "brain.head.profile")
        .font(.system(size: 13))
        .foregroundColor(role == .user ? .blue : Color(red: 0.85, green: 0.47, blue: 0.34))
    }
  }
}

/// Routes to the appropriate view for a content block type.
struct ContentBlockView: View {
  let block: ChatContentBlock
  var renderAsMarkdown: Bool = true

  var body: some View {
    switch block {
    case .text(let text):
      if !text.isEmpty {
        if renderAsMarkdown {
          MarkdownTextView(text: text)
            .font(.system(size: 13))
        } else {
          Text(text)
            .font(.system(size: 13))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

    case .thinking(let text):
      ThinkingBlockView(text: text)

    case .toolUse(_, let name, let input):
      ToolUseBlockView(name: name, input: input)

    case .toolResult(_, let content):
      ToolResultBlockView(content: content)
    }
  }
}

/// Small raw block showing that Claude is thinking.
/// Displays a compact, non-interactive snippet of the raw thinking text.
struct ThinkingBlockView: View {
  let text: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "brain")
        .font(.system(size: 10))

      Text(text.isEmpty ? "Thinking..." : truncated)
        .font(.system(size: 10, design: .monospaced))
        .lineLimit(2)
        .truncationMode(.tail)
    }
    .foregroundColor(.secondary.opacity(0.5))
    .padding(.vertical, 2)
  }

  private var truncated: String {
    let compact = text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\n", with: " ")
    let limit = compact.prefix(120)
    return limit.count < compact.count
      ? limit + "..."
      : String(limit)
  }
}

/// Displays a tool use block with compact raw preview.
struct ToolUseBlockView: View {
  let name: String
  let input: String
  @State private var isExpanded = false

  private var preview: String {
    let compact = input
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "  ", with: " ")
    let truncated = compact.prefix(80)
    return truncated.count < compact.count
      ? truncated + "..."
      : String(truncated)
  }

  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isExpanded.toggle()
      }
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Image(systemName: "wrench.and.screwdriver")
            .font(.system(size: 10))

          Text(name.isEmpty ? "Tool" : name)
            .font(.system(size: 10, weight: .semibold))

          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 8))

          Spacer()
        }
        .foregroundColor(.blue.opacity(0.7))

        if !isExpanded && !input.isEmpty {
          Text(preview)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.6))
            .lineLimit(1)
        }

        if isExpanded && !input.isEmpty {
          Text(input)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .buttonStyle(.plain)
    .padding(6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.blue.opacity(0.03))
    .cornerRadius(6)
  }
}

/// Displays a tool result block with compact raw preview.
struct ToolResultBlockView: View {
  let content: String
  @State private var isExpanded = false

  private var preview: String {
    let compact = content
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "  ", with: " ")
    let truncated = compact.prefix(80)
    return truncated.count < compact.count
      ? truncated + "..."
      : String(truncated)
  }

  var body: some View {
    if !content.isEmpty {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          isExpanded.toggle()
        }
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 5) {
            Image(systemName: "arrow.turn.down.right")
              .font(.system(size: 10))

            Text("Result")
              .font(.system(size: 10, weight: .semibold))

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.system(size: 8))

            Spacer()
          }
          .foregroundColor(.green.opacity(0.7))

          if !isExpanded {
            Text(preview)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary.opacity(0.6))
              .lineLimit(1)
          }

          if isExpanded {
            Text(content)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      .buttonStyle(.plain)
      .padding(6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.green.opacity(0.03))
      .cornerRadius(6)
    }
  }
}

/// Animated dots indicating streaming is in progress.
struct StreamingIndicatorView: View {
  @State private var dotCount = 0

  private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color.secondary)
          .frame(width: 6, height: 6)
          .opacity(index <= dotCount ? 1.0 : 0.3)
      }
    }
    .onReceive(timer) { _ in
      dotCount = (dotCount + 1) % 3
    }
  }
}
