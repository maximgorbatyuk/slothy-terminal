import SwiftUI

/// Displays a single chat message with role indicator and content blocks.
struct MessageBubbleView: View {
  let message: ChatMessage
  var assistantName: String = "Claude"
  var renderAsMarkdown: Bool = true
  var currentToolName: String?
  var retryAction: (() -> Void)?

  private var toolResultByUseId: [String: String] {
    var result: [String: String] = [:]

    for block in message.contentBlocks {
      if case .toolResult(let toolUseId, let content) = block,
         !toolUseId.isEmpty,
         !result.keys.contains(toolUseId)
      {
        result[toolUseId] = content
      }
    }

    return result
  }

  private var toolUseIds: Set<String> {
    Set(message.contentBlocks.compactMap { block in
      if case .toolUse(let toolUseId, _, _) = block, !toolUseId.isEmpty {
        return toolUseId
      }

      return nil
    })
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RoleAvatarView(role: message.role)

      VStack(alignment: .leading, spacing: 8) {
        Text(message.role == .user ? "You" : assistantName)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.secondary)

        ForEach(Array(message.contentBlocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .toolUse(let id, let name, let input):
            ToolBlockRouter(
              name: name,
              input: input,
              resultContent: toolResultByUseId[id]
            )

          case .toolResult(let toolUseId, let content):
            if !toolUseIds.contains(toolUseId), !content.isEmpty {
              UnmatchedToolResultView(content: content)
            }

          case .text, .thinking:
            ContentBlockView(
              block: block,
              renderAsMarkdown: renderAsMarkdown,
              isStreaming: message.isStreaming
            )
          }
        }

        if message.isStreaming && message.contentBlocks.isEmpty {
          StreamingIndicatorView(toolName: currentToolName)
        }

        /// Metadata row for completed assistant messages.
        if message.role == .assistant && !message.isStreaming {
          MessageMetadataRow(message: message, retryAction: retryAction)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

/// Timestamp, token counts, copy button, and optional retry for completed assistant messages.
struct MessageMetadataRow: View {
  let message: ChatMessage
  var retryAction: (() -> Void)?

  var body: some View {
    HStack(spacing: 8) {
      Text(message.timestamp, style: .time)
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.5))

      if message.inputTokens > 0 || message.outputTokens > 0 {
        Text("\(message.inputTokens) in / \(message.outputTokens) out")
          .font(.system(size: 10))
          .foregroundColor(.secondary.opacity(0.5))
      }

      Spacer()

      if let retryAction {
        Button {
          retryAction()
        } label: {
          HStack(spacing: 3) {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 10))

            Text("Retry")
              .font(.system(size: 10))
          }
          .foregroundColor(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.1))
          .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help("Retry this message")
      }

      if !message.textContent.isEmpty {
        CopyButton(text: message.textContent)
      }
    }
    .padding(.top, 4)
  }
}

/// Fallback rendering when a tool result is received without a matching tool use.
struct UnmatchedToolResultView: View {
  let content: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 5) {
        Image(systemName: "arrow.turn.down.right")
          .font(.system(size: 10))

        Text("Result")
          .font(.system(size: 10, weight: .semibold))

        Spacer()
      }
      .foregroundColor(.green.opacity(0.7))

      Text(content)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.green.opacity(0.03))
    .cornerRadius(6)
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

/// Routes text and thinking content blocks to the appropriate view.
/// Tool blocks are handled separately by `ToolBlockRouter`.
struct ContentBlockView: View {
  let block: ChatContentBlock
  var renderAsMarkdown: Bool = true
  var isStreaming: Bool = false

  var body: some View {
    switch block {
    case .text(let text):
      if !text.isEmpty {
        if renderAsMarkdown {
          MarkdownTextView(text: text, isStreaming: isStreaming)
        } else {
          Text(text)
            .font(.system(size: 13))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

    case .thinking(let text):
      ThinkingBlockView(text: text)

    case .toolUse, .toolResult:
      EmptyView()
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

/// Context-aware streaming indicator.
/// Shows tool name when a tool is running, or animated dots otherwise.
struct StreamingIndicatorView: View {
  var toolName: String?

  @State private var dotCount = 0

  private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

  var body: some View {
    HStack(spacing: 6) {
      if let toolName,
         !toolName.isEmpty
      {
        Image(systemName: toolIconName(for: toolName))
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Text("Running \(toolName)...")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      } else {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(Color.secondary)
            .frame(width: 6, height: 6)
            .opacity(index <= dotCount ? 1.0 : 0.3)
        }
      }
    }
    .onReceive(timer) { _ in
      dotCount = (dotCount + 1) % 3
    }
  }

  private func toolIconName(for tool: String) -> String {
    switch tool.lowercased() {
    case "bash":
      return "terminal"

    case "read", "file_read":
      return "doc.text"

    case "write", "file_write":
      return "doc.badge.plus"

    case "edit", "file_edit":
      return "pencil"

    case "glob", "grep", "search":
      return "magnifyingglass"

    default:
      return "gearshape"
    }
  }
}
