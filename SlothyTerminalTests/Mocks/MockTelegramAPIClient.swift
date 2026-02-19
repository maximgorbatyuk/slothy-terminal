import Foundation
@testable import SlothyTerminalLib

/// Mock Telegram Bot API client for unit tests.
///
/// Provides configurable responses for each API method so tests can
/// simulate various server behaviors without making network calls.
actor MockTelegramAPIClient {
  var getMeResult: Result<TelegramBotInfo, Error> = .failure(TelegramAPIError.unauthorized)
  var getUpdatesResult: Result<[TelegramUpdate], Error> = .success([])
  var sendMessageCalls: [(chatId: Int64, text: String, replyToMessageId: Int64?)] = []
  var sendChatActionCalls: [Int64] = []
  var sendMessageError: Error?
  var sendChatActionError: Error?

  func getMe() async throws -> TelegramBotInfo {
    switch getMeResult {
    case .success(let info):
      return info

    case .failure(let error):
      throw error
    }
  }

  func getUpdates(offset: Int64?, timeout: Int = 30) async throws -> [TelegramUpdate] {
    switch getUpdatesResult {
    case .success(let updates):
      return updates

    case .failure(let error):
      throw error
    }
  }

  func sendMessage(chatId: Int64, text: String, replyToMessageId: Int64? = nil) async throws {
    sendMessageCalls.append((chatId: chatId, text: text, replyToMessageId: replyToMessageId))

    if let error = sendMessageError {
      throw error
    }
  }

  func sendChatAction(chatId: Int64) async throws {
    sendChatActionCalls.append(chatId)

    if let error = sendChatActionError {
      throw error
    }
  }
}
