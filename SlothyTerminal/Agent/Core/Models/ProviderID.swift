import Foundation

/// Identifies an LLM provider backend.
enum ProviderID: String, Codable, Sendable {
  case openAI = "openai"
  case anthropic = "anthropic"
  case zai = "zai"
  case zhipuAI = "zhipuai"
}
