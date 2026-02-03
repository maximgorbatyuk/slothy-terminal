import SwiftUI

/// About window showing app information.
struct AboutView: View {
  @Environment(\.dismiss) private var dismiss

  /// App version from bundle.
  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  }

  /// Build number from bundle.
  private var buildNumber: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
  }

  var body: some View {
    VStack(spacing: 20) {
      /// App icon and name.
      VStack(spacing: 12) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 80, height: 80)

        Text(BuildConfig.current.appName)
          .font(.title)
          .fontWeight(.semibold)
          .foregroundColor(.primary)

        Text("Version \(appVersion) (\(buildNumber))")
          .font(.subheadline)
          .foregroundColor(.secondary)

        if BuildConfig.isDevelopment {
          Text("Development Build")
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(4)
        }
      }

      Divider()
        .padding(.horizontal, 40)

      /// Developer info.
      VStack(spacing: 8) {
        Text("Developed by")
          .font(.caption)
          .foregroundColor(.secondary)

        Text(BuildConfig.developerName)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.primary)
      }

      /// GitHub link.
      Button {
        if let url = URL(string: BuildConfig.githubUrl) {
          NSWorkspace.shared.open(url)
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "link")
            .font(.system(size: 12))
          Text("View on GitHub")
            .font(.system(size: 12))
        }
      }
      .buttonStyle(.link)

      Spacer()

      /// Copyright.
      Text("© 2026 \(BuildConfig.developerName). All rights reserved.")
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    .padding(24)
    .frame(width: 300, height: 380)
    .background(appBackgroundColor)
  }
}

#Preview {
  AboutView()
}
