import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("ModelDescriptor")
struct ModelDescriptorTests {

  private let sampleModel = ModelDescriptor(
    providerID: .anthropic,
    modelID: "claude-sonnet-4-6",
    packageID: "@ai-sdk/anthropic",
    supportsReasoning: true,
    releaseDate: "2025-05-14",
    outputLimit: 16_384
  )

  // MARK: - Codable

  @Test("Codable round-trip preserves all fields")
  func codableRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data = try encoder.encode(sampleModel)
    let decoded = try decoder.decode(ModelDescriptor.self, from: data)

    #expect(decoded.providerID == .anthropic)
    #expect(decoded.modelID == "claude-sonnet-4-6")
    #expect(decoded.packageID == "@ai-sdk/anthropic")
    #expect(decoded.supportsReasoning == true)
    #expect(decoded.releaseDate == "2025-05-14")
    #expect(decoded.outputLimit == 16_384)
  }

  @Test("Codable round-trip for OpenAI model")
  func codableRoundTripOpenAI() throws {
    let model = ModelDescriptor(
      providerID: .openAI,
      modelID: "gpt-5.1-codex",
      packageID: "@ai-sdk/openai",
      supportsReasoning: true,
      releaseDate: "2025-07-01",
      outputLimit: 32_768
    )

    let data = try JSONEncoder().encode(model)
    let decoded = try JSONDecoder().decode(ModelDescriptor.self, from: data)

    #expect(decoded == model)
  }

  // MARK: - Hashable

  @Test("Equal models have same hash")
  func equalModelsHash() {
    let copy = ModelDescriptor(
      providerID: .anthropic,
      modelID: "claude-sonnet-4-6",
      packageID: "@ai-sdk/anthropic",
      supportsReasoning: true,
      releaseDate: "2025-05-14",
      outputLimit: 16_384
    )

    #expect(sampleModel == copy)
    #expect(sampleModel.hashValue == copy.hashValue)
  }

  @Test("Different models are not equal")
  func differentModelsNotEqual() {
    let other = ModelDescriptor(
      providerID: .anthropic,
      modelID: "claude-opus-4-6",
      packageID: "@ai-sdk/anthropic",
      supportsReasoning: true,
      releaseDate: "2025-05-14",
      outputLimit: 32_000
    )

    #expect(sampleModel != other)
  }

  @Test("Can be used as dictionary key")
  func dictionaryKey() {
    var dict: [ModelDescriptor: String] = [:]
    dict[sampleModel] = "selected"

    #expect(dict[sampleModel] == "selected")
  }

  // MARK: - Set membership

  @Test("Can be used in a Set")
  func setMembership() {
    let duplicate = ModelDescriptor(
      providerID: .anthropic,
      modelID: "claude-sonnet-4-6",
      packageID: "@ai-sdk/anthropic",
      supportsReasoning: true,
      releaseDate: "2025-05-14",
      outputLimit: 16_384
    )

    let set: Set<ModelDescriptor> = [sampleModel, duplicate]
    #expect(set.count == 1)
  }
}
