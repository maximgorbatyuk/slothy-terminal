import Foundation
import OSLog

/// HTTP transport that executes a `PreparedRequest` and returns
/// a streaming `AsyncThrowingStream` of SSE events.
///
/// Uses `URLSession.bytes(for:)` for streaming responses and feeds
/// byte chunks through `SSEParser`.
final class URLSessionHTTPTransport: @unchecked Sendable {

  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  /// Execute a prepared request and stream SSE events back.
  ///
  /// The stream terminates when the server closes the connection
  /// or sends a `[DONE]` data payload.
  func stream(
    request: PreparedRequest
  ) -> AsyncThrowingStream<SSEEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let urlRequest = Self.makeURLRequest(from: request)
          Logger.agent.info(
            "[HTTP] \(request.method) \(request.url.absoluteString)"
          )

          let (bytes, response) = try await session.bytes(for: urlRequest)

          if let httpResponse = response as? HTTPURLResponse {
            Logger.agent.info("[HTTP] Response status: \(httpResponse.statusCode)")

            if !(200..<300).contains(httpResponse.statusCode) {
              var body = ""
              for try await line in bytes.lines {
                body += line + "\n"
              }

              Logger.agent.error(
                "[HTTP] Error body: \(body.prefix(2000))"
              )
              throw URLSessionHTTPTransportError.httpError(
                statusCode: httpResponse.statusCode,
                body: body
              )
            }
          }

          let parser = SSEParser()

          for try await line in bytes.lines {
            let events = parser.feed(line + "\n")
            for event in events {
              if event.data == "[DONE]" {
                continuation.finish()
                return
              }
              continuation.yield(event)
            }
          }

          /// Connection closed — flush any remaining buffered event.
          let remaining = parser.feed("\n")
          for event in remaining {
            if event.data != "[DONE]" {
              continuation.yield(event)
            }
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  /// Execute a non-streaming request and return the full response.
  func execute(
    request: PreparedRequest
  ) async throws -> (Data, HTTPURLResponse) {
    let urlRequest = Self.makeURLRequest(from: request)
    let (data, response) = try await session.data(for: urlRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLSessionHTTPTransportError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw URLSessionHTTPTransportError.httpError(
        statusCode: httpResponse.statusCode,
        body: body
      )
    }

    return (data, httpResponse)
  }

  // MARK: - Private

  private static func makeURLRequest(from request: PreparedRequest) -> URLRequest {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body.isEmpty ? nil : request.body

    for (key, value) in request.headers {
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }

    return urlRequest
  }
}

/// Errors from the HTTP transport layer.
enum URLSessionHTTPTransportError: Error, LocalizedError {
  case httpError(statusCode: Int, body: String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .httpError(let code, let body):
      if let parsed = Self.parseAPIError(statusCode: code, body: body) {
        return parsed
      }

      return "HTTP \(code): \(body.prefix(500))"

    case .invalidResponse:
      return "Invalid HTTP response"
    }
  }

  /// Attempts to extract a human-readable message from known API error formats.
  private static func parseAPIError(statusCode: Int, body: String) -> String? {
    guard let data = body.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    /// OpenAI / Codex format: {"error": {"message": "...", "type": "...", "resets_at": ...}}
    if let error = json["error"] as? [String: Any],
       let message = error["message"] as? String
    {
      var result = "HTTP \(statusCode): \(message)"

      if let resetsAt = error["resets_at"] as? TimeInterval {
        let resetDate = Date(timeIntervalSince1970: resetsAt)
        let remaining = resetDate.timeIntervalSinceNow

        if remaining > 0 {
          let hours = Int(remaining) / 3600
          let minutes = (Int(remaining) % 3600) / 60

          if hours > 0 {
            result += " (resets in \(hours)h \(minutes)m)"
          } else {
            result += " (resets in \(minutes)m)"
          }
        }
      }

      return result
    }

    /// Anthropic format: {"error": {"message": "..."}} or {"detail": "..."}
    if let detail = json["detail"] as? String {
      return "HTTP \(statusCode): \(detail)"
    }

    return nil
  }
}
