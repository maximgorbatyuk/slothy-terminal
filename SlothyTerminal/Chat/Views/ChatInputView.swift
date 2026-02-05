import SwiftUI

/// Text input field with send/stop button for the chat interface.
/// Respects the `chatSendKey` setting: Enter or Shift+Enter to send,
/// with the opposite key inserting a newline.
struct ChatInputView: View {
  let isLoading: Bool
  let onSend: (String) -> Void
  let onStop: () -> Void

  @State private var inputText: String = ""
  @FocusState private var isFocused: Bool

  private var sendKey: ChatSendKey {
    ConfigManager.shared.config.chatSendKey
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextEditor(text: $inputText)
        .font(.system(size: 13))
        .scrollContentBackground(.hidden)
        .focused($isFocused)
        .frame(minHeight: 36, maxHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .background(appCardColor)
        .cornerRadius(8)
        .onKeyPress(.return, phases: .down) { press in
          let hasShift = press.modifiers.contains(.shift)

          switch sendKey {
          case .enter:
            if hasShift {
              /// Shift+Return → newline (let TextEditor handle it).
              return .ignored
            }

            /// Plain Return → send.
            send()
            return .handled

          case .shiftEnter:
            if hasShift {
              /// Shift+Return → send.
              send()
              return .handled
            }

            /// Plain Return → newline (let TextEditor handle it).
            return .ignored
          }
        }

      if isLoading {
        Button {
          onStop()
        } label: {
          Image(systemName: "stop.circle.fill")
            .font(.system(size: 24))
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
        .help("Stop response (Esc)")
        .keyboardShortcut(.escape, modifiers: [])
      } else {
        Button {
          send()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 24))
            .foregroundColor(canSend ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help("Send message (\(sendKey.displayName))")
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .onAppear {
      isFocused = true
    }
  }

  private var canSend: Bool {
    !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
  }

  private func send() {
    guard canSend else {
      return
    }

    let text = inputText
    inputText = ""
    onSend(text)
  }
}
