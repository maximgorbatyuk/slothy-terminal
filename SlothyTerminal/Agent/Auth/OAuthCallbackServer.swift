import Foundation
import Network
import OSLog

/// Result from an OAuth callback containing the authorization code
/// and the state parameter for CSRF validation.
struct OAuthCallbackResult: Sendable {
  let code: String
  let state: String?
}

/// Minimal local HTTP server that listens for OAuth redirect callbacks.
///
/// Starts an `NWListener` on a localhost port, waits for a single GET
/// request containing `?code=` and `?state=` parameters, extracts them,
/// and stops. The result is delivered via the `onResult` closure.
///
/// Usage:
/// ```swift
/// let server = OAuthCallbackServer(port: 1455)
/// try server.start { result in
///   guard result.state == expectedState else { throw ... }
///   let token = try await oauthClient.exchange(code: result.code)
/// }
/// ```
final class OAuthCallbackServer: @unchecked Sendable {
  private let port: UInt16
  private var listener: NWListener?
  private var onResult: ((OAuthCallbackResult) -> Void)?
  private let queue = DispatchQueue(label: "com.slothyterminal.oauth-callback")

  /// The redirect URI that should be registered with the OAuth provider.
  var redirectURI: String {
    "http://localhost:\(port)/auth/callback"
  }

  init(port: UInt16 = 1455) {
    self.port = port
  }

  /// Starts listening and calls `onResult` when an authorization callback arrives.
  ///
  /// The server stops automatically after receiving one valid callback.
  func start(onResult: @escaping (OAuthCallbackResult) -> Void) throws {
    self.onResult = onResult

    let params = NWParameters.tcp
    let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
    self.listener = listener

    listener.newConnectionHandler = { [weak self] connection in
      self?.handleConnection(connection)
    }

    listener.stateUpdateHandler = { state in
      switch state {
      case .ready:
        Logger.chat.info("OAuth callback server listening on port \(self.port)")

      case .failed(let error):
        Logger.chat.error("OAuth callback server failed: \(error.localizedDescription)")

      default:
        break
      }
    }

    listener.start(queue: queue)
  }

  /// Stops the listener and cleans up.
  func stop() {
    listener?.cancel()
    listener = nil
    onResult = nil
  }

  // MARK: - Private

  private func handleConnection(_ connection: NWConnection) {
    connection.start(queue: queue)

    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
      guard let self,
            let data,
            let request = String(data: data, encoding: .utf8)
      else {
        connection.cancel()
        return
      }

      self.processRequest(request, connection: connection)
    }
  }

  private func processRequest(_ request: String, connection: NWConnection) {
    /// Parse the first line: GET /callback?code=xxx&state=yyy HTTP/1.1
    guard let firstLine = request.split(separator: "\r\n").first else {
      sendResponse(connection: connection, body: "Invalid request")
      return
    }

    let parts = firstLine.split(separator: " ")

    guard parts.count >= 2 else {
      sendResponse(connection: connection, body: "Invalid request")
      return
    }

    let path = String(parts[1])

    guard let components = URLComponents(string: "http://localhost\(path)"),
          let code = components.queryItems?.first(where: { $0.name == "code" })?.value
    else {
      sendResponse(connection: connection, body: "Missing authorization code")
      return
    }

    let state = components.queryItems?.first(where: { $0.name == "state" })?.value

    /// Send success page.
    let successHTML = """
      <html><body style="font-family: system-ui; text-align: center; padding: 60px;">
      <h2>Authorization successful</h2>
      <p>You can close this window and return to SlothyTerminal.</p>
      </body></html>
      """
    sendResponse(connection: connection, body: successHTML, contentType: "text/html")

    /// Deliver the result and stop.
    onResult?(OAuthCallbackResult(code: code, state: state))
    stop()
  }

  private func sendResponse(
    connection: NWConnection,
    body: String,
    contentType: String = "text/plain"
  ) {
    let response = """
      HTTP/1.1 200 OK\r\n\
      Content-Type: \(contentType)\r\n\
      Content-Length: \(body.utf8.count)\r\n\
      Connection: close\r\n\
      \r\n\
      \(body)
      """

    connection.send(
      content: response.data(using: .utf8),
      completion: .contentProcessed { _ in
        connection.cancel()
      }
    )
  }
}
