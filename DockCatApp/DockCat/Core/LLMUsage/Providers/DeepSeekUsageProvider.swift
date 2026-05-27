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
        let url = URL(string: "https://api.deepseek.com/user/balance")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let state = await fetchState(request: request)
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }

    private func fetchState(request: URLRequest) async -> ProviderUsageSnapshot.State {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(reason: "无效响应")
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(reason: "HTTP \(http.statusCode): \(body.prefix(120))")
            }
            let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
            let cnyEntry = decoded.balanceInfos.first(where: { $0.currency == "CNY" })
            let amount = cnyEntry.flatMap { Decimal(string: $0.totalBalance) } ?? 0
            return .success(UsageData(
                balance: Money(amount: amount, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        } catch let urlError as URLError {
            return .failure(reason: "网络错误：\(urlError.localizedDescription)")
        } catch {
            return .failure(reason: "响应格式异常")
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
