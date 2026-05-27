import Foundation

/// 自定义 URLProtocol，拦截所有请求并返回预设响应。
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var stubs: [(matcher: (URLRequest) -> Bool,
                                            response: (URLRequest) -> (HTTPURLResponse, Data))] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let match = Self.stubs.first(where: { $0.matcher(request) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (response, data) = match.response(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() { stubs.removeAll() }
}

enum URLSessionStub {
    /// 返回一个用 StubURLProtocol 拦截所有请求的 session
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// 注册一个 stub：URL 匹配时返回指定 status + JSON 字符串
    static func stub(urlContains: String, status: Int, jsonString: String) {
        StubURLProtocol.stubs.append((
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
