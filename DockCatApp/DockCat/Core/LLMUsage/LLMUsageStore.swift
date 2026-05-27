import Foundation

final class LLMUsageStore {
    private let defaults: UserDefaults
    private let key = "DockCat.LLMUsageSnapshots.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAll() -> [LLMProviderID: ProviderUsageSnapshot] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        do {
            let snapshots = try JSONDecoder().decode([ProviderUsageSnapshot].self, from: data)
            return Dictionary(uniqueKeysWithValues: snapshots.map { ($0.providerID, $0) })
        } catch {
            DockCatLog.app.error("Failed to decode LLM usage snapshots: \(error.localizedDescription)")
            return [:]
        }
    }

    func save(_ snapshot: ProviderUsageSnapshot) {
        var all = loadAll()
        all[snapshot.providerID] = snapshot
        persist(all)
    }

    func remove(_ providerID: LLMProviderID) {
        var all = loadAll()
        all.removeValue(forKey: providerID)
        persist(all)
    }

    private func persist(_ all: [LLMProviderID: ProviderUsageSnapshot]) {
        do {
            let data = try JSONEncoder().encode(Array(all.values))
            defaults.set(data, forKey: key)
        } catch {
            DockCatLog.app.error("Failed to encode LLM usage snapshots: \(error.localizedDescription)")
        }
    }
}
