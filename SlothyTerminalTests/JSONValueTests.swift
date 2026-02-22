import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("JSONValue")
struct JSONValueTests {

  // MARK: - Codable round-trip

  @Test("String round-trip")
  func stringRoundTrip() throws {
    let value = JSONValue.string("hello")
    let decoded = try encodeDecode(value)
    #expect(decoded == value)
  }

  @Test("Number round-trip")
  func numberRoundTrip() throws {
    let value = JSONValue.number(42.5)
    let decoded = try encodeDecode(value)
    #expect(decoded == value)
  }

  @Test("Bool round-trip")
  func boolRoundTrip() throws {
    let trueValue = JSONValue.bool(true)
    let falseValue = JSONValue.bool(false)
    #expect(try encodeDecode(trueValue) == trueValue)
    #expect(try encodeDecode(falseValue) == falseValue)
  }

  @Test("Null round-trip")
  func nullRoundTrip() throws {
    let value = JSONValue.null
    let decoded = try encodeDecode(value)
    #expect(decoded == value)
  }

  @Test("Array round-trip")
  func arrayRoundTrip() throws {
    let value = JSONValue.array([
      .string("a"),
      .number(1),
      .bool(true),
      .null,
    ])
    let decoded = try encodeDecode(value)
    #expect(decoded == value)
  }

  @Test("Object round-trip")
  func objectRoundTrip() throws {
    let value = JSONValue.object([
      "name": .string("test"),
      "count": .number(3),
      "active": .bool(false),
    ])
    let decoded = try encodeDecode(value)
    #expect(decoded == value)
  }

  @Test("Nested object round-trip")
  func nestedRoundTrip() throws {
    let value = JSONValue.object([
      "thinking": .object([
        "type": .string("enabled"),
        "budgetTokens": .number(16_000),
      ]),
      "tags": .array([.string("a"), .string("b")]),
      "meta": .null,
    ])
    let decoded = try encodeDecode(value)
    #expect(decoded == value)
  }

  // MARK: - Decoding from raw JSON

  @Test("Decode from raw JSON string")
  func decodeFromRawJSON() throws {
    let json = """
      {"key": "value", "num": 42, "flag": true, "nothing": null}
      """
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

    let expected = JSONValue.object([
      "key": .string("value"),
      "num": .number(42),
      "flag": .bool(true),
      "nothing": .null,
    ])
    #expect(decoded == expected)
  }

  // MARK: - Equatable

  @Test("Different types are not equal")
  func differentTypesNotEqual() {
    #expect(JSONValue.string("1") != JSONValue.number(1))
    #expect(JSONValue.bool(true) != JSONValue.number(1))
    #expect(JSONValue.null != JSONValue.string("null"))
  }

  // MARK: - Helpers

  private func encodeDecode(_ value: JSONValue) throws -> JSONValue {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(value)
    return try decoder.decode(JSONValue.self, from: data)
  }
}
