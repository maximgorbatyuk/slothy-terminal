import SwiftUI

/// Placeholder panel for the upcoming tasks feature.
struct TasksPlaceholderView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "checklist")
        .font(.system(size: 32))
        .foregroundColor(.secondary)

      Text("Tasks")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)

      Text("Coming soon")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .opacity(0.7)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}
