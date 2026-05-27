import Foundation

struct ProviderUsageSnapshot: Codable, Equatable, Hashable {
    let providerID: LLMProviderID
    let fetchedAt: Date
    let state: State

    enum State: Codable, Equatable, Hashable {
        case missingKey
        case keyValidNoUsageAccess(hint: String)
        case success(UsageData)
        case failure(reason: String)
    }
}

struct UsageData: Codable, Equatable, Hashable {
    let balance: Money?
    let totalSpent: Money?
    let totalSpentLabel: SpentLabel
    let modelBreakdown: [ModelUsage]?
}

enum SpentLabel: String, Codable, Hashable {
    case thisMonth
    case lifetime
}

struct ModelUsage: Codable, Equatable, Hashable {
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Money
}
