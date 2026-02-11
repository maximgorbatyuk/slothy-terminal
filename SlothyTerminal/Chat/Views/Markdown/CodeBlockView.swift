import SwiftUI

/// Fenced code block with language label, copy button, and monospaced text.
struct CodeBlockView: View {
  let language: String?
  let code: String

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

      CopyButton(text: code, iconSize: 11)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  private var codeBody: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      Text(code)
        .font(.system(size: 12, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
  }
}
