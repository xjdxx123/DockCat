import Foundation
import Combine

@MainActor
final class LLMUsageService: ObservableObject {

    struct LastGood: Equatable {
        let data: UsageData
        let fetchedAt: Date
    }

    @Published private(set) var snapshots: [LLMProviderID: ProviderUsageSnapshot]
    @Published private(set) var lastSuccessful: [LLMProviderID: LastGood] = [:]
    @Published private(set) var refreshingIDs: Set<LLMProviderID> = []

    private let providers: [LLMProviderID: any LLMUsageProvider]
    private let keychain: LLMKeychainStore
    private let store: LLMUsageStore
    private let now: () -> Date

    convenience init() {
        self.init(
            providers: [
                .anthropic:  AnthropicUsageProvider(),
                .openai:     OpenAIUsageProvider(),
                .openrouter: OpenRouterUsageProvider(),
                .deepseek:   DeepSeekUsageProvider(),
                .kimi:       KimiUsageProvider(),
            ],
            keychain: LLMKeychainStore(),
            store: LLMUsageStore(),
            now: Date.init
        )
    }

    init(providers: [LLMProviderID: any LLMUsageProvider],
         keychain: LLMKeychainStore,
         store: LLMUsageStore,
         now: @escaping () -> Date) {
        self.providers = providers
        self.keychain = keychain
        self.store = store
        self.now = now
        let loaded = store.loadAll()
        self.snapshots = loaded
        // 从历史快照中提取成功的，作为 lastSuccessful 初始值
        for (id, snapshot) in loaded {
            if case .success(let data) = snapshot.state {
                self.lastSuccessful[id] = LastGood(data: data, fetchedAt: snapshot.fetchedAt)
            }
        }
    }

    var orderedProviders: [any LLMUsageProvider] {
        LLMProviderID.allCases.compactMap { providers[$0] }
    }

    func hasKey(for id: LLMProviderID) -> Bool {
        keychain.hasKey(for: id)
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for id in providers.keys {
                group.addTask { [weak self] in await self?.refresh(id) }
            }
        }
    }

    func refreshAllIfStale(maxAge: TimeInterval) async {
        let cutoff = now().addingTimeInterval(-maxAge)
        await withTaskGroup(of: Void.self) { group in
            for id in providers.keys {
                if let snapshot = snapshots[id], snapshot.fetchedAt > cutoff {
                    continue
                }
                group.addTask { [weak self] in await self?.refresh(id) }
            }
        }
    }

    func refresh(_ id: LLMProviderID) async {
        guard let provider = providers[id] else { return }
        refreshingIDs.insert(id)
        defer { refreshingIDs.remove(id) }

        let snapshot: ProviderUsageSnapshot
        if let key = keychain.load(id) {
            do {
                snapshot = try await provider.fetchUsage(apiKey: key)
            } catch {
                snapshot = ProviderUsageSnapshot(
                    providerID: id, fetchedAt: now(),
                    state: .failure(reason: error.localizedDescription)
                )
            }
        } else {
            snapshot = ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: .missingKey)
        }
        snapshots[id] = snapshot
        store.save(snapshot)
        // 只有成功才更新 lastSuccessful；失败不会污染已有的成功缓存
        if case .success(let data) = snapshot.state {
            lastSuccessful[id] = LastGood(data: data, fetchedAt: snapshot.fetchedAt)
        }
    }

    func saveKey(_ key: String, for id: LLMProviderID) async {
        try? keychain.save(key, for: id)
        await refresh(id)
    }

    func clearKey(_ id: LLMProviderID) {
        try? keychain.delete(id)
        store.remove(id)
        snapshots[id] = ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: .missingKey)
        lastSuccessful.removeValue(forKey: id)
    }
}
