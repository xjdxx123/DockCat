import XCTest
@testable import DockCat

final class LLMKeychainStoreTests: XCTestCase {

    // 用一个独立 service name 隔离测试与生产环境
    private let testService = "com.dockcat.llm-usage.tests"
    private var store: LLMKeychainStore!

    override func setUp() {
        super.setUp()
        store = LLMKeychainStore(service: testService)
        // 清理所有可能残留的 key
        for id in LLMProviderID.allCases {
            try? store.delete(id)
        }
    }

    override func tearDown() {
        for id in LLMProviderID.allCases {
            try? store.delete(id)
        }
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        try store.save("sk-test-123", for: .anthropic)
        XCTAssertEqual(store.load(.anthropic), "sk-test-123")
    }

    func testHasKey() throws {
        XCTAssertFalse(store.hasKey(for: .openai))
        try store.save("sk-test-456", for: .openai)
        XCTAssertTrue(store.hasKey(for: .openai))
    }

    func testKeysAreIsolatedByProvider() throws {
        try store.save("anthropic-key", for: .anthropic)
        try store.save("openai-key", for: .openai)
        XCTAssertEqual(store.load(.anthropic), "anthropic-key")
        XCTAssertEqual(store.load(.openai), "openai-key")
    }

    func testSaveReplacesExisting() throws {
        try store.save("old-key", for: .deepseek)
        try store.save("new-key", for: .deepseek)
        XCTAssertEqual(store.load(.deepseek), "new-key")
    }

    func testDelete() throws {
        try store.save("kimi-key", for: .kimi)
        try store.delete(.kimi)
        XCTAssertNil(store.load(.kimi))
        XCTAssertFalse(store.hasKey(for: .kimi))
    }

    func testDeleteNonExistent_doesNotThrow() {
        XCTAssertNoThrow(try store.delete(.openrouter))
    }

    func testLoadNonExistent_returnsNil() {
        XCTAssertNil(store.load(.kimi))
    }
}
