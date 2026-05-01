import Foundation

/// In-memory store of the most recent raw HTTP response per
/// `(provider, endpoint)` pair. Powers the Settings → Usage tab's "Latest JSON
/// responses" section so users (and developers) can inspect the actual JSON
/// shape each provider returns.
///
/// Auth material is never stored — request headers (Cookie, Authorization)
/// aren't recorded. Email-shaped strings in response bodies are scrubbed
/// before storage to avoid surfacing PII. Captured entries live only in
/// memory for the lifetime of the process.
@Observable
@MainActor
final class ProviderResponseStore {
  static let shared = ProviderResponseStore()

  /// One captured response. Latest wins per `(provider, endpoint)` key.
  /// `id` is a stable composite of provider + endpoint so SwiftUI doesn't
  /// tear down the row on refetch — that would silently drop the user's
  /// expansion state.
  struct Entry: Identifiable, Equatable {
    let provider: UsageProvider
    /// Short label distinguishing endpoints within a provider, e.g. `events`
    /// or `current-period`. Used together with `provider` as the upsert key.
    let endpoint: String
    let url: String
    let statusCode: Int?
    /// Pretty-printed JSON when the body parses; otherwise the raw UTF-8
    /// preview; otherwise a binary placeholder. Email-shaped substrings are
    /// replaced with `[redacted-email]` before storage.
    let prettyBody: String
    let byteCount: Int
    let fetchedAt: Date
    let error: String?

    var id: String { "\(provider.rawValue)/\(endpoint)" }
  }

  private(set) var entries: [Entry] = []

  private init() {}

  /// Records a captured response. Safe to call from any context — hops to the
  /// main actor internally so callers in `nonisolated` static methods don't
  /// need their own `Task { @MainActor in }` wrapper.
  nonisolated static func record(
    provider: UsageProvider,
    endpoint: String,
    url: String,
    statusCode: Int?,
    body: Data,
    error: String? = nil
  ) {
    let formatted = formatBody(body)
    let resolvedError = error ?? formatted.errorHint
    let entry = Entry(
      provider: provider,
      endpoint: endpoint,
      url: url,
      statusCode: statusCode,
      prettyBody: formatted.text,
      byteCount: body.count,
      fetchedAt: Date(),
      error: resolvedError
    )

    Task { @MainActor in
      shared.upsert(entry)
    }
  }

  /// Removes all stored entries.
  func clear() {
    entries.removeAll()
  }

  /// Replaces the existing entry for this `(provider, endpoint)` only if the
  /// incoming capture is strictly newer. This guards against a subtle race:
  /// the paginated Cursor fetch fires `record(...)` once per page, each one
  /// schedules an unstructured `Task { @MainActor in upsert(...) }`, and Swift
  /// Concurrency does not guarantee FIFO ordering of those tasks on the
  /// target actor. Without this check, an older page could overwrite a newer
  /// one if its task was reordered.
  private func upsert(_ entry: Entry) {
    if let index = entries.firstIndex(where: { existing in
      existing.provider == entry.provider && existing.endpoint == entry.endpoint
    }) {
      guard entry.fetchedAt > entries[index].fetchedAt else {
        return
      }

      entries[index] = entry
    } else {
      entries.append(entry)
    }
  }

  /// Tries JSON pretty-print, then UTF-8 raw, then a binary placeholder.
  /// Returns the displayable text plus an `errorHint` that flags the binary
  /// case so the UI's existing error styling kicks in (otherwise binary
  /// captures look identical to a successful one).
  nonisolated static func formatBody(_ data: Data) -> (text: String, errorHint: String?) {
    if let json = try? JSONSerialization.jsonObject(
      with: data,
      options: [.fragmentsAllowed]
    ) {
      if let pretty = try? JSONSerialization.data(
        withJSONObject: json,
        options: [.prettyPrinted, .sortedKeys]
      ),
        let text = String(data: pretty, encoding: .utf8)
      {
        return (scrubPII(text), nil)
      }
    }

    if let text = String(data: data, encoding: .utf8) {
      return (scrubPII(text), nil)
    }

    return (
      "<binary, \(data.count) bytes>",
      "Binary response (\(data.count) bytes)"
    )
  }

  nonisolated private static let emailRegex: NSRegularExpression? = {
    let pattern = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
    return try? NSRegularExpression(pattern: pattern)
  }()

  /// Replaces email-shaped substrings with `[redacted-email]`. Provider
  /// responses (e.g. Claude admin orgs, OpenAI org, ChatGPT wham/usage)
  /// can include the caller's account email; the developer reviewing the
  /// JSON shape doesn't need the actual address and shouldn't see it in
  /// screenshots/logs by default.
  nonisolated static func scrubPII(_ text: String) -> String {
    guard let regex = emailRegex else {
      return text
    }

    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(
      in: text,
      range: range,
      withTemplate: "[redacted-email]"
    )
  }
}
