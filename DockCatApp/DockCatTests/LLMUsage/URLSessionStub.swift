import Foundation

final class StubURLProtocol: URLProtocol {
    typealias Stub = (matcher: (URLRequest) -> Bool, response: (URLRequest) -> (HTTPURLResponse, Data))

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _stubs: [Stub] = []

    static func append(_ stub: Stub) {
        lock.lock(); defer { lock.unlock() }
        _stubs.append(stub)
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _stubs.removeAll()
    }

    private static func firstMatch(for request: URLRequest) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        return _stubs.first(where: { $0.matcher(request) })
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let match = Self.firstMatch(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (response, data) = match.response(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum URLSessionStub {
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func stub(urlContains: String, status: Int, jsonString: String) {
        StubURLProtocol.append((
            matcher: { req in req.url?.absoluteString.contains(urlContains) ?? false },
            response: { req in
                let response = HTTPURLResponse(
                    url: req.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(jsonString.utf8))
            }
        ))
    }
}
