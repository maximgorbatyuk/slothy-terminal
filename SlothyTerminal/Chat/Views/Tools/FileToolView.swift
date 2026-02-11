import SwiftUI

/// Displays a file Read or Write tool invocation.
struct FileToolView: View {
  let action: String
  let filePath: String
  let content: String?

  @State private var isExpanded = false

  private var icon: String {
    action == "Write" ? "doc.fill" : "doc"
  }

  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isExpanded.toggle()
      }
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Image(systemName: icon)
            .font(.system(size: 10))

          Text(action)
            .font(.system(size: 10, weight: .semibold))

          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 8))

          Spacer()
        }
        .foregroundColor(.blue.opacity(0.7))

        Text(filePath)
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary.opacity(isExpanded ? 0.8 : 0.6))
          .lineLimit(isExpanded ? nil : 1)
          .truncationMode(.middle)

        if isExpanded, let content, !content.isEmpty {
          Text(content)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(30)
            .padding(6)
            .background(Color.black.opacity(0.08))
            .cornerRadius(4)
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
