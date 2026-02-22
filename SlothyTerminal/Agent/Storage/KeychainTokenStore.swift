import Foundation
import Security

/// Persists `AuthMode` credentials in the macOS Keychain.
///
/// Each provider gets its own Keychain item, keyed by `ProviderID.rawValue`
/// under a shared service name. The `AuthMode` value is JSON-encoded.
final class KeychainTokenStore: TokenStore, @unchecked Sendable {
  private let service: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(service: String = "com.slothyterminal.agent.auth") {
    self.service = service
  }

  func load(provider: ProviderID) async throws -> AuthMode? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var out: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &out)

    if status == errSecItemNotFound {
      return nil
    }

    guard status == errSecSuccess,
          let data = out as? Data
    else {
      throw KeychainError.unhandledStatus(status)
    }

    return try decoder.decode(AuthMode.self, from: data)
  }

  func save(provider: ProviderID, auth: AuthMode) async throws {
    let data = try encoder.encode(auth)

    /// Delete any existing item first to avoid duplicate errors.
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      kSecValueData as String: data,
    ]

    let status = SecItemAdd(addQuery as CFDictionary, nil)

    guard status == errSecSuccess else {
      throw KeychainError.unhandledStatus(status)
    }
  }

  func remove(provider: ProviderID) async throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
    ]

    let status = SecItemDelete(query as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unhandledStatus(status)
    }
  }
}

// MARK: - KeychainError

/// Errors from Keychain operations.
enum KeychainError: Error, LocalizedError {
  case unhandledStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .unhandledStatus(let status):
      return "Keychain operation failed with status \(status)"
    }
  }
}
