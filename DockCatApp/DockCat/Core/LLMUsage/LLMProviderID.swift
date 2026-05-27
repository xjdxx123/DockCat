import Foundation

enum LLMProviderID: String, Codable, CaseIterable, Hashable {
    case anthropic
    case openai
    case openrouter
    case deepseek
    case kimi
}
