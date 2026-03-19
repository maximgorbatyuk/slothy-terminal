import XCTest
@testable import SlothyTerminalLib

final class InjectionRequestTests: XCTestCase {

  // MARK: - ControlSignal ASCII Values

  func testControlSignalAsciiValues() {
    XCTAssertEqual(ControlSignal.ctrlC.asciiValue, 3)
    XCTAssertEqual(ControlSignal.ctrlD.asciiValue, 4)
    XCTAssertEqual(ControlSignal.ctrlZ.asciiValue, 26)
    XCTAssertEqual(ControlSignal.ctrlL.asciiValue, 12)
  }

  // MARK: - Default Values

  func testRequestDefaultValues() {
    let request = InjectionRequest(
      payload: .text("hello"),
      target: .activeTab
    )

    XCTAssertEqual(request.status, .accepted)
    XCTAssertEqual(request.origin, .automation)
    XCTAssertNotNil(request.id)
    XCTAssertNil(request.timeoutSeconds)
  }

  // MARK: - Codable Roundtrip

  func testTextPayloadCodable() throws {
    let request = InjectionRequest(
      payload: .text("hello world"),
      target: .activeTab,
      origin: .ui
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(InjectionRequest.self, from: data)

    XCTAssertEqual(request, decoded)
  }

  func testCommandPayloadCodable() throws {
    let request = InjectionRequest(
      payload: .command("ls -la", submit: .execute),
      target: .tabId(UUID())
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(InjectionRequest.self, from: data)

    XCTAssertEqual(request, decoded)
  }

  func testCommandInsertModeCodable() throws {
    let request = InjectionRequest(
      payload: .command("echo test", submit: .insert),
      target: .activeTab
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(InjectionRequest.self, from: data)

    XCTAssertEqual(request, decoded)
  }

  func testPastePayloadCodable() throws {
    let request = InjectionRequest(
      payload: .paste("multiline\ncontent", mode: .bracketed),
      target: .activeTab
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(InjectionRequest.self, from: data)

    XCTAssertEqual(request, decoded)
  }

  func testPastePlainModeCodable() throws {
    let request = InjectionRequest(
      payload: .paste("plain text", mode: .plain),
      target: .activeTab
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(InjectionRequest.self, from: data)

    XCTAssertEqual(request, decoded)
  }

  func testControlPayloadCodable() throws {
    let request = InjectionRequest(
      payload: .control(.ctrlC),
      target: .activeTab,
      origin: .automation
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(InjectionRequest.self, from: data)

    XCTAssertEqual(request, decoded)
  }

  func testKeyPayloadCodable() throws {
    let request = InjectionRequest(
      payload: .key(keyCode: 36, modifiers: 0),
      target: .activeTab
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(InjectionRequest.self, from: data)

    XCTAssertEqual(request, decoded)
  }

  // MARK: - InjectionTarget Equality

  func testTargetActiveTabEquality() {
    XCTAssertEqual(InjectionTarget.activeTab, InjectionTarget.activeTab)
  }

  func testTargetTabIdEquality() {
    let id = UUID()
    XCTAssertEqual(InjectionTarget.tabId(id), InjectionTarget.tabId(id))
    XCTAssertNotEqual(InjectionTarget.tabId(id), InjectionTarget.tabId(UUID()))
  }

  func testTargetFilteredEquality() {
    XCTAssertEqual(
      InjectionTarget.filtered(agentType: .claude, mode: .terminal),
      InjectionTarget.filtered(agentType: .claude, mode: .terminal)
    )
    XCTAssertNotEqual(
      InjectionTarget.filtered(agentType: .claude, mode: .terminal),
      InjectionTarget.filtered(agentType: .opencode, mode: .terminal)
    )
  }

  func testTargetCodableRoundtrip() throws {
    let targets: [InjectionTarget] = [
      .activeTab,
      .tabId(UUID()),
      .filtered(agentType: .claude, mode: .terminal),
      .filtered(agentType: nil, mode: nil),
    ]

    for target in targets {
      let data = try JSONEncoder().encode(target)
      let decoded = try JSONDecoder().decode(InjectionTarget.self, from: data)
      XCTAssertEqual(target, decoded)
    }
  }

  // MARK: - InjectionResult

  func testResultCodable() throws {
    let result = InjectionResult(
      requestId: UUID(),
      tabId: UUID(),
      status: .completed,
      error: nil
    )

    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(InjectionResult.self, from: data)

    XCTAssertEqual(result, decoded)
  }

  func testResultWithError() throws {
    let result = InjectionResult(
      requestId: UUID(),
      tabId: UUID(),
      status: .failed,
      error: "Surface not found"
    )

    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(InjectionResult.self, from: data)

    XCTAssertEqual(result, decoded)
    XCTAssertEqual(decoded.error, "Surface not found")
  }

  // MARK: - InjectionEvent Equality

  func testEventEquality() {
    let id = UUID()
    let tabId = UUID()

    XCTAssertEqual(
      InjectionEvent.requestAccepted(requestId: id),
      InjectionEvent.requestAccepted(requestId: id)
    )
    XCTAssertEqual(
      InjectionEvent.requestFailed(requestId: id, tabId: tabId, error: "oops"),
      InjectionEvent.requestFailed(requestId: id, tabId: tabId, error: "oops")
    )
    XCTAssertNotEqual(
      InjectionEvent.requestAccepted(requestId: id),
      InjectionEvent.requestCancelled(requestId: id)
    )
  }
}
