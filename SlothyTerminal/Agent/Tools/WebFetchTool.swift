import Foundation

/// Fetches content from a URL and returns it as text.
///
/// Performs a simple GET request via URLSession, converts the response
/// body to a UTF-8 string, and truncates if necessary.
struct WebFetchTool: AgentTool {
  let id = "webfetch"

  let toolDescription = """
    Fetch content from a URL and return it as text. \
    Useful for retrieving web pages, API responses, or documentation.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "url": .init(
        type: "string",
        description: "The URL to fetch content from",
        enumValues: nil
      ),
    ],
    required: ["url"]
  )

  /// Maximum response size in characters.
  private let maxResponseSize = 50_000

  /// Request timeout in seconds.
  private let requestTimeout: TimeInterval = 30

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let urlString) = arguments["url"] else {
      return ToolResult(output: "Error: url is required", isError: true)
    }

    guard let url = URL(string: urlString) else {
      return ToolResult(output: "Error: Invalid URL: \(urlString)", isError: true)
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = requestTimeout
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) SlothyTerminal/1.0",
      forHTTPHeaderField: "User-Agent"
    )

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      return ToolResult(
        output: "Error: Request failed: \(error.localizedDescription)",
        isError: true
      )
    }

    if let httpResponse = response as? HTTPURLResponse,
       !(200..<300).contains(httpResponse.statusCode)
    {
      return ToolResult(
        output: "Error: HTTP \(httpResponse.statusCode)",
        isError: true
      )
    }

    guard var text = String(data: data, encoding: .utf8) else {
      return ToolResult(
        output: "Error: Unable to decode response as UTF-8",
        isError: true
      )
    }

    /// Strip common HTML tags for readability.
    text = stripHTMLTags(text)

    if text.count > maxResponseSize {
      text = String(text.prefix(maxResponseSize)) + "\n... (truncated)"
    }

    return ToolResult(output: text)
  }

  // MARK: - Private

  /// Basic HTML tag stripping for readability.
  private func stripHTMLTags(_ html: String) -> String {
    guard html.contains("<") else {
      return html
    }

    var result = html

    /// Remove script and style blocks.
    let blockPatterns = [
      "<script[^>]*>[\\s\\S]*?</script>",
      "<style[^>]*>[\\s\\S]*?</style>",
    ]
    for pattern in blockPatterns {
      if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
        result = regex.stringByReplacingMatches(
          in: result,
          range: NSRange(result.startIndex..., in: result),
          withTemplate: ""
        )
      }
    }

    /// Replace common block elements with newlines.
    let blockElements = ["<br", "<p", "<div", "<li", "<tr", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6"]
    for tag in blockElements {
      result = result.replacingOccurrences(
        of: tag,
        with: "\n" + tag,
        options: .caseInsensitive
      )
    }

    /// Strip all remaining tags.
    if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
      result = regex.stringByReplacingMatches(
        in: result,
        range: NSRange(result.startIndex..., in: result),
        withTemplate: ""
      )
    }

    /// Collapse multiple blank lines.
    while result.contains("\n\n\n") {
      result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
