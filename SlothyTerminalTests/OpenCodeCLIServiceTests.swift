import Testing

@testable import SlothyTerminalLib

@Suite("OpenCodeCLIService")
struct OpenCodeCLIServiceTests {
  @Test("Parses unique provider and model pairs")
  func parsesUniqueModels() {
    let output = """
    anthropic/claude-sonnet-4
    openai/gpt-5
    """

    let result = OpenCodeCLIService.parseModels(from: output)

    #expect(result == [
      ChatModelSelection(providerID: "anthropic", modelID: "claude-sonnet-4", displayName: "anthropic/claude-sonnet-4"),
      ChatModelSelection(providerID: "openai", modelID: "gpt-5", displayName: "openai/gpt-5"),
    ])
  }

  @Test("Skips malformed rows and empty lines")
  func skipsMalformedRows() {
    let output = """
    anthropic/claude-sonnet-4

    invalid-row
    /missing-provider
    openai/
    openai/gpt-5
    """

    let result = OpenCodeCLIService.parseModels(from: output)

    #expect(result.map(\.displayName) == [
      "anthropic/claude-sonnet-4",
      "openai/gpt-5",
    ])
  }

  @Test("Deduplicates duplicate model rows")
  func deduplicatesRows() {
    let output = """
    openai/gpt-5
    openai/gpt-5
    anthropic/claude-sonnet-4
    openai/gpt-5
    """

    let result = OpenCodeCLIService.parseModels(from: output)

    #expect(result.count == 2)
    #expect(result.filter { $0.displayName == "openai/gpt-5" }.count == 1)
  }

  @Test("Returns models sorted by display name")
  func sortsModelsByDisplayName() {
    let output = """
    zed/model-b
    anthropic/claude-sonnet-4
    openai/gpt-5
    """

    let result = OpenCodeCLIService.parseModels(from: output)

    #expect(result.map(\.displayName) == [
      "anthropic/claude-sonnet-4",
      "openai/gpt-5",
      "zed/model-b",
    ])
  }

  @Test("Empty output returns no models")
  func emptyOutputReturnsNoModels() {
    #expect(OpenCodeCLIService.parseModels(from: "").isEmpty)
  }
}
