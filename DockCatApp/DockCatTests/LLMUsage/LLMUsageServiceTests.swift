import XCTest
@testable import DockCat

/// 用于注入到 service 测试的可控 provider
struct MockUsageProvider: LLMUsageProvider {
    let id: LLMProviderID
    let displayName: String
    let supportsModelBreakdown: Bool = false
    let requiresAdminKey: Bool = false
    let helpURL = URL(string: "https://example.com")!

    let fetchHandler: @Sendable (String) async throws -> ProviderUsageSnapshot

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        try await fetchHandler(apiKey)
    }
}

/// 线程安全的可变盒，便于在 @Sendable 闭包中跨 actor 修改状态。
final class TestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { self._value = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
    @discardableResult
    func mutate<R>(_ block: (inout T) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return block(&_value)
    }
}

@MainActor
final class LLMUsageServiceTests: XCTestCase {

    private let testService = "com.dockcat.llm-usage.tests.service.\(UUID().uuidString)"
    private var keychain: LLMKeychainStore!
    private var store: LLMUsageStore!
    private var defaults: UserDefaults!
    private let defaultsSuite = "com.dockcat.llm-usage.tests.service.\(UUID().uuidString)"

    override func setUp() async throws {
        try await super.setUp()
        keychain = LLMKeychainStore(service: testService)
        defaults = UserDefaults(suiteName: defaultsSuite)
        store = LLMUsageStore(defaults: defaults)
        for id in LLMProviderID.allCases { try? keychain.delete(id) }
    }

    override func tearDown() async throws {
        for id in LLMProviderID.allCases { try? keychain.delete(id) }
        defaults.removePersistentDomain(forName: defaultsSuite)
        try await super.tearDown()
    }

    private func makeService(providers: [LLMProviderID: any LLMUsageProvider],
                             now: @escaping () -> Date = Date.init) -> LLMUsageService {
        LLMUsageService(providers: providers, keychain: keychain, store: store, now: now)
    }

    func testRefresh_missingKey_setsState() async {
        let mock = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            XCTFail("should not call fetch when no key")
            return ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(), state: .missingKey)
        }
        let service = makeService(providers: [.deepseek: mock])
        await service.refresh(.deepseek)
        XCTAssertEqual(service.snapshots[.deepseek]?.state, .missingKey)
    }

    func testRefresh_withKey_callsProviderAndStoresSnapshot() async throws {
        try keychain.save("sk-test", for: .deepseek)
        let expectedSnapshot = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(UsageData(
                balance: Money(amount: 10, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        )
        let mock = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { key in
            XCTAssertEqual(key, "sk-test")
            return expectedSnapshot
        }
        let service = makeService(providers: [.deepseek: mock])
        await service.refresh(.deepseek)
        XCTAssertEqual(service.snapshots[.deepseek], expectedSnapshot)
        XCTAssertEqual(store.loadAll()[.deepseek], expectedSnapshot)
    }

    func testRefresh_providerThrows_setsFailure() async throws {
        try keychain.save("sk-test", for: .deepseek)
        let mock = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = makeService(providers: [.deepseek: mock])
        await service.refresh(.deepseek)
        guard case .failure(let error)? = service.snapshots[.deepseek]?.state else {
            return XCTFail("expected failure")
        }
        // Detail should match the thrown error's localizedDescription so we know it propagated;
        // the exact text varies by macOS version (older versions return "The Internet connection
        // appears to be offline", newer ones return a generic NSURLErrorDomain message).
        guard case .unknown(let detail) = error else {
            return XCTFail("expected .unknown error, got \(error)")
        }
        XCTAssertEqual(detail, URLError(.notConnectedToInternet).localizedDescription)
        XCTAssertFalse(detail.isEmpty)
    }

    func testRefreshAll_invokesAllProvidersConcurrently() async throws {
        try keychain.save("k1", for: .deepseek)
        try keychain.save("k2", for: .kimi)
        let provider1 = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(),
                                  state: .success(UsageData(
                                      balance: Money(amount: 1, currency: "CNY"),
                                      totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil)))
        }
        let provider2 = MockUsageProvider(id: .kimi, displayName: "Kimi") { _ in
            ProviderUsageSnapshot(providerID: .kimi, fetchedAt: Date(),
                                  state: .success(UsageData(
                                      balance: Money(amount: 2, currency: "CNY"),
                                      totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil)))
        }
        let service = makeService(providers: [.deepseek: provider1, .kimi: provider2])
        await service.refreshAll()
        XCTAssertNotNil(service.snapshots[.deepseek])
        XCTAssertNotNil(service.snapshots[.kimi])
    }

    func testRefreshAllIfStale_skipsRecent() async throws {
        try keychain.save("k", for: .deepseek)
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_100)
        let callCount = TestBox(0)
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            callCount.mutate { $0 += 1 }
            return ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: fixedNow,
                                         state: .missingKey)
        }
        let service = makeService(providers: [.deepseek: provider], now: { fixedNow })
        // 第一次拉
        await service.refreshAll()
        XCTAssertEqual(callCount.value, 1)
        // 30s 后再 refreshIfStale(60)，应跳过
        await service.refreshAllIfStale(maxAge: 60)
        XCTAssertEqual(callCount.value, 1, "should skip fresh snapshot")
    }

    func testSaveKey_storesAndRefreshes() async throws {
        let capturedKey = TestBox<String?>(nil)
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { key in
            capturedKey.value = key
            return ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(),
                                         state: .success(UsageData(
                                             balance: Money(amount: 5, currency: "CNY"),
                                             totalSpent: nil, totalSpentLabel: .thisMonth,
                                             modelBreakdown: nil)))
        }
        let service = makeService(providers: [.deepseek: provider])
        await service.saveKey("sk-new", for: .deepseek)
        XCTAssertEqual(capturedKey.value, "sk-new")
        XCTAssertEqual(keychain.load(.deepseek), "sk-new")
    }

    func testClearKey_removesKeyAndCacheAndResetsState() async throws {
        try keychain.save("sk-old", for: .deepseek)
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(),
                                  state: .success(UsageData(
                                      balance: Money(amount: 5, currency: "CNY"),
                                      totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil)))
        }
        let service = makeService(providers: [.deepseek: provider])
        await service.refresh(.deepseek)
        service.clearKey(.deepseek)

        XCTAssertNil(keychain.load(.deepseek))
        XCTAssertEqual(service.snapshots[.deepseek]?.state, .missingKey)
        XCTAssertNil(store.loadAll()[.deepseek])
        XCTAssertNil(service.lastSuccessful[.deepseek])
    }

    func testLastSuccessful_retainedAfterFailure() async throws {
        try keychain.save("sk-test", for: .deepseek)
        let successData = UsageData(
            balance: Money(amount: 50, currency: "CNY"),
            totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil
        )
        let callCount = TestBox(0)
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            let current = callCount.mutate { $0 += 1; return $0 }
            if current == 1 {
                return ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(),
                                             state: .success(successData))
            } else {
                throw URLError(.notConnectedToInternet)
            }
        }
        let service = makeService(providers: [.deepseek: provider])

        // 第一次：成功
        await service.refresh(.deepseek)
        XCTAssertEqual(service.lastSuccessful[.deepseek]?.data, successData)

        // 第二次：网络失败
        await service.refresh(.deepseek)
        if case .failure = service.snapshots[.deepseek]?.state {} else {
            XCTFail("expected current snapshot to be .failure")
        }
        // lastSuccessful 仍保留之前的成功数据
        XCTAssertEqual(service.lastSuccessful[.deepseek]?.data, successData)
    }

    func testLastSuccessful_populatedFromStoreOnInit() async throws {
        // 预写一个 success 快照到 store
        let successData = UsageData(
            balance: Money(amount: 50, currency: "CNY"),
            totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil
        )
        let snapshot = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(successData)
        )
        store.save(snapshot)
        // 新构建 service —— 应从 store 恢复 lastSuccessful
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = makeService(providers: [.deepseek: provider])
        XCTAssertEqual(service.lastSuccessful[.deepseek]?.data, successData)
    }
}
