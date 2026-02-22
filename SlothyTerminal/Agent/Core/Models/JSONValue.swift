import Foundation

/// A type-safe JSON value container used for dynamic API payloads.
enum JSONValue: Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null
}

// MARK: - Codable

extension JSONValue: Codable {
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
      return
    }

    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
      return
    }

    if let value = try? container.decode(Double.self) {
      self = .number(value)
      return
    }

    if let value = try? container.decode(String.self) {
      self = .string(value)
      return
    }

    if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
      return
    }

    if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
      return
    }

    throw DecodingError.typeMismatch(
      JSONValue.self,
      DecodingError.Context(
        codingPath: decoder.codingPath,
        debugDescription: "Unable to decode JSONValue"
      )
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .string(let value):
      try container.encode(value)

    case .number(let value):
      try container.encode(value)

    case .bool(let value):
      try container.encode(value)

    case .object(let value):
      try container.encode(value)

    case .array(let value):
      try container.encode(value)

    case .null:
      try container.encodeNil()
    }
  }
}
