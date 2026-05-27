import Foundation

/// 标识错误种类，由 UI 层做语言映射，避免在数据层硬编码中文。
/// Identifies error kinds; the view layer localizes them so no language is baked into the data layer.
enum ProviderUsageError: Codable, Equatable, Hashable {
    case invalidKey
    case network(detail: String)
    case http(status: Int, body: String)
    case decoding
    case keychain(status: Int32)
    case adminKeyRequired
    case unknown(detail: String)
}
