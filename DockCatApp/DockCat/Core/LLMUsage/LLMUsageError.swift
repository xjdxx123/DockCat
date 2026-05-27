import Foundation

enum LLMUsageError: Error, LocalizedError {
    case network(underlying: Error)
    case http(status: Int, body: String)
    case decoding(underlying: Error)
    case keychain(status: OSStatus)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .network(let underlying):
            return "网络错误：\(underlying.localizedDescription)"
        case .http(let status, let body):
            return "HTTP \(status)：\(body.prefix(200))"
        case .decoding:
            return "响应格式异常"
        case .keychain(let status):
            return "无法访问钥匙串 (status=\(status))"
        case .cancelled:
            return "已取消"
        }
    }
}
