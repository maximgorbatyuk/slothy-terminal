import SwiftUI

/// Displays a file Edit tool invocation with old/new diff view.
struct EditToolView: View {
  let filePath: String
  let oldString: String
  let newString: String

  @State private var isExpanded = false

  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isExpanded.toggle()
      }
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Image(systemName: "pencil")
            .font(.system(size: 10))

          Text("Edit")
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

        if isExpanded {
          if !oldString.isEmpty {
            Text(oldString)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.red.opacity(0.8))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .lineLimit(20)
              .padding(6)
              .background(Color.red.opacity(0.05))
              .cornerRadius(4)
          }

          if !newString.isEmpty {
            Text(newString)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.green.opacity(0.8))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .lineLimit(20)
              .padding(6)
              .background(Color.green.opacity(0.05))
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
