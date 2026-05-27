import Foundation

extension LLMProviderID {
    var displayName: String {
        switch self {
        case .anthropic:  return "Anthropic"
        case .openai:     return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .deepseek:   return "DeepSeek"
        case .kimi:       return "Kimi"
        }
    }
}

enum PetBalanceMessenger {
    /// 从快照里随机选一个有数据的 provider，生成气泡文案。
    /// 完全无数据时返回"未配置"提示。
    /// - Parameter randomPicker: 注入用于测试（默认 `randomElement()`）
    static func message(
        snapshots: [LLMProviderID: ProviderUsageSnapshot],
        lastSuccessful: [LLMProviderID: LLMUsageService.LastGood],
        strings: AppStrings,
        randomPicker: ([(LLMProviderID, UsageData)]) -> (LLMProviderID, UsageData)? = { $0.randomElement() }
    ) -> String {
        let pool: [(LLMProviderID, UsageData)] = LLMProviderID.allCases.compactMap { id in
            if let snapshot = snapshots[id], case .success(let data) = snapshot.state {
                return (id, data)
            }
            if let last = lastSuccessful[id] {
                return (id, last.data)
            }
            return nil
        }
        guard let pick = randomPicker(pool) else {
            return strings.petBubbleNoLLM
        }
        return strings.petBubbleMessage(providerID: pick.0, data: pick.1)
    }
}
