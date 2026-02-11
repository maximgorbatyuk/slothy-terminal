import SwiftUI

/// Fallback view for unknown tool types. Shows raw JSON input and output.
struct GenericToolView: View {
  let name: String
  let input: String
  let output: String?

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

        if isExpanded {
          if !input.isEmpty {
            Text(input)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(6)
              .background(Color.black.opacity(0.08))
              .cornerRadius(4)
          }

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
