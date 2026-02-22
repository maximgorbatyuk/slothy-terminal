import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("DefaultVariantMapper")
struct DefaultVariantMapperTests {

  private let mapper = DefaultVariantMapper()

  // MARK: - Test models

  private let claudeSonnet = ModelDescriptor(
    providerID: .anthropic,
    modelID: "claude-sonnet-4-6",
    packageID: "@ai-sdk/anthropic",
    supportsReasoning: true,
    releaseDate: "2025-05-14",
    outputLimit: 16_384
  )

  private let claudeHaiku = ModelDescriptor(
    providerID: .anthropic,
    modelID: "claude-haiku-3-5",
    packageID: "@ai-sdk/anthropic",
    supportsReasoning: true,
    releaseDate: "2024-10-01",
    outputLimit: 8_192
  )

  private let gptCodex = ModelDescriptor(
    providerID: .openAI,
    modelID: "gpt-5.1-codex",
    packageID: "@ai-sdk/openai",
    supportsReasoning: true,
    releaseDate: "2025-07-01",
    outputLimit: 32_768
  )

  private let gptCodex52 = ModelDescriptor(
    providerID: .openAI,
    modelID: "gpt-5.2-codex",
    packageID: "@ai-sdk/openai",
    supportsReasoning: true,
    releaseDate: "2025-09-01",
    outputLimit: 32_768
  )

  private let gpt5 = ModelDescriptor(
    providerID: .openAI,
    modelID: "gpt-5",
    packageID: "@ai-sdk/openai",
    supportsReasoning: true,
    releaseDate: "2025-06-01",
    outputLimit: 32_768
  )

  private let glmModel = ModelDescriptor(
    providerID: .zai,
    modelID: "glm-4-plus",
    packageID: "@ai-sdk/zhipu",
    supportsReasoning: true,
    releaseDate: "2025-01-01",
    outputLimit: 8_192
  )

  private let noReasoningModel = ModelDescriptor(
    providerID: .anthropic,
    modelID: "claude-instant-1.2",
    packageID: "@ai-sdk/anthropic",
    supportsReasoning: false,
    releaseDate: "2023-01-01",
    outputLimit: 4_096
  )

  // MARK: - Variant Lists

  @Test("Adaptive Anthropic model gets low/medium/high/max")
  func adaptiveAnthropicVariants() {
    let variants = mapper.variants(for: claudeSonnet)
    #expect(variants == [.low, .medium, .high, .max])
  }

  @Test("Non-adaptive Anthropic model gets high/max")
  func nonAdaptiveAnthropicVariants() {
    let variants = mapper.variants(for: claudeHaiku)
    #expect(variants == [.high, .max])
  }

  @Test("Codex model gets low/medium/high")
  func codexVariants() {
    let variants = mapper.variants(for: gptCodex)
    #expect(variants == [.low, .medium, .high])
  }

  @Test("Codex 5.2 model gets low/medium/high/xhigh")
  func codex52Variants() {
    let variants = mapper.variants(for: gptCodex52)
    #expect(variants == [.low, .medium, .high, .xhigh])
  }

  @Test("GPT-5 (non-codex) gets minimal/low/medium/high")
  func gpt5Variants() {
    let variants = mapper.variants(for: gpt5)
    #expect(variants == [.minimal, .low, .medium, .high])
  }

  @Test("GLM model returns empty variants")
  func glmVariants() {
    let variants = mapper.variants(for: glmModel)
    #expect(variants.isEmpty)
  }

  @Test("Non-reasoning model returns empty variants")
  func noReasoningVariants() {
    let variants = mapper.variants(for: noReasoningModel)
    #expect(variants.isEmpty)
  }

  @Test("Z.AI zhipuAI returns empty variants")
  func zhipuVariants() {
    let zhipuModel = ModelDescriptor(
      providerID: .zhipuAI,
      modelID: "some-model",
      packageID: "@ai-sdk/zhipu",
      supportsReasoning: true,
      releaseDate: "2025-01-01",
      outputLimit: 8_192
    )
    let variants = mapper.variants(for: zhipuModel)
    #expect(variants.isEmpty)
  }

  // MARK: - Variant Options

  @Test("OpenAI variant options set reasoningEffort and reasoningSummary")
  func openAIVariantOptions() {
    let options = mapper.options(for: gptCodex, variant: .high)

    #expect(options["reasoningEffort"] == .string("high"))
    #expect(options["reasoningSummary"] == .string("auto"))
  }

  @Test("Adaptive Anthropic variant options use adaptive thinking")
  func adaptiveAnthropicOptions() {
    let options = mapper.options(for: claudeSonnet, variant: .medium)

    #expect(options["thinking"] == .object(["type": .string("adaptive")]))
    #expect(options["effort"] == .string("medium"))
  }

  @Test("Non-adaptive Anthropic high variant uses budgetTokens 16000")
  func nonAdaptiveAnthropicHigh() {
    let options = mapper.options(for: claudeHaiku, variant: .high)

    #expect(options["thinking"] == .object([
      "type": .string("enabled"),
      "budgetTokens": .number(16_000),
    ]))
  }

  @Test("Non-adaptive Anthropic max variant uses budgetTokens 31999")
  func nonAdaptiveAnthropicMax() {
    let options = mapper.options(for: claudeHaiku, variant: .max)

    #expect(options["thinking"] == .object([
      "type": .string("enabled"),
      "budgetTokens": .number(31_999),
    ]))
  }

  @Test("Z.AI variant options are empty")
  func zaiVariantOptions() {
    let options = mapper.options(for: glmModel, variant: .high)
    #expect(options.isEmpty)
  }

  // MARK: - Default Thinking Options

  @Test("Z.AI default thinking enables thinking")
  func zaiDefaultThinking() {
    let options = mapper.defaultThinkingOptions(for: glmModel)

    #expect(options["thinking"] == .object([
      "type": .string("enabled"),
      "clear_thinking": .bool(false),
    ]))
  }

  @Test("Anthropic default thinking is empty")
  func anthropicDefaultThinking() {
    let options = mapper.defaultThinkingOptions(for: claudeSonnet)
    #expect(options.isEmpty)
  }

  @Test("OpenAI default thinking is empty")
  func openAIDefaultThinking() {
    let options = mapper.defaultThinkingOptions(for: gptCodex)
    #expect(options.isEmpty)
  }
}
