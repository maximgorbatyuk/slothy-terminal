import SwiftUI

/// Fenced code block with language label, copy button, and monospaced text.
struct CodeBlockView: View {
  let language: String?
  let code: String

  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      codeBody
    }
    .background(Color.white.opacity(0.08))
    .cornerRadius(8)
  }

  private var header: some View {
    HStack {
      if let language {
        Text(language)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

      Spacer()

      Button {
        copyToClipboard()
      } label: {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
          .font(.system(size: 11))
          .foregroundColor(copied ? .green : .secondary)
          .contentTransition(.symbolEffect(.replace))
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  private var codeBody: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      Text(code)
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
  }

  private func copyToClipboard() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code, forType: .string)
    copied = true

    Task {
      try? await Task.sleep(for: .seconds(2))
      copied = false
    }
  }
}
