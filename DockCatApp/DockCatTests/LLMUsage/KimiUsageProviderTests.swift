import XCTest
@testable import DockCat

final class KimiUsageProviderTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testSuccess_returnsCNYBalance() async throws {
        URLSessionStub.stub(
            urlContains: "api.moonshot.cn/v1/users/me/balance",
            status: 200,
            jsonString: """
            {
              "code": 0,
              "data": {
                "available_balance": 23.45,
                "voucher_balance": 0,
                "cash_balance": 23.45
              },
              "status": true
            }
            """
        )
        let provider = KimiUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success, got \(snapshot.state)")
        }
        XCTAssertEqual(data.balance, Money(amount: Decimal(23.45), currency: "CNY"))
    }

    func testUnauthorized_returnsFailure() async throws {
        URLSessionStub.stub(urlContains: "api.moonshot.cn", status: 401,
                            jsonString: #"{"error":"invalid_api_key"}"#)
        let provider = KimiUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-bad")
        guard case .failure = snapshot.state else {
            return XCTFail("expected .failure, got \(snapshot.state)")
        }
    }

    func testProviderMetadata() {
        let provider = KimiUsageProvider()
        XCTAssertEqual(provider.id, .kimi)
        XCTAssertEqual(provider.displayName, "Kimi")
        XCTAssertFalse(provider.supportsModelBreakdown)
        XCTAssertFalse(provider.requiresAdminKey)
    }
}
