import Foundation

struct OpenRouterUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .openrouter
    let displayName = "OpenRouter"
    let supportsModelBreakdown = false
    let requiresAdminKey = false
    let helpURL = URL(string: "https://openrouter.ai/settings/keys")!

    private let session: URLSession
    private let now: @Sendable () -> Date

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/credits")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result = await session.fetchJSON(request, as: OpenRouterCreditsResponse.self)
        let state: ProviderUsageSnapshot.State
        switch result {
        case .success(let decoded):
            let totalCredits = decoded.data.totalCredits
            let totalUsage = decoded.data.totalUsage
            let balance = totalCredits - totalUsage
            state = .success(UsageData(
                balance: Money(amount: balance, currency: "USD"),
                totalSpent: Money(amount: totalUsage, currency: "USD"),
                totalSpentLabel: .lifetime,
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

private struct OpenRouterCreditsResponse: Decodable {
    let data: CreditsData

    struct CreditsData: Decodable {
        let totalCredits: Decimal
        let totalUsage: Decimal

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
}
