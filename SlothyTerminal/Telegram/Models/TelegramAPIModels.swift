import Foundation

/// Generic Telegram Bot API response wrapper.
struct TelegramAPIResponse<T: Decodable>: Decodable {
  let ok: Bool
  let result: T?
  let errorCode: Int?
  let description: String?

  enum CodingKeys: String, CodingKey {
    case ok
    case result
    case errorCode = "error_code"
    case description
  }
}

/// A Telegram update from the getUpdates endpoint.
struct TelegramUpdate: Decodable, Identifiable {
  let updateId: Int64
  let message: TelegramAPIMessage?

  var id: Int64 { updateId }

  enum CodingKeys: String, CodingKey {
    case updateId = "update_id"
    case message
  }
}

/// A Telegram message.
struct TelegramAPIMessage: Decodable {
  let messageId: Int64
  let from: TelegramUser?
  let chat: TelegramChat
  let date: Int
  let text: String?

  enum CodingKeys: String, CodingKey {
    case messageId = "message_id"
    case from
    case chat
    case date
    case text
  }
}

/// A Telegram user.
struct TelegramUser: Decodable {
  let id: Int64
  let isBot: Bool
  let firstName: String
  let username: String?

  enum CodingKeys: String, CodingKey {
    case id
    case isBot = "is_bot"
    case firstName = "first_name"
    case username
  }
}

/// A Telegram chat.
struct TelegramChat: Decodable {
  let id: Int64
  let type: String
}

/// Bot info returned by getMe.
struct TelegramBotInfo: Decodable {
  let id: Int64
  let isBot: Bool
  let firstName: String
  let username: String?

  enum CodingKeys: String, CodingKey {
    case id
    case isBot = "is_bot"
    case firstName = "first_name"
    case username
  }
}

/// Errors from the Telegram Bot API client.
enum TelegramAPIError: LocalizedError {
  case unauthorized
  case apiError(code: Int, description: String)
  case networkError(Error)
  case decodingError(Error)

  var errorDescription: String? {
    switch self {
    case .unauthorized:
      return "Bot token is invalid or revoked (401)"

    case .apiError(let code, let description):
      return "Telegram API error \(code): \(description)"

    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"

    case .decodingError(let error):
      return "Decoding error: \(error.localizedDescription)"
    }
  }
}
