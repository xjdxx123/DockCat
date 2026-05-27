import XCTest
@testable import DockCat

final class OpenAIUsageProviderTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func stubModelsOK() {
        URLSessionStub.stub(
            urlContains: "api.openai.com/v1/models",
            status: 200,
            jsonString: #"{"data":[{"id":"gpt-4o"}]}"#
        )
    }

    private func stubUsageOK() {
        URLSessionStub.stub(
            urlContains: "organization/usage/completions",
            status: 200,
            jsonString: """
            {
              "data": [
                {
                  "results": [
                    {"model": "gpt-4o", "input_tokens": 800000, "output_tokens": 200000},
                    {"model": "gpt-4o-mini", "input_tokens": 1500000, "output_tokens": 400000}
                  ]
                }
              ]
            }
            """
        )
    }

    private func stubCostsOK() {
        URLSessionStub.stub(
            urlContains: "organization/costs",
            status: 200,
            jsonString: """
            {
              "data": [
                {
                  "results": [
                    {"amount": {"value": 18.50, "currency": "USD"}, "line_item": "gpt-4o"},
                    {"amount": {"value": 3.20, "currency": "USD"}, "line_item": "gpt-4o-mini"}
                  ]
                }
              ]
            }
            """
        )
    }

    func testFullSuccess() async throws {
        stubModelsOK(); stubUsageOK(); stubCostsOK()
        let provider = OpenAIUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-admin-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success, got \(snapshot.state)")
        }
        XCTAssertNil(data.balance)
        XCTAssertEqual(data.totalSpent, Money(amount: Decimal(string: "21.70")!, currency: "USD"))
        XCTAssertEqual(data.modelBreakdown?.count, 2)
    }

    func testNormalKey_returnsKeyValidNoUsageAccess() async throws {
        stubModelsOK()
        URLSessionStub.stub(urlContains: "organization/usage", status: 401,
                            jsonString: #"{"error":{"message":"missing admin scope"}}"#)
        let provider = OpenAIUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-proj-normal")
        guard case .keyValidNoUsageAccess = snapshot.state else {
            return XCTFail("expected .keyValidNoUsageAccess, got \(snapshot.state)")
        }
    }

    func testInvalidKey_returnsFailure() async throws {
        URLSessionStub.stub(urlContains: "api.openai.com/v1/models", status: 401,
                            jsonString: #"{"error":{"message":"invalid_api_key"}}"#)
        let provider = OpenAIUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-bad")
        guard case .failure(let error) = snapshot.state else {
            return XCTFail("expected .failure")
        }
        if case .invalidKey = error {} else {
            XCTFail("expected .invalidKey error, got \(error)")
        }
    }

    func testProviderMetadata() {
        let provider = OpenAIUsageProvider()
        XCTAssertEqual(provider.id, .openai)
        XCTAssertEqual(provider.displayName, "OpenAI")
        XCTAssertTrue(provider.supportsModelBreakdown)
        XCTAssertTrue(provider.requiresAdminKey)
    }
}
