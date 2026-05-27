import XCTest
@testable import DockCat

final class DeepSeekUsageProviderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testSuccess_returnsCNYBalance() async throws {
        URLSessionStub.stub(
            urlContains: "api.deepseek.com/user/balance",
            status: 200,
            jsonString: """
            {
              "is_available": true,
              "balance_infos": [
                {"currency": "CNY", "total_balance": "45.20"},
                {"currency": "USD", "total_balance": "6.50"}
              ]
            }
            """
        )
        let provider = DeepSeekUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success, got \(snapshot.state)")
        }
        XCTAssertEqual(data.balance, Money(amount: Decimal(string: "45.20")!, currency: "CNY"))
        XCTAssertNil(data.totalSpent)
        XCTAssertNil(data.modelBreakdown)
        XCTAssertEqual(snapshot.providerID, .deepseek)
    }

    func testInvalidKey_returnsFailure() async throws {
        URLSessionStub.stub(
            urlContains: "api.deepseek.com",
            status: 401,
            jsonString: #"{"error":{"message":"Authentication failed"}}"#
        )
        let provider = DeepSeekUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-bad")
        guard case .failure(let reason) = snapshot.state else {
            return XCTFail("expected .failure, got \(snapshot.state)")
        }
        XCTAssertTrue(reason.contains("401"), "got: \(reason)")
    }

    func testNoCNYBalance_returnsZero() async throws {
        URLSessionStub.stub(
            urlContains: "api.deepseek.com",
            status: 200,
            jsonString: #"{"is_available": true, "balance_infos": []}"#
        )
        let provider = DeepSeekUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(data.balance, Money(amount: 0, currency: "CNY"))
    }

    func testProviderMetadata() {
        let provider = DeepSeekUsageProvider()
        XCTAssertEqual(provider.id, .deepseek)
        XCTAssertEqual(provider.displayName, "DeepSeek")
        XCTAssertFalse(provider.supportsModelBreakdown)
        XCTAssertFalse(provider.requiresAdminKey)
    }
}
