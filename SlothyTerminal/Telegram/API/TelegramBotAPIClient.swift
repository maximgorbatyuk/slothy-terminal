import Foundation
import OSLog

/// HTTP client for the Telegram Bot API.
actor TelegramBotAPIClient {
  private let token: String
  private let baseURL: String
  private let session: URLSession

  init(token: String) {
    self.token = token
    self.baseURL = "https://api.telegram.org/bot\(token)"

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 35
    self.session = URLSession(configuration: config)
  }

  /// Validates the bot token and returns bot info.
  func getMe() async throws -> TelegramBotInfo {
    let url = URL(string: "\(baseURL)/getMe")!
    let (data, response) = try await performGet(url: url)
    try checkHTTPStatus(response)

    let apiResponse = try decodeResponse(TelegramAPIResponse<TelegramBotInfo>.self, from: data)

    guard let result = apiResponse.result else {
      throw TelegramAPIError.apiError(
        code: apiResponse.errorCode ?? -1,
        description: apiResponse.description ?? "Unknown error"
      )
    }

    return result
  }

  /// Fetches new updates using long polling.
  func getUpdates(offset: Int64?, timeout: Int = 30) async throws -> [TelegramUpdate] {
    var components = URLComponents(string: "\(baseURL)/getUpdates")!
    var queryItems = [URLQueryItem(name: "timeout", value: "\(timeout)")]

    if let offset {
      queryItems.append(URLQueryItem(name: "offset", value: "\(offset)"))
    }

    queryItems.append(URLQueryItem(name: "allowed_updates", value: "[\"message\"]"))
    components.queryItems = queryItems

    let (data, response) = try await performGet(url: components.url!)
    try checkHTTPStatus(response)

    let apiResponse = try decodeResponse(TelegramAPIResponse<[TelegramUpdate]>.self, from: data)
    return apiResponse.result ?? []
  }

  /// Sends a text message to a chat.
  func sendMessage(chatId: Int64, text: String, replyToMessageId: Int64? = nil) async throws {
    var body: [String: Any] = [
      "chat_id": chatId,
      "text": text,
    ]

    if let replyToMessageId {
      body["reply_parameters"] = ["message_id": replyToMessageId]
    }

    let (data, response) = try await performPost(path: "/sendMessage", body: body)
    try checkHTTPStatus(response, data: data)
  }

  /// Sends a "typing" chat action indicator.
  func sendChatAction(chatId: Int64) async throws {
    let body: [String: Any] = [
      "chat_id": chatId,
      "action": "typing",
    ]

    let (data, response) = try await performPost(path: "/sendChatAction", body: body)
    try checkHTTPStatus(response, data: data)
  }

  // MARK: - Private

  private func performGet(url: URL) async throws -> (Data, HTTPURLResponse) {
    do {
      let (data, response) = try await session.data(from: url)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw TelegramAPIError.networkError(
          NSError(domain: "TelegramBot", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        )
      }

      return (data, httpResponse)
    } catch let error as TelegramAPIError {
      throw error
    } catch {
      throw TelegramAPIError.networkError(error)
    }
  }

  private func performPost(path: String, body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
    let url = URL(string: "\(baseURL)\(path)")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    do {
      let (data, response) = try await session.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw TelegramAPIError.networkError(
          NSError(domain: "TelegramBot", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        )
      }

      return (data, httpResponse)
    } catch let error as TelegramAPIError {
      throw error
    } catch {
      throw TelegramAPIError.networkError(error)
    }
  }

  private func checkHTTPStatus(_ response: HTTPURLResponse, data: Data? = nil) throws {
    guard response.statusCode != 401 else {
      throw TelegramAPIError.unauthorized
    }

    guard (200...299).contains(response.statusCode) else {
      var description = "HTTP \(response.statusCode)"

      if let data,
         let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let desc = body["description"] as? String
      {
        description = desc
      }

      throw TelegramAPIError.apiError(code: response.statusCode, description: description)
    }
  }

  private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw TelegramAPIError.decodingError(error)
    }
  }
}
