import SwiftUI

struct LLMUsagePanel: View {
    @ObservedObject var service: LLMUsageService
    let language: AppLanguage

    @State private var draftKeys: [LLMProviderID: String] = [:]
    @State private var editingKeyForProvider: LLMProviderID?
    @State private var expandedProviders: Set<LLMProviderID> = []

    private var strings: AppStrings { AppStrings(language: language) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().padding(.top, 8)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(service.orderedProviders, id: \.id) { provider in
                        ProviderCard(
                            provider: provider,
                            snapshot: service.snapshots[provider.id],
                            lastSuccessful: service.lastSuccessful[provider.id],
                            isRefreshing: service.refreshingIDs.contains(provider.id),
                            isEditing: editingKeyForProvider == provider.id,
                            draftKey: Binding(
                                get: { draftKeys[provider.id] ?? "" },
                                set: { draftKeys[provider.id] = $0 }
                            ),
                            isExpanded: expandedProviders.contains(provider.id),
                            strings: strings,
                            onSaveKey: { key in
                                Task {
                                    await service.saveKey(key, for: provider.id)
                                    draftKeys[provider.id] = ""
                                    editingKeyForProvider = nil
                                }
                            },
                            onEdit: { editingKeyForProvider = provider.id },
                            onClear: {
                                service.clearKey(provider.id)
                                draftKeys[provider.id] = ""
                                editingKeyForProvider = nil
                            },
                            onRetry: { Task { await service.refresh(provider.id) } },
                            onToggleExpand: {
                                if expandedProviders.contains(provider.id) {
                                    expandedProviders.remove(provider.id)
                                } else {
                                    expandedProviders.insert(provider.id)
                                }
                            },
                            onOpenHelp: { NSWorkspace.shared.open(provider.helpURL) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .onAppear {
            Task { await service.refreshAllIfStale(maxAge: 60) }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                Task { await service.refreshAll() }
            } label: {
                Label(strings.llmRefreshAll, systemImage: "arrow.clockwise")
            }
            .disabled(!service.refreshingIDs.isEmpty)
            Spacer()
            Text(lastUpdatedLabel)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 14).padding(.top, 10)
    }

    private var lastUpdatedLabel: String {
        let allDates = service.snapshots.values.map(\.fetchedAt)
        guard let oldest = allDates.min() else { return strings.llmNeverUpdated }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(strings.llmLastUpdatedPrefix) \(formatter.string(from: oldest))"
    }
}

private struct ProviderCard: View {
    let provider: any LLMUsageProvider
    let snapshot: ProviderUsageSnapshot?
    let lastSuccessful: LLMUsageService.LastGood?
    let isRefreshing: Bool
    let isEditing: Bool
    @Binding var draftKey: String
    let isExpanded: Bool
    let strings: AppStrings

    let onSaveKey: (String) -> Void
    let onEdit: () -> Void
    let onClear: () -> Void
    let onRetry: () -> Void
    let onToggleExpand: () -> Void
    let onOpenHelp: () -> Void

    var body: some View {
        GroupBox(label: header) {
            VStack(alignment: .leading, spacing: 8) {
                content
                Divider().opacity(0.4)
                keyControls
            }
            .padding(.vertical, 4)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(provider.displayName).font(.system(size: 14, weight: .semibold))
            Spacer()
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                statusIcon
            }
            if canExpand {
                Button { onToggleExpand() } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch snapshot?.state {
        case .none, .missingKey:
            Circle().fill(Color.secondary.opacity(0.6)).frame(width: 8, height: 8)
        case .keyValidNoUsageAccess:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var canExpand: Bool {
        guard provider.supportsModelBreakdown else { return false }
        guard case .success(let data) = snapshot?.state, data.modelBreakdown != nil else {
            return false
        }
        return true
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot?.state {
        case .none, .missingKey:
            Text(strings.llmMissingKey).foregroundStyle(.secondary)
        case .keyValidNoUsageAccess(let hint):
            HStack(spacing: 4) {
                Text(strings.llmKeyValidNoUsageHintPrefix + hint)
                    .foregroundStyle(.primary)
                Button(strings.llmHowToGetAdminKey) { onOpenHelp() }
                    .buttonStyle(.link)
            }
        case .success(let data):
            successContent(data: data)
        case .failure(let reason):
            VStack(alignment: .leading, spacing: 4) {
                if let last = lastSuccessful {
                    successContent(data: last.data).opacity(0.6)
                    Text("(\(relativeAge(of: last.fetchedAt)))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(reason).foregroundStyle(.red).lineLimit(2)
                    Button(strings.llmRetry) { onRetry() }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private func relativeAge(of date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        return strings.llmRelativeStaleText(minutes: minutes)
    }

    @ViewBuilder
    private func successContent(data: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let balance = data.balance {
                HStack {
                    Text(strings.llmBalanceLabel).foregroundStyle(.secondary)
                    Text(balance.formattedDisplay())
                }
            } else {
                HStack {
                    Text(strings.llmBalanceLabel).foregroundStyle(.secondary)
                    Text(strings.llmUnknownValue).foregroundStyle(.secondary)
                }
            }

            if let spent = data.totalSpent {
                let label = data.totalSpentLabel == .lifetime
                    ? strings.llmLifetimeSpent
                    : strings.llmThisMonthSpent
                HStack {
                    Text(label).foregroundStyle(.secondary)
                    Text(spent.formattedDisplay())
                }
            }

            if isExpanded, let breakdown = data.modelBreakdown, !breakdown.isEmpty {
                Divider().opacity(0.4).padding(.top, 4)
                Text(strings.llmModelBreakdown).font(.system(size: 12, weight: .semibold))
                let sorted = breakdown.sorted {
                    ($0.cost.amount as NSDecimalNumber).doubleValue
                        > ($1.cost.amount as NSDecimalNumber).doubleValue
                }
                ForEach(sorted.prefix(5), id: \.modelName) { row in
                    HStack {
                        Text(row.modelName).font(.system(size: 12, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(strings.llmInputTokens) \(formatTokens(row.inputTokens))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("\(strings.llmOutputTokens) \(formatTokens(row.outputTokens))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(row.cost.formattedDisplay())
                            .font(.system(size: 11)).frame(width: 60, alignment: .trailing)
                    }
                }
                if sorted.count > 5 {
                    Text(strings.llmShowMoreModels)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }

    @ViewBuilder
    private var keyControls: some View {
        if isEditing || ((snapshot?.state == .missingKey) || snapshot == nil) {
            HStack {
                SecureField(strings.llmKeyPlaceholder, text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                Button(strings.llmSaveKey) {
                    onSaveKey(draftKey)
                }
                .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            HStack {
                Text("••••••••••••••").foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Button(strings.llmEditKey) { onEdit() }
                    .buttonStyle(.borderless)
                Button(strings.llmClearKey) { onClear() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
        }
    }
}
