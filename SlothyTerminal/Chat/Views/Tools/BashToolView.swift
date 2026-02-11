import SwiftUI

/// Displays a Bash tool invocation with command and output.
struct BashToolView: View {
  let command: String
  let output: String?

  @State private var isExpanded = false

  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isExpanded.toggle()
      }
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Image(systemName: "terminal")
            .font(.system(size: 10))

          Text("Bash")
            .font(.system(size: 10, weight: .semibold))

          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 8))

          Spacer()
        }
        .foregroundColor(.blue.opacity(0.7))

        if !isExpanded {
          Text(command)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.tail)
        }

        if isExpanded {
          Text(command)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(Color.black.opacity(0.15))
            .cornerRadius(4)

          if let output, !output.isEmpty {
            Text(output)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .lineLimit(20)
              .padding(6)
              .background(Color.green.opacity(0.03))
              .cornerRadius(4)
          }
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
