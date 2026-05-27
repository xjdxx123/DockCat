import XCTest
@testable import DockCat

final class PetBalanceMessengerTests: XCTestCase {

    private let chineseStrings = AppStrings(language: .chinese)
    private let englishStrings = AppStrings(language: .english)

    private func successSnapshot(_ id: LLMProviderID, balance: Money?, spent: Money?) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(UsageData(
                balance: balance,
                totalSpent: spent,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        )
    }

    private func failureSnapshot(_ id: LLMProviderID) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            fetchedAt: Date(),
            state: .failure(.unknown(detail: "network down"))
        )
    }

    func testNoData_returnsNoLLMMessage() {
        let result = PetBalanceMessenger.message(
            snapshots: [:],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "还没配置任何 LLM 账号呢")
    }

    func testNoData_english() {
        let result = PetBalanceMessenger.message(
            snapshots: [:],
            lastSuccessful: [:],
            strings: englishStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "No LLM accounts configured yet")
    }

    func testSuccessSnapshot_withBalance_chinese() {
        let snap = successSnapshot(.deepseek,
                                   balance: Money(amount: Decimal(string: "25.46")!, currency: "USD"),
                                   spent: nil)
        let result = PetBalanceMessenger.message(
            snapshots: [.deepseek: snap],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "你在 DeepSeek 还剩 $25.46")
    }

    func testSuccessSnapshot_withBalance_english() {
        let snap = successSnapshot(.deepseek,
                                   balance: Money(amount: Decimal(string: "25.46")!, currency: "USD"),
                                   spent: nil)
        let result = PetBalanceMessenger.message(
            snapshots: [.deepseek: snap],
            lastSuccessful: [:],
            strings: englishStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "You have $25.46 left on DeepSeek")
    }

    func testSuccessSnapshot_balanceNil_usesSpentLine() {
        let snap = successSnapshot(.openai,
                                   balance: nil,
                                   spent: Money(amount: Decimal(string: "42.18")!, currency: "USD"))
        let result = PetBalanceMessenger.message(
            snapshots: [.openai: snap],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "你这个月在 OpenAI 花了 $42.18")
    }

    func testLastSuccessful_usedWhenCurrentSnapshotFailed() {
        let last = LLMUsageService.LastGood(
            data: UsageData(
                balance: Money(amount: Decimal(string: "45.20")!, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let result = PetBalanceMessenger.message(
            snapshots: [.kimi: failureSnapshot(.kimi)],
            lastSuccessful: [.kimi: last],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "你在 Kimi 还剩 ¥45.20")
    }

    func testMissingKeySnapshot_skipped() {
        let missing = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(),
            state: .missingKey
        )
        let result = PetBalanceMessenger.message(
            snapshots: [.deepseek: missing],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "还没配置任何 LLM 账号呢")
    }

    func testFailureSnapshot_skippedFromPool() {
        let fail = failureSnapshot(.deepseek)
        let success = successSnapshot(.kimi,
                                      balance: Money(amount: Decimal(string: "10.00")!, currency: "CNY"),
                                      spent: nil)
        let result = PetBalanceMessenger.message(
            snapshots: [.deepseek: fail, .kimi: success],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "你在 Kimi 还剩 ¥10.00")
    }

    func testProviderID_displayName() {
        XCTAssertEqual(LLMProviderID.anthropic.displayName, "Anthropic")
        XCTAssertEqual(LLMProviderID.openai.displayName, "OpenAI")
        XCTAssertEqual(LLMProviderID.openrouter.displayName, "OpenRouter")
        XCTAssertEqual(LLMProviderID.deepseek.displayName, "DeepSeek")
        XCTAssertEqual(LLMProviderID.kimi.displayName, "Kimi")
    }
}
