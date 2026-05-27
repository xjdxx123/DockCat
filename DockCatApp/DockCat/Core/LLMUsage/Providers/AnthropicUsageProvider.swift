import Foundation

struct AnthropicUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .anthropic
    let displayName = "Anthropic"
    let supportsModelBreakdown = true
    let requiresAdminKey = true
    let helpURL = URL(string: "https://console.anthropic.com/settings/admin-keys")!

    private let session: URLSession
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(session: URLSession = .shared,
         now: @Sendable @escaping () -> Date = Date.init,
         calendar: Calendar = .init(identifier: .gregorian)) {
        self.session = session
        self.now = now
        self.calendar = calendar
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        let state = await resolveState(apiKey: apiKey)
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }

    private func resolveState(apiKey: String) async -> ProviderUsageSnapshot.State {
        // 1. Probe /v1/models to check that the key is valid for inference at all.
        let modelsRequest = makeRequest(url: URL(string: "https://api.anthropic.com/v1/models")!, apiKey: apiKey)
        let probeResult = await session.fetchJSON(modelsRequest, as: AnthropicModelsProbe.self)
        switch probeResult {
        case .success:
            break
        case .failure(let error):
            if case .http(let status, _) = error, status == 401 || status == 403 {
                return .failure(reason: "Invalid API key")
            }
            return .failure(reason: error.errorDescription ?? "未知错误")
        }

        // 2. Usage report — requires admin key. 401/403 here means the key is valid
        //    for inference but lacks the admin scope.
        let startISO = monthStartISO8601()
        let usageURL = URL(string: "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=\(startISO)")!
        let usageRequest = makeRequest(url: usageURL, apiKey: apiKey)
        let usageResult = await session.fetchJSON(usageRequest, as: AnthropicUsageResponse.self)
        let usage: AnthropicUsageResponse
        switch usageResult {
        case .success(let value):
            usage = value
        case .failure(let error):
            if case .http(let status, _) = error, status == 401 || status == 403 {
                return .keyValidNoUsageAccess(hint: "此 key 有效，但需要 Admin Key 才能查询用量")
            }
            return .failure(reason: error.errorDescription ?? "未知错误")
        }

        // 3. Cost report (best effort) — degrade gracefully if it fails.
        let costURL = URL(string: "https://api.anthropic.com/v1/organizations/cost_report?starting_at=\(startISO)")!
        let costRequest = makeRequest(url: costURL, apiKey: apiKey)
        var costsByModel: [String: Money] = [:]
        var totalSpent = Decimal(0)
        if case .success(let costResponse) = await session.fetchJSON(costRequest, as: AnthropicCostResponse.self) {
            for entry in costResponse.data {
                let amount = Decimal(string: entry.amount) ?? 0
                costsByModel[entry.model] = Money(amount: amount, currency: entry.currency)
                totalSpent += amount
            }
        }

        // 4. Compose the per-model breakdown.
        let breakdown = usage.data.map { row in
            ModelUsage(
                modelName: row.model,
                inputTokens: row.inputTokens,
                outputTokens: row.outputTokens,
                cost: costsByModel[row.model] ?? Money(amount: 0, currency: "USD")
            )
        }

        return .success(UsageData(
            balance: nil,
            totalSpent: Money(amount: totalSpent, currency: "USD"),
            totalSpentLabel: .thisMonth,
            modelBreakdown: breakdown
        ))
    }

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func monthStartISO8601() -> String {
        var components = calendar.dateComponents([.year, .month], from: now())
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        let date = calendar.date(from: components) ?? now()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private struct AnthropicModelsProbe: Decodable {
    let data: [Item]
    struct Item: Decodable {
        let id: String
    }
}

private struct AnthropicUsageResponse: Decodable {
    let data: [Row]
    struct Row: Decodable {
        let model: String
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case model
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

private struct AnthropicCostResponse: Decodable {
    let data: [Row]
    struct Row: Decodable {
        let model: String
        let amount: String
        let currency: String
    }
}
