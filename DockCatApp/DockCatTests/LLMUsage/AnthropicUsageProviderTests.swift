import XCTest
@testable import DockCat

final class AnthropicUsageProviderTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func stubModelsOK() {
        URLSessionStub.stub(
            urlContains: "api.anthropic.com/v1/models",
            status: 200,
            jsonString: #"{"data":[{"id":"claude-sonnet-4-7"}]}"#
        )
    }

    private func stubUsageOK() {
        URLSessionStub.stub(
            urlContains: "usage_report/messages",
            status: 200,
            jsonString: """
            {
              "data": [
                {
                  "model": "claude-sonnet-4-7",
                  "input_tokens": 1200000,
                  "output_tokens": 380000
                },
                {
                  "model": "claude-opus-4-6",
                  "input_tokens": 240000,
                  "output_tokens": 95000
                }
              ]
            }
            """
        )
    }

    private func stubCostOK() {
        URLSessionStub.stub(
            urlContains: "cost_report",
            status: 200,
            jsonString: """
            {
              "data": [
                {"model": "claude-sonnet-4-7", "amount": "28.40", "currency": "USD"},
                {"model": "claude-opus-4-6", "amount": "13.78", "currency": "USD"}
              ]
            }
            """
        )
    }

    func testFullSuccess_withModelBreakdown() async throws {
        stubModelsOK(); stubUsageOK(); stubCostOK()
        let provider = AnthropicUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-ant-admin-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success, got \(snapshot.state)")
        }
        XCTAssertNil(data.balance)
        XCTAssertEqual(data.totalSpent, Money(amount: Decimal(string: "42.18")!, currency: "USD"))
        XCTAssertEqual(data.totalSpentLabel, .thisMonth)
        XCTAssertEqual(data.modelBreakdown?.count, 2)
        let sonnet = data.modelBreakdown?.first { $0.modelName == "claude-sonnet-4-7" }
        XCTAssertEqual(sonnet?.inputTokens, 1_200_000)
        XCTAssertEqual(sonnet?.outputTokens, 380_000)
        XCTAssertEqual(sonnet?.cost, Money(amount: Decimal(string: "28.40")!, currency: "USD"))
    }

    func testNormalKey_returnsKeyValidNoUsageAccess() async throws {
        stubModelsOK()  // models 端点能用，证明 key 有效
        URLSessionStub.stub(
            urlContains: "usage_report/messages",
            status: 401,
            jsonString: #"{"error":{"type":"authentication_error","message":"admin scope required"}}"#
        )
        let provider = AnthropicUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-ant-api03-normal")
        guard case .keyValidNoUsageAccess(let hint) = snapshot.state else {
            return XCTFail("expected .keyValidNoUsageAccess, got \(snapshot.state)")
        }
        XCTAssertTrue(hint.contains("Admin"))
    }

    func testInvalidKey_returnsFailure() async throws {
        URLSessionStub.stub(urlContains: "api.anthropic.com/v1/models", status: 401,
                            jsonString: #"{"error":{"message":"invalid x-api-key"}}"#)
        let provider = AnthropicUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-ant-bad")
        guard case .failure = snapshot.state else {
            return XCTFail("expected .failure")
        }
    }

    func testProviderMetadata() {
        let provider = AnthropicUsageProvider()
        XCTAssertEqual(provider.id, .anthropic)
        XCTAssertEqual(provider.displayName, "Anthropic")
        XCTAssertTrue(provider.supportsModelBreakdown)
        XCTAssertTrue(provider.requiresAdminKey)
    }
}
