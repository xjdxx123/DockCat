import Foundation

protocol LLMUsageProvider: Sendable {
    var id: LLMProviderID { get }
    var displayName: String { get }
    var supportsModelBreakdown: Bool { get }
    var requiresAdminKey: Bool { get }
    var helpURL: URL { get }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot
}
