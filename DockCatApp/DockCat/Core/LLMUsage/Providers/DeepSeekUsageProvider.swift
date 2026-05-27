import Foundation

struct DeepSeekUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .deepseek
    let displayName = "DeepSeek"
    let supportsModelBreakdown = false
    let requiresAdminKey = false
    let helpURL = URL(string: "https://platform.deepseek.com/api_keys")!

    private let session: URLSession
    private let now: @Sendable () -> Date

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result = await session.fetchJSON(request, as: DeepSeekBalanceResponse.self)
        let state: ProviderUsageSnapshot.State
        switch result {
        case .success(let decoded):
            let cnyEntry = decoded.balanceInfos.first(where: { $0.currency == "CNY" })
            let amount = cnyEntry.flatMap { Decimal(string: $0.totalBalance) } ?? 0
            state = .success(UsageData(
                balance: Money(amount: amount, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        case .failure(let error):
            state = .failure(mapError(error))
        }
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }

    private func mapError(_ error: LLMUsageError) -> ProviderUsageError {
        switch error {
        case .network(let underlying):
            return .network(detail: underlying.localizedDescription)
        case .http(let status, let body):
            return .http(status: status, body: body)
        case .decoding:
            return .decoding
        case .keychain(let status):
            return .keychain(status: status)
        case .cancelled:
            return .unknown(detail: "cancelled")
        }
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
        }
    }
}
