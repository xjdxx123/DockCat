import XCTest
@testable import DockCat

final class OpenRouterUsageProviderTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testSuccess_computesBalanceAndSpent() async throws {
        URLSessionStub.stub(
            urlContains: "openrouter.ai/api/v1/credits",
            status: 200,
            jsonString: """
            {"data": {"total_credits": 100.00, "total_usage": 87.65}}
            """
        )
        let provider = OpenRouterUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-or-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success, got \(snapshot.state)")
        }
        XCTAssertEqual(data.balance, Money(amount: Decimal(12.35), currency: "USD"))
        XCTAssertEqual(data.totalSpent, Money(amount: Decimal(87.65), currency: "USD"))
        XCTAssertEqual(data.totalSpentLabel, .lifetime)
    }

    func testUnauthorized_returnsFailure() async throws {
        URLSessionStub.stub(urlContains: "openrouter.ai", status: 401,
                            jsonString: #"{"error":{"message":"No auth credentials found"}}"#)
        let provider = OpenRouterUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-bad")
        guard case .failure = snapshot.state else {
            return XCTFail("expected .failure")
        }
    }

    func testProviderMetadata() {
        let provider = OpenRouterUsageProvider()
        XCTAssertEqual(provider.id, .openrouter)
        XCTAssertEqual(provider.displayName, "OpenRouter")
        XCTAssertFalse(provider.supportsModelBreakdown)
        XCTAssertFalse(provider.requiresAdminKey)
    }
}
