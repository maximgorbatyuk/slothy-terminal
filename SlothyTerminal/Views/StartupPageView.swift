import SwiftUI

/// Modal wrapper for the shared start-session launcher.
struct StartupPageView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      StartSessionContentView(
        presentation: .modal,
        onStart: {
          dismiss()
        }
      )
    }
    .frame(width: 560)
    .fixedSize(horizontal: false, vertical: true)
    .background(appBackgroundColor)
  }

  private var header: some View {
    HStack {
      Text("Start New Session")
        .font(.headline)

      Spacer()

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 20))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.escape)
    }
    .padding(20)
  }
}

#Preview {
  StartupPageView()
    .environment(AppState())
}
