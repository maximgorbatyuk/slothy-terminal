import Foundation
import OSLog
import Security

/// Keychain-backed store for usage-related auth material.
/// Secrets are never stored in plain JSON config files.
enum UsageKeychainStore {
  private static let serviceName = "com.slothyterminal.usage"

  /// Saves auth material to the Keychain.
  @discardableResult
  static func save(
    provider: UsageProvider,
    sourceKind: UsageSourceKind,
    data: Data
  ) -> Bool {
    let account = keychainAccount(provider: provider, sourceKind: sourceKind)

    /// Remove existing entry first.
    delete(provider: provider, sourceKind: sourceKind)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecUseDataProtectionKeychain as String: true,
    ]

    let status = SecItemAdd(query as CFDictionary, nil)

    if status != errSecSuccess {
      Logger.usage.error(
        "Keychain save failed for \(provider.rawValue)/\(sourceKind.rawValue): \(status)"
      )
    }

    return status == errSecSuccess
  }

  /// Saves a string value to the Keychain.
  @discardableResult
  static func saveString(
    _ value: String,
    provider: UsageProvider,
    sourceKind: UsageSourceKind
  ) -> Bool {
    guard let data = value.data(using: .utf8) else {
      return false
    }

    return save(provider: provider, sourceKind: sourceKind, data: data)
  }

  /// Loads auth material from the Keychain.
  static func load(
    provider: UsageProvider,
    sourceKind: UsageSourceKind
  ) -> Data? {
    let account = keychainAccount(provider: provider, sourceKind: sourceKind)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseDataProtectionKeychain as String: true,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      return nil
    }

    return result as? Data
  }

  /// Loads a string value from the Keychain.
  static func loadString(
    provider: UsageProvider,
    sourceKind: UsageSourceKind
  ) -> String? {
    guard let data = load(provider: provider, sourceKind: sourceKind) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  /// Deletes auth material from the Keychain.
  @discardableResult
  static func delete(
    provider: UsageProvider,
    sourceKind: UsageSourceKind
  ) -> Bool {
    let account = keychainAccount(provider: provider, sourceKind: sourceKind)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
    ]

    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  /// Deletes all stored auth material for a provider.
  static func deleteAll(provider: UsageProvider) {
    for kind in UsageSourceKind.allCases {
      delete(provider: provider, sourceKind: kind)
    }
  }

  /// Deletes all stored usage auth material.
  static func deleteAll() {
    for provider in UsageProvider.allCases {
      deleteAll(provider: provider)
    }
  }

  // MARK: - Private

  private static func keychainAccount(
    provider: UsageProvider,
    sourceKind: UsageSourceKind
  ) -> String {
    "\(provider.rawValue).\(sourceKind.rawValue)"
  }
}
