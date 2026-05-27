import XCTest
@testable import DockCat

final class LLMUsageStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: LLMUsageStore!
    private let suiteName = "com.dockcat.llm-usage.tests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        store = LLMUsageStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeSuccessSnapshot(_ id: LLMProviderID = .deepseek) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(UsageData(
                balance: Money(amount: 45.2, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        )
    }

    func testLoadAll_emptyByDefault() {
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testSaveAndLoadAll() {
        let snapshot = makeSuccessSnapshot(.deepseek)
        store.save(snapshot)
        let all = store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[.deepseek], snapshot)
    }

    func testSaveMultiple_loadAll() {
        let s1 = makeSuccessSnapshot(.deepseek)
        let s2 = ProviderUsageSnapshot(providerID: .openai, fetchedAt: Date(), state: .missingKey)
        store.save(s1)
        store.save(s2)
        XCTAssertEqual(store.loadAll().count, 2)
    }

    func testSaveReplaces() {
        store.save(makeSuccessSnapshot(.deepseek))
        let updated = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(),
            state: .failure(.invalidKey)
        )
        store.save(updated)
        XCTAssertEqual(store.loadAll()[.deepseek], updated)
    }

    func testRemove() {
        store.save(makeSuccessSnapshot(.deepseek))
        store.remove(.deepseek)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testCorruptedData_returnsEmpty() {
        defaults.set(Data("garbage".utf8), forKey: "DockCat.LLMUsageSnapshots.v1")
        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
