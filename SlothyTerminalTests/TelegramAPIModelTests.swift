import XCTest
@testable import SlothyTerminalLib

final class TelegramAPIModelTests: XCTestCase {

  // MARK: - TelegramAPIResponse

  func testDecodeSuccessResponse() throws {
    let json = """
    {
      "ok": true,
      "result": {
        "id": 123456789,
        "is_bot": true,
        "first_name": "TestBot",
        "username": "test_bot"
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(
      TelegramAPIResponse<TelegramBotInfo>.self,
      from: json
    )

    XCTAssertTrue(response.ok)
    XCTAssertNotNil(response.result)
    XCTAssertEqual(response.result?.id, 123456789)
    XCTAssertEqual(response.result?.firstName, "TestBot")
    XCTAssertEqual(response.result?.username, "test_bot")
    XCTAssertTrue(response.result?.isBot ?? false)
    XCTAssertNil(response.errorCode)
  }

  func testDecodeErrorResponse() throws {
    let json = """
    {
      "ok": false,
      "error_code": 401,
      "description": "Unauthorized"
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(
      TelegramAPIResponse<TelegramBotInfo>.self,
      from: json
    )

    XCTAssertFalse(response.ok)
    XCTAssertNil(response.result)
    XCTAssertEqual(response.errorCode, 401)
    XCTAssertEqual(response.description, "Unauthorized")
  }

  // MARK: - TelegramUpdate

  func testDecodeUpdate() throws {
    let json = """
    {
      "update_id": 100200300,
      "message": {
        "message_id": 42,
        "from": {
          "id": 999,
          "is_bot": false,
          "first_name": "Max"
        },
        "chat": {
          "id": 999,
          "type": "private"
        },
        "date": 1700000000,
        "text": "Hello bot"
      }
    }
    """.data(using: .utf8)!

    let update = try JSONDecoder().decode(TelegramUpdate.self, from: json)

    XCTAssertEqual(update.updateId, 100200300)
    XCTAssertEqual(update.id, 100200300)
    XCTAssertNotNil(update.message)
    XCTAssertEqual(update.message?.messageId, 42)
    XCTAssertEqual(update.message?.text, "Hello bot")
    XCTAssertEqual(update.message?.from?.id, 999)
    XCTAssertEqual(update.message?.from?.firstName, "Max")
    XCTAssertFalse(update.message?.from?.isBot ?? true)
    XCTAssertEqual(update.message?.chat.id, 999)
    XCTAssertEqual(update.message?.chat.type, "private")
    XCTAssertEqual(update.message?.date, 1700000000)
  }

  func testDecodeUpdateWithoutMessage() throws {
    let json = """
    {
      "update_id": 100200301
    }
    """.data(using: .utf8)!

    let update = try JSONDecoder().decode(TelegramUpdate.self, from: json)

    XCTAssertEqual(update.updateId, 100200301)
    XCTAssertNil(update.message)
  }

  // MARK: - TelegramAPIMessage

  func testDecodeMessageWithoutFrom() throws {
    let json = """
    {
      "message_id": 10,
      "chat": {
        "id": 555,
        "type": "group"
      },
      "date": 1700000000,
      "text": "group message"
    }
    """.data(using: .utf8)!

    let message = try JSONDecoder().decode(TelegramAPIMessage.self, from: json)

    XCTAssertEqual(message.messageId, 10)
    XCTAssertNil(message.from)
    XCTAssertEqual(message.chat.id, 555)
    XCTAssertEqual(message.chat.type, "group")
    XCTAssertEqual(message.text, "group message")
  }

  func testDecodeMessageWithoutText() throws {
    let json = """
    {
      "message_id": 11,
      "from": {
        "id": 100,
        "is_bot": false,
        "first_name": "Alice"
      },
      "chat": {
        "id": 100,
        "type": "private"
      },
      "date": 1700000000
    }
    """.data(using: .utf8)!

    let message = try JSONDecoder().decode(TelegramAPIMessage.self, from: json)

    XCTAssertEqual(message.messageId, 11)
    XCTAssertNil(message.text)
    XCTAssertNotNil(message.from)
  }

  // MARK: - TelegramUser

  func testDecodeUserWithUsername() throws {
    let json = """
    {
      "id": 42,
      "is_bot": false,
      "first_name": "Bob",
      "username": "bob123"
    }
    """.data(using: .utf8)!

    let user = try JSONDecoder().decode(TelegramUser.self, from: json)

    XCTAssertEqual(user.id, 42)
    XCTAssertFalse(user.isBot)
    XCTAssertEqual(user.firstName, "Bob")
    XCTAssertEqual(user.username, "bob123")
  }

  func testDecodeUserWithoutUsername() throws {
    let json = """
    {
      "id": 43,
      "is_bot": true,
      "first_name": "BotUser"
    }
    """.data(using: .utf8)!

    let user = try JSONDecoder().decode(TelegramUser.self, from: json)

    XCTAssertEqual(user.id, 43)
    XCTAssertTrue(user.isBot)
    XCTAssertEqual(user.firstName, "BotUser")
    XCTAssertNil(user.username)
  }

  // MARK: - TelegramBotInfo

  func testDecodeBotInfo() throws {
    let json = """
    {
      "id": 7777777,
      "is_bot": true,
      "first_name": "Slothy Bot",
      "username": "slothy_bot"
    }
    """.data(using: .utf8)!

    let info = try JSONDecoder().decode(TelegramBotInfo.self, from: json)

    XCTAssertEqual(info.id, 7777777)
    XCTAssertTrue(info.isBot)
    XCTAssertEqual(info.firstName, "Slothy Bot")
    XCTAssertEqual(info.username, "slothy_bot")
  }

  // MARK: - TelegramAPIError

  func testErrorDescriptions() {
    let unauthorized = TelegramAPIError.unauthorized
    XCTAssertTrue(unauthorized.errorDescription?.contains("401") ?? false)

    let apiError = TelegramAPIError.apiError(code: 400, description: "Bad Request")
    XCTAssertTrue(apiError.errorDescription?.contains("400") ?? false)
    XCTAssertTrue(apiError.errorDescription?.contains("Bad Request") ?? false)

    let networkError = TelegramAPIError.networkError(
      NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
    )
    XCTAssertTrue(networkError.errorDescription?.contains("Network error") ?? false)

    let decodingError = TelegramAPIError.decodingError(
      NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid json"])
    )
    XCTAssertTrue(decodingError.errorDescription?.contains("Decoding error") ?? false)
  }

  // MARK: - Batch Decode (getUpdates response)

  func testDecodeGetUpdatesResponse() throws {
    let json = """
    {
      "ok": true,
      "result": [
        {
          "update_id": 1001,
          "message": {
            "message_id": 1,
            "from": {
              "id": 999,
              "is_bot": false,
              "first_name": "Max"
            },
            "chat": {
              "id": 999,
              "type": "private"
            },
            "date": 1700000000,
            "text": "/help"
          }
        },
        {
          "update_id": 1002,
          "message": {
            "message_id": 2,
            "from": {
              "id": 999,
              "is_bot": false,
              "first_name": "Max"
            },
            "chat": {
              "id": 999,
              "type": "private"
            },
            "date": 1700000001,
            "text": "Do something"
          }
        }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(
      TelegramAPIResponse<[TelegramUpdate]>.self,
      from: json
    )

    XCTAssertTrue(response.ok)
    XCTAssertEqual(response.result?.count, 2)
    XCTAssertEqual(response.result?[0].updateId, 1001)
    XCTAssertEqual(response.result?[0].message?.text, "/help")
    XCTAssertEqual(response.result?[1].updateId, 1002)
    XCTAssertEqual(response.result?[1].message?.text, "Do something")
  }

  func testDecodeEmptyUpdatesResponse() throws {
    let json = """
    {
      "ok": true,
      "result": []
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(
      TelegramAPIResponse<[TelegramUpdate]>.self,
      from: json
    )

    XCTAssertTrue(response.ok)
    XCTAssertEqual(response.result?.count, 0)
  }

  // MARK: - TelegramChat Types

  func testDecodeChatTypes() throws {
    let types = ["private", "group", "supergroup", "channel"]

    for type in types {
      let json = """
      {
        "id": 123,
        "type": "\(type)"
      }
      """.data(using: .utf8)!

      let chat = try JSONDecoder().decode(TelegramChat.self, from: json)

      XCTAssertEqual(chat.type, type)
    }
  }
}
