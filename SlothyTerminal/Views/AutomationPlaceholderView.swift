import SwiftUI

/// Placeholder panel for the upcoming automation feature.
struct AutomationPlaceholderView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "gearshape.2")
        .font(.system(size: 32))
        .foregroundColor(.secondary)

      Text("Automation")
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
