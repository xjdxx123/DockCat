import Foundation

struct KimiUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .kimi
    let displayName = "Kimi"
    let supportsModelBreakdown = false
    let requiresAdminKey = false
    let helpURL = URL(string: "https://platform.moonshot.cn/console/api-keys")!

    private let session: URLSession
    private let now: @Sendable () -> Date

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.moonshot.cn/v1/users/me/balance")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result = await session.fetchJSON(request, as: KimiBalanceResponse.self)
        let state: ProviderUsageSnapshot.State
        switch result {
        case .success(let decoded):
            let amount = decoded.data.availableBalance
            state = .success(UsageData(
                balance: Money(amount: amount, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        case .failure(let error):
            state = .failure(reason: error.localizedDescription ?? "未知错误")
        }
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }
}

private struct KimiBalanceResponse: Decodable {
    let data: BalanceData

    struct BalanceData: Decodable {
        let availableBalance: Decimal

        enum CodingKeys: String, CodingKey {
            case availableBalance = "available_balance"
        }
    }
}
