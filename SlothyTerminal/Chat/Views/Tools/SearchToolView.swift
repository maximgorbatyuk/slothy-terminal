import SwiftUI

/// Displays a Glob or Grep search tool invocation.
struct SearchToolView: View {
  let type: String
  let pattern: String
  let results: String?

  @State private var isExpanded = false

  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isExpanded.toggle()
      }
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 10))

          Text(type)
            .font(.system(size: 10, weight: .semibold))

          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 8))

          Spacer()
        }
        .foregroundColor(.blue.opacity(0.7))

        Text(pattern)
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary.opacity(isExpanded ? 0.8 : 0.6))
          .lineLimit(isExpanded ? nil : 1)

        if isExpanded, let results, !results.isEmpty {
          Text(results)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(20)
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
