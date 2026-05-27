import XCTest
@testable import DockCat

final class ProviderUsageSnapshotCodableTests: XCTestCase {

    func testRoundTrip_missingKey() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .missingKey
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testRoundTrip_keyValidNoUsageAccess() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: .anthropic,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .keyValidNoUsageAccess(hint: "Admin key required")
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testRoundTrip_success_full() throws {
        let usage = UsageData(
            balance: Money(amount: Decimal(string: "12.34")!, currency: "USD"),
            totalSpent: Money(amount: Decimal(string: "87.65")!, currency: "USD"),
            totalSpentLabel: .lifetime,
            modelBreakdown: [
                ModelUsage(
                    modelName: "claude-sonnet-4-7",
                    inputTokens: 1_200_000,
                    outputTokens: 380_000,
                    cost: Money(amount: Decimal(string: "28.40")!, currency: "USD")
                )
            ]
        )
        let snapshot = ProviderUsageSnapshot(
            providerID: .anthropic,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(usage)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testRoundTrip_failure() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: .openai,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .failure(reason: "Invalid API key")
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testAllProviderIDs_haveStableRawValues() {
        XCTAssertEqual(LLMProviderID.anthropic.rawValue, "anthropic")
        XCTAssertEqual(LLMProviderID.openai.rawValue, "openai")
        XCTAssertEqual(LLMProviderID.openrouter.rawValue, "openrouter")
        XCTAssertEqual(LLMProviderID.deepseek.rawValue, "deepseek")
        XCTAssertEqual(LLMProviderID.kimi.rawValue, "kimi")
        XCTAssertEqual(LLMProviderID.allCases.count, 5)
    }

    func testMoney_formatsAsUSD() {
        let m = Money(amount: Decimal(string: "12.34")!, currency: "USD")
        XCTAssertEqual(m.formattedDisplay(), "$12.34")
    }

    func testMoney_formatsAsCNY() {
        let m = Money(amount: Decimal(string: "45.20")!, currency: "CNY")
        XCTAssertEqual(m.formattedDisplay(), "¥45.20")
    }

    func testMoney_formatsUnknownCurrencyWithCode() {
        let m = Money(amount: Decimal(string: "10.00")!, currency: "EUR")
        XCTAssertEqual(m.formattedDisplay(), "EUR 10.00")
    }
}
