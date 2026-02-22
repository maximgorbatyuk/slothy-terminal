import SwiftUI

/// Reusable row for a single LLM provider's authentication configuration.
///
/// Shows provider name, auth status indicator, and either an API key
/// `SecureField` or an OAuth login button depending on provider capabilities.
struct ProviderAuthRow: View {
  let providerName: String
  let providerIcon: String
  let apiKeyBinding: Binding<String>
  let authStatus: AuthStatus

  /// Optional OAuth action. When non-nil, an OAuth button is shown
  /// alongside the API key field.
  var onOAuthLogin: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: providerIcon)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.secondary)
          .frame(width: 20)

        Text(providerName)
          .font(.system(size: 13, weight: .medium))

        Spacer()

        statusBadge
      }

      SecureField(
        "API Key",
        text: apiKeyBinding,
        prompt: Text("sk-...")
      )
      .textFieldStyle(.roundedBorder)

      if let onOAuthLogin {
        Button(action: onOAuthLogin) {
          HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle")
            Text("Sign in with \(providerName)")
          }
          .font(.system(size: 12))
        }
        .buttonStyle(.link)
      }
    }
  }

  @ViewBuilder
  private var statusBadge: some View {
    switch authStatus {
    case .connected:
      HStack(spacing: 4) {
        Circle()
          .fill(.green)
          .frame(width: 6, height: 6)

        Text("Connected")
          .font(.system(size: 11))
          .foregroundColor(.green)
      }

    case .disconnected:
      HStack(spacing: 4) {
        Circle()
          .fill(.secondary.opacity(0.5))
          .frame(width: 6, height: 6)

        Text("Not configured")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

    case .error(let message):
      HStack(spacing: 4) {
        Circle()
          .fill(.red)
          .frame(width: 6, height: 6)

        Text(message)
          .font(.system(size: 11))
          .foregroundColor(.red)
      }
    }
  }
}

// MARK: - AuthStatus

/// Visual status of a provider's authentication.
enum AuthStatus {
  case connected
  case disconnected
  case error(String)
}
