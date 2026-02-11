import SwiftUI

/// Reusable copy-to-clipboard button with checkmark feedback.
struct CopyButton: View {
  let text: String
  var iconSize: CGFloat = 10

  @State private var copied = false

  var body: some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      copied = true

      Task {
        try? await Task.sleep(for: .seconds(1.5))
        copied = false
      }
    } label: {
      Image(systemName: copied ? "checkmark" : "doc.on.doc")
        .font(.system(size: iconSize))
        .foregroundColor(copied ? .green : .secondary)
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.plain)
    .help("Copy to clipboard")
  }
}
