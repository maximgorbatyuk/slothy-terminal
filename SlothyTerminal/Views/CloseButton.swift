import SwiftUI

/// Reusable close button with a circular hover highlight.
struct CloseButton: View {
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button {
      action()
    } label: {
      Image(systemName: "xmark")
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(.gray)
        .frame(width: 20, height: 20)
        .background(
          isHovered
            ? Color.gray.opacity(0.25)
            : Color.clear
        )
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}
