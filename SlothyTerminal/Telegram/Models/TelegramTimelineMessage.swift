import Foundation

/// Direction of a message in the timeline.
enum TelegramMessageDirection {
  case inbound
  case outbound
  case system
}

/// A display model for the message timeline.
struct TelegramTimelineMessage: Identifiable {
  let id: UUID
  let timestamp: Date
  let direction: TelegramMessageDirection
  let text: String

  init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    direction: TelegramMessageDirection,
    text: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.direction = direction
    self.text = text
  }

  var isSystemMessage: Bool {
    direction == .system
  }
}
