import Foundation

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
          let (bytes, response) = try await session.bytes(for: urlRequest)

          if let httpResponse = response as? HTTPURLResponse,
             !(200..<300).contains(httpResponse.statusCode)
          {
            var body = ""
            for try await line in bytes.lines {
              body += line + "\n"
            }
            throw URLSessionHTTPTransportError.httpError(
              statusCode: httpResponse.statusCode,
              body: body
            )
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
      return "HTTP \(code): \(body.prefix(500))"

    case .invalidResponse:
      return "Invalid HTTP response"
    }
  }
}
