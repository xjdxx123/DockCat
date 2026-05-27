import Foundation

struct OpenAIUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .openai
    let displayName = "OpenAI"
    let supportsModelBreakdown = true
    let requiresAdminKey = true
    let helpURL = URL(string: "https://platform.openai.com/settings/organization/admin-keys")!

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
        let modelsRequest = makeRequest(url: URL(string: "https://api.openai.com/v1/models")!, apiKey: apiKey)
        let probeResult = await session.fetchJSON(modelsRequest, as: OpenAIModelsProbe.self)
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
        let startTimestamp = monthStartUnixTimestamp()
        let usageURL = URL(string: "https://api.openai.com/v1/organization/usage/completions?start_time=\(startTimestamp)&group_by=model")!
        let usageRequest = makeRequest(url: usageURL, apiKey: apiKey)
        let usageResult = await session.fetchJSON(usageRequest, as: OpenAIUsageResponse.self)
        let usage: OpenAIUsageResponse
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
        let costURL = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startTimestamp)&group_by=line_item")!
        let costRequest = makeRequest(url: costURL, apiKey: apiKey)
        var costsByModel: [String: Money] = [:]
        var totalSpent = Decimal(0)
        var totalCurrency = "USD"
        if case .success(let costResponse) = await session.fetchJSON(costRequest, as: OpenAICostsResponse.self) {
            for bucket in costResponse.data {
                for entry in bucket.results {
                    let amount = entry.amount.value
                    costsByModel[entry.lineItem] = Money(amount: amount, currency: entry.amount.currency)
                    totalSpent += amount
                    totalCurrency = entry.amount.currency
                }
            }
        }

        // 4. Aggregate tokens across buckets per model.
        var byModel: [String: (input: Int, output: Int)] = [:]
        for bucket in usage.data {
            for entry in bucket.results {
                var current = byModel[entry.model] ?? (0, 0)
                current.input += entry.inputTokens
                current.output += entry.outputTokens
                byModel[entry.model] = current
            }
        }

        // 5. Compose the per-model breakdown.
        let breakdown: [ModelUsage] = byModel.map { name, tokens in
            ModelUsage(
                modelName: name,
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cost: costsByModel[name] ?? Money(amount: 0, currency: "USD")
            )
        }

        return .success(UsageData(
            balance: nil,
            totalSpent: Money(amount: totalSpent, currency: totalCurrency),
            totalSpentLabel: .thisMonth,
            modelBreakdown: breakdown
        ))
    }

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func monthStartUnixTimestamp() -> Int {
        var components = calendar.dateComponents([.year, .month], from: now())
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        let date = calendar.date(from: components) ?? now()
        return Int(date.timeIntervalSince1970)
    }
}

private struct OpenAIModelsProbe: Decodable {
    let data: [Item]
    struct Item: Decodable {
        let id: String
    }
}

private struct OpenAIUsageResponse: Decodable {
    let data: [Bucket]
    struct Bucket: Decodable { let results: [Row] }
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

private struct OpenAICostsResponse: Decodable {
    let data: [Bucket]
    struct Bucket: Decodable { let results: [Row] }
    struct Row: Decodable {
        let amount: Amount
        let lineItem: String
        enum CodingKeys: String, CodingKey {
            case amount
            case lineItem = "line_item"
        }
    }
    struct Amount: Decodable {
        let value: Decimal
        let currency: String
    }
}
