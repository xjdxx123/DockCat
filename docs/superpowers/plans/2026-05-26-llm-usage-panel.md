# LLM 用量面板 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 DockCat 设置窗口新增 "LLM 用量" Tab，展示用户在 Anthropic / OpenAI / OpenRouter / DeepSeek / Kimi 五家 provider 的余额与花费数据。

**Architecture:** Provider 协议 + 注册表模式。每家 provider 实现 `LLMUsageProvider`，统一注入 `LLMUsageService` 协调器。API key 存 macOS Keychain，快照缓存到 UserDefaults。UI 是一个新增的 SwiftUI tab，通过 `@Published` 订阅 service 状态。

**Tech Stack:** Swift 5+、SwiftUI、AppKit、`Security` framework (Keychain)、`URLSession`、XCTest。

**Spec:** `docs/superpowers/specs/2026-05-26-llm-usage-panel-design.md`

---

## 项目背景（执行者必读）

- 项目根：`/Users/clintongao/coding/DockCat`
- Xcode 工程：`DockCatApp/DockCat.xcodeproj`
- 源代码目录：`DockCatApp/DockCat/`
- 测试代码目录：`DockCatApp/DockCatTests/`（已配置 target，目录待创建）
- 工程用 `PBXFileSystemSynchronizedRootGroup`：新增 `.swift` 文件到对应目录自动入构建，不用动 `project.pbxproj`
- 运行测试：`xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS'`，或 Xcode 内 `Cmd+U`
- 运行 app：`xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug build` 然后 open built bundle，或 Xcode 内 `Cmd+R`

---

## 文件结构总览

新增文件（按 Task 分组）：

```
DockCatApp/DockCat/Core/LLMUsage/
├── LLMProviderID.swift                 # Task 1
├── Money.swift                          # Task 1
├── ProviderUsageSnapshot.swift          # Task 1
├── LLMUsageError.swift                  # Task 2
├── LLMUsageProvider.swift               # Task 2
├── LLMKeychainStore.swift               # Task 3
├── LLMUsageStore.swift                  # Task 4
├── LLMUsageService.swift                # Task 11
└── Providers/
    ├── DeepSeekUsageProvider.swift      # Task 6
    ├── KimiUsageProvider.swift          # Task 7
    ├── OpenRouterUsageProvider.swift    # Task 8
    ├── AnthropicUsageProvider.swift     # Task 9
    └── OpenAIUsageProvider.swift        # Task 10

DockCatApp/DockCat/UI/Settings/
└── LLMUsagePanel.swift                  # Task 13

DockCatApp/DockCatTests/
├── LLMUsage/
│   ├── ProviderUsageSnapshotCodableTests.swift   # Task 1
│   ├── LLMKeychainStoreTests.swift               # Task 3
│   ├── LLMUsageStoreTests.swift                  # Task 4
│   ├── URLSessionStub.swift                      # Task 5
│   ├── DeepSeekUsageProviderTests.swift          # Task 6
│   ├── KimiUsageProviderTests.swift              # Task 7
│   ├── OpenRouterUsageProviderTests.swift        # Task 8
│   ├── AnthropicUsageProviderTests.swift         # Task 9
│   ├── OpenAIUsageProviderTests.swift            # Task 10
│   └── LLMUsageServiceTests.swift                # Task 11
```

修改文件：

```
DockCatApp/DockCat/Support/AppStrings.swift                 # Task 12: +15 文案
DockCatApp/DockCat/UI/Settings/SettingsView.swift           # Task 14: +1 tab
DockCatApp/DockCat/UI/Settings/SettingsWindowController.swift  # Task 15: 透传 service
DockCatApp/DockCat/App/DockCatApplication.swift             # Task 16: 装配 service
```

---

## Task 1: 核心数据类型（Money / Snapshot / State）

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/LLMProviderID.swift`
- Create: `DockCatApp/DockCat/Core/LLMUsage/Money.swift`
- Create: `DockCatApp/DockCat/Core/LLMUsage/ProviderUsageSnapshot.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/ProviderUsageSnapshotCodableTests.swift`

- [ ] **Step 1: 写测试文件**

Create `DockCatApp/DockCatTests/LLMUsage/ProviderUsageSnapshotCodableTests.swift`:

```swift
import XCTest
@testable import DockCat

final class ProviderUsageSnapshotCodableTests: XCTestCase {

    func testRoundTrip_missingKey() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .missingKey
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testRoundTrip_keyValidNoUsageAccess() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: .anthropic,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .keyValidNoUsageAccess(hint: "Admin key required")
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testRoundTrip_success_full() throws {
        let usage = UsageData(
            balance: Money(amount: Decimal(string: "12.34")!, currency: "USD"),
            totalSpent: Money(amount: Decimal(string: "87.65")!, currency: "USD"),
            totalSpentLabel: .lifetime,
            modelBreakdown: [
                ModelUsage(
                    modelName: "claude-sonnet-4-7",
                    inputTokens: 1_200_000,
                    outputTokens: 380_000,
                    cost: Money(amount: Decimal(string: "28.40")!, currency: "USD")
                )
            ]
        )
        let snapshot = ProviderUsageSnapshot(
            providerID: .anthropic,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(usage)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testRoundTrip_failure() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: .openai,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .failure(reason: "Invalid API key")
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testAllProviderIDs_haveStableRawValues() {
        XCTAssertEqual(LLMProviderID.anthropic.rawValue, "anthropic")
        XCTAssertEqual(LLMProviderID.openai.rawValue, "openai")
        XCTAssertEqual(LLMProviderID.openrouter.rawValue, "openrouter")
        XCTAssertEqual(LLMProviderID.deepseek.rawValue, "deepseek")
        XCTAssertEqual(LLMProviderID.kimi.rawValue, "kimi")
        XCTAssertEqual(LLMProviderID.allCases.count, 5)
    }

    func testMoney_formatsAsUSD() {
        let m = Money(amount: Decimal(string: "12.34")!, currency: "USD")
        XCTAssertEqual(m.formattedDisplay(), "$12.34")
    }

    func testMoney_formatsAsCNY() {
        let m = Money(amount: Decimal(string: "45.20")!, currency: "CNY")
        XCTAssertEqual(m.formattedDisplay(), "¥45.20")
    }

    func testMoney_formatsUnknownCurrencyWithCode() {
        let m = Money(amount: Decimal(string: "10.00")!, currency: "EUR")
        XCTAssertEqual(m.formattedDisplay(), "EUR 10.00")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: 编译失败 ("cannot find 'ProviderUsageSnapshot' in scope" 等)

- [ ] **Step 3: 实现 `LLMProviderID`**

Create `DockCatApp/DockCat/Core/LLMUsage/LLMProviderID.swift`:

```swift
import Foundation

enum LLMProviderID: String, Codable, CaseIterable, Hashable {
    case anthropic
    case openai
    case openrouter
    case deepseek
    case kimi
}
```

- [ ] **Step 4: 实现 `Money`**

Create `DockCatApp/DockCat/Core/LLMUsage/Money.swift`:

```swift
import Foundation

struct Money: Codable, Equatable, Hashable {
    let amount: Decimal
    let currency: String

    func formattedDisplay() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let amountString = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        switch currency {
        case "USD": return "$\(amountString)"
        case "CNY": return "¥\(amountString)"
        default:    return "\(currency) \(amountString)"
        }
    }
}
```

- [ ] **Step 5: 实现 `ProviderUsageSnapshot` + 相关类型**

Create `DockCatApp/DockCat/Core/LLMUsage/ProviderUsageSnapshot.swift`:

```swift
import Foundation

struct ProviderUsageSnapshot: Codable, Equatable, Hashable {
    let providerID: LLMProviderID
    let fetchedAt: Date
    let state: State

    enum State: Codable, Equatable, Hashable {
        case missingKey
        case keyValidNoUsageAccess(hint: String)
        case success(UsageData)
        case failure(reason: String)
    }
}

struct UsageData: Codable, Equatable, Hashable {
    let balance: Money?
    let totalSpent: Money?
    let totalSpentLabel: SpentLabel
    let modelBreakdown: [ModelUsage]?
}

enum SpentLabel: String, Codable, Hashable {
    case thisMonth
    case lifetime
}

struct ModelUsage: Codable, Equatable, Hashable {
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Money
}
```

- [ ] **Step 6: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `Test Suite 'ProviderUsageSnapshotCodableTests' passed` —— 8 个 case 全过。

- [ ] **Step 7: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/ DockCatApp/DockCatTests/LLMUsage/
git commit -m "feat(llm-usage): add core data types (LLMProviderID, Money, ProviderUsageSnapshot)"
```

---

## Task 2: Provider 协议与错误类型

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/LLMUsageError.swift`
- Create: `DockCatApp/DockCat/Core/LLMUsage/LLMUsageProvider.swift`

无独立测试 —— 是定义文件，靠后续 provider 实现来验证。

- [ ] **Step 1: 实现 `LLMUsageError`**

Create `DockCatApp/DockCat/Core/LLMUsage/LLMUsageError.swift`:

```swift
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
```

- [ ] **Step 2: 实现 `LLMUsageProvider` 协议**

Create `DockCatApp/DockCat/Core/LLMUsage/LLMUsageProvider.swift`:

```swift
import Foundation

protocol LLMUsageProvider: Sendable {
    var id: LLMProviderID { get }
    var displayName: String { get }
    var supportsModelBreakdown: Bool { get }
    var requiresAdminKey: Bool { get }
    var helpURL: URL { get }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot
}
```

- [ ] **Step 3: 编译通过性检查**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/LLMUsageError.swift DockCatApp/DockCat/Core/LLMUsage/LLMUsageProvider.swift
git commit -m "feat(llm-usage): add provider protocol and error type"
```

---

## Task 3: LLMKeychainStore

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/LLMKeychainStore.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/LLMKeychainStoreTests.swift`

- [ ] **Step 1: 写测试**

Create `DockCatApp/DockCatTests/LLMUsage/LLMKeychainStoreTests.swift`:

```swift
import XCTest
@testable import DockCat

final class LLMKeychainStoreTests: XCTestCase {

    // 用一个独立 service name 隔离测试与生产环境
    private let testService = "com.dockcat.llm-usage.tests"
    private var store: LLMKeychainStore!

    override func setUp() {
        super.setUp()
        store = LLMKeychainStore(service: testService)
        // 清理所有可能残留的 key
        for id in LLMProviderID.allCases {
            try? store.delete(id)
        }
    }

    override func tearDown() {
        for id in LLMProviderID.allCases {
            try? store.delete(id)
        }
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        try store.save("sk-test-123", for: .anthropic)
        XCTAssertEqual(store.load(.anthropic), "sk-test-123")
    }

    func testHasKey() throws {
        XCTAssertFalse(store.hasKey(for: .openai))
        try store.save("sk-test-456", for: .openai)
        XCTAssertTrue(store.hasKey(for: .openai))
    }

    func testKeysAreIsolatedByProvider() throws {
        try store.save("anthropic-key", for: .anthropic)
        try store.save("openai-key", for: .openai)
        XCTAssertEqual(store.load(.anthropic), "anthropic-key")
        XCTAssertEqual(store.load(.openai), "openai-key")
    }

    func testSaveReplacesExisting() throws {
        try store.save("old-key", for: .deepseek)
        try store.save("new-key", for: .deepseek)
        XCTAssertEqual(store.load(.deepseek), "new-key")
    }

    func testDelete() throws {
        try store.save("kimi-key", for: .kimi)
        try store.delete(.kimi)
        XCTAssertNil(store.load(.kimi))
        XCTAssertFalse(store.hasKey(for: .kimi))
    }

    func testDeleteNonExistent_doesNotThrow() {
        XCTAssertNoThrow(try store.delete(.openrouter))
    }

    func testLoadNonExistent_returnsNil() {
        XCTAssertNil(store.load(.kimi))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/LLMKeychainStoreTests 2>&1 | tail -20
```

Expected: 编译失败 "cannot find 'LLMKeychainStore' in scope"

- [ ] **Step 3: 实现 `LLMKeychainStore`**

Create `DockCatApp/DockCat/Core/LLMUsage/LLMKeychainStore.swift`:

```swift
import Foundation
import Security

final class LLMKeychainStore {
    private let service: String

    init(service: String = "com.dockcat.llm-usage") {
        self.service = service
    }

    func save(_ key: String, for provider: LLMProviderID) throws {
        try? delete(provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LLMUsageError.keychain(status: status)
        }
    }

    func load(_ provider: LLMProviderID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ provider: LLMProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw LLMUsageError.keychain(status: status)
        }
    }

    func hasKey(for provider: LLMProviderID) -> Bool {
        load(provider) != nil
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/LLMKeychainStoreTests 2>&1 | tail -20
```

Expected: 7 个测试全过。

> **如果遇到** "errSecMissingEntitlement" 错误：app/test target 需要 Keychain entitlement。打开 Xcode → DockCat target → Signing & Capabilities → 确认已勾选 Keychain Sharing（或检查 entitlements 文件已含 `keychain-access-groups`）。如果是新机首次跑可能弹钥匙串解锁框，输入密码后再跑一次。

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/LLMKeychainStore.swift DockCatApp/DockCatTests/LLMUsage/LLMKeychainStoreTests.swift
git commit -m "feat(llm-usage): add LLMKeychainStore for API key persistence"
```

---

## Task 4: LLMUsageStore（UserDefaults 快照缓存）

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/LLMUsageStore.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/LLMUsageStoreTests.swift`

- [ ] **Step 1: 写测试**

Create `DockCatApp/DockCatTests/LLMUsage/LLMUsageStoreTests.swift`:

```swift
import XCTest
@testable import DockCat

final class LLMUsageStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: LLMUsageStore!
    private let suiteName = "com.dockcat.llm-usage.tests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        store = LLMUsageStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeSuccessSnapshot(_ id: LLMProviderID = .deepseek) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(UsageData(
                balance: Money(amount: 45.2, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        )
    }

    func testLoadAll_emptyByDefault() {
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testSaveAndLoadAll() {
        let snapshot = makeSuccessSnapshot(.deepseek)
        store.save(snapshot)
        let all = store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[.deepseek], snapshot)
    }

    func testSaveMultiple_loadAll() {
        let s1 = makeSuccessSnapshot(.deepseek)
        let s2 = ProviderUsageSnapshot(providerID: .openai, fetchedAt: Date(), state: .missingKey)
        store.save(s1)
        store.save(s2)
        XCTAssertEqual(store.loadAll().count, 2)
    }

    func testSaveReplaces() {
        store.save(makeSuccessSnapshot(.deepseek))
        let updated = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(),
            state: .failure(reason: "Invalid key")
        )
        store.save(updated)
        XCTAssertEqual(store.loadAll()[.deepseek], updated)
    }

    func testRemove() {
        store.save(makeSuccessSnapshot(.deepseek))
        store.remove(.deepseek)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testCorruptedData_returnsEmpty() {
        defaults.set(Data("garbage".utf8), forKey: "DockCat.LLMUsageSnapshots.v1")
        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/LLMUsageStoreTests 2>&1 | tail -20
```

Expected: 编译失败 "cannot find 'LLMUsageStore'"

- [ ] **Step 3: 实现 `LLMUsageStore`**

Create `DockCatApp/DockCat/Core/LLMUsage/LLMUsageStore.swift`:

```swift
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
```

- [ ] **Step 4: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/LLMUsageStoreTests 2>&1 | tail -20
```

Expected: 6 个测试全过。

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/LLMUsageStore.swift DockCatApp/DockCatTests/LLMUsage/LLMUsageStoreTests.swift
git commit -m "feat(llm-usage): add LLMUsageStore for snapshot caching"
```

---

## Task 5: URLSession 测试桩（共享辅助类）

**Files:**
- Create: `DockCatApp/DockCatTests/LLMUsage/URLSessionStub.swift`

供后续所有 provider 测试使用，不打真接口。无独立测试 —— 通过后续 provider 测试验证。

- [ ] **Step 1: 实现 stub 与 helpers**

Create `DockCatApp/DockCatTests/LLMUsage/URLSessionStub.swift`:

```swift
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
```

- [ ] **Step 2: 编译通过性检查**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build-for-testing -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DockCatApp/DockCatTests/LLMUsage/URLSessionStub.swift
git commit -m "test(llm-usage): add URLSession stub helper for provider tests"
```

---

## Task 6: DeepSeekUsageProvider（最简单的 provider，先做）

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/Providers/DeepSeekUsageProvider.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/DeepSeekUsageProviderTests.swift`

- [ ] **Step 1: 写测试**

Create `DockCatApp/DockCatTests/LLMUsage/DeepSeekUsageProviderTests.swift`:

```swift
import XCTest
@testable import DockCat

final class DeepSeekUsageProviderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testSuccess_returnsCNYBalance() async throws {
        URLSessionStub.stub(
            urlContains: "api.deepseek.com/user/balance",
            status: 200,
            jsonString: """
            {
              "is_available": true,
              "balance_infos": [
                {"currency": "CNY", "total_balance": "45.20"},
                {"currency": "USD", "total_balance": "6.50"}
              ]
            }
            """
        )
        let provider = DeepSeekUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success, got \(snapshot.state)")
        }
        XCTAssertEqual(data.balance, Money(amount: Decimal(string: "45.20")!, currency: "CNY"))
        XCTAssertNil(data.totalSpent)
        XCTAssertNil(data.modelBreakdown)
        XCTAssertEqual(snapshot.providerID, .deepseek)
    }

    func testInvalidKey_returnsFailure() async throws {
        URLSessionStub.stub(
            urlContains: "api.deepseek.com",
            status: 401,
            jsonString: #"{"error":{"message":"Authentication failed"}}"#
        )
        let provider = DeepSeekUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-bad")
        guard case .failure(let reason) = snapshot.state else {
            return XCTFail("expected .failure, got \(snapshot.state)")
        }
        XCTAssertTrue(reason.contains("401") || reason.contains("Invalid"))
    }

    func testNoCNYBalance_returnsZero() async throws {
        URLSessionStub.stub(
            urlContains: "api.deepseek.com",
            status: 200,
            jsonString: #"{"is_available": true, "balance_infos": []}"#
        )
        let provider = DeepSeekUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(data.balance, Money(amount: 0, currency: "CNY"))
    }

    func testProviderMetadata() {
        let provider = DeepSeekUsageProvider()
        XCTAssertEqual(provider.id, .deepseek)
        XCTAssertEqual(provider.displayName, "DeepSeek")
        XCTAssertFalse(provider.supportsModelBreakdown)
        XCTAssertFalse(provider.requiresAdminKey)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/DeepSeekUsageProviderTests 2>&1 | tail -20
```

Expected: 编译失败 "cannot find 'DeepSeekUsageProvider'"

- [ ] **Step 3: 实现**

Create `DockCatApp/DockCat/Core/LLMUsage/Providers/DeepSeekUsageProvider.swift`:

```swift
import Foundation

struct DeepSeekUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .deepseek
    let displayName = "DeepSeek"
    let supportsModelBreakdown = false
    let requiresAdminKey = false
    let helpURL = URL(string: "https://platform.deepseek.com/api_keys")!

    private let session: URLSession
    private let now: () -> Date

    init(session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        let url = URL(string: "https://api.deepseek.com/user/balance")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let state = await fetchState(request: request)
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }

    private func fetchState(request: URLRequest) async -> ProviderUsageSnapshot.State {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(reason: "无效响应")
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(reason: "HTTP \(http.statusCode): \(body.prefix(120))")
            }
            let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
            let cnyEntry = decoded.balanceInfos.first(where: { $0.currency == "CNY" })
            let amount = cnyEntry.flatMap { Decimal(string: $0.totalBalance) } ?? 0
            return .success(UsageData(
                balance: Money(amount: amount, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        } catch let urlError as URLError {
            return .failure(reason: "网络错误：\(urlError.localizedDescription)")
        } catch {
            return .failure(reason: "响应格式异常")
        }
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/DeepSeekUsageProviderTests 2>&1 | tail -20
```

Expected: 4 个测试全过。

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/Providers/DeepSeekUsageProvider.swift DockCatApp/DockCatTests/LLMUsage/DeepSeekUsageProviderTests.swift
git commit -m "feat(llm-usage): add DeepSeekUsageProvider"
```

---

## Task 7: KimiUsageProvider

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/Providers/KimiUsageProvider.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/KimiUsageProviderTests.swift`

- [ ] **Step 1: 写测试**

Create `DockCatApp/DockCatTests/LLMUsage/KimiUsageProviderTests.swift`:

```swift
import XCTest
@testable import DockCat

final class KimiUsageProviderTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testSuccess_returnsCNYBalance() async throws {
        URLSessionStub.stub(
            urlContains: "api.moonshot.cn/v1/users/me/balance",
            status: 200,
            jsonString: """
            {
              "code": 0,
              "data": {
                "available_balance": 23.45,
                "voucher_balance": 0,
                "cash_balance": 23.45
              },
              "status": true
            }
            """
        )
        let provider = KimiUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success, got \(snapshot.state)")
        }
        XCTAssertEqual(data.balance, Money(amount: Decimal(23.45), currency: "CNY"))
    }

    func testUnauthorized_returnsFailure() async throws {
        URLSessionStub.stub(urlContains: "api.moonshot.cn", status: 401,
                            jsonString: #"{"error":"invalid_api_key"}"#)
        let provider = KimiUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-bad")
        guard case .failure = snapshot.state else {
            return XCTFail("expected .failure, got \(snapshot.state)")
        }
    }

    func testProviderMetadata() {
        let provider = KimiUsageProvider()
        XCTAssertEqual(provider.id, .kimi)
        XCTAssertEqual(provider.displayName, "Kimi")
        XCTAssertFalse(provider.supportsModelBreakdown)
        XCTAssertFalse(provider.requiresAdminKey)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/KimiUsageProviderTests 2>&1 | tail -20
```

Expected: 编译失败 "cannot find 'KimiUsageProvider'"

- [ ] **Step 3: 实现**

Create `DockCatApp/DockCat/Core/LLMUsage/Providers/KimiUsageProvider.swift`:

```swift
import Foundation

struct KimiUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .kimi
    let displayName = "Kimi"
    let supportsModelBreakdown = false
    let requiresAdminKey = false
    let helpURL = URL(string: "https://platform.moonshot.cn/console/api-keys")!

    private let session: URLSession
    private let now: () -> Date

    init(session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.moonshot.cn/v1/users/me/balance")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let state = await fetchState(request: request)
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }

    private func fetchState(request: URLRequest) async -> ProviderUsageSnapshot.State {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(reason: "无效响应")
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(reason: "HTTP \(http.statusCode): \(body.prefix(120))")
            }
            let decoded = try JSONDecoder().decode(KimiBalanceResponse.self, from: data)
            return .success(UsageData(
                balance: Money(amount: Decimal(decoded.data.availableBalance), currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        } catch let urlError as URLError {
            return .failure(reason: "网络错误：\(urlError.localizedDescription)")
        } catch {
            return .failure(reason: "响应格式异常")
        }
    }
}

private struct KimiBalanceResponse: Decodable {
    let data: BalanceData

    struct BalanceData: Decodable {
        let availableBalance: Double

        enum CodingKeys: String, CodingKey {
            case availableBalance = "available_balance"
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/KimiUsageProviderTests 2>&1 | tail -20
```

Expected: 3 个测试全过。

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/Providers/KimiUsageProvider.swift DockCatApp/DockCatTests/LLMUsage/KimiUsageProviderTests.swift
git commit -m "feat(llm-usage): add KimiUsageProvider"
```

---

## Task 8: OpenRouterUsageProvider

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/Providers/OpenRouterUsageProvider.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/OpenRouterUsageProviderTests.swift`

- [ ] **Step 1: 写测试**

Create `DockCatApp/DockCatTests/LLMUsage/OpenRouterUsageProviderTests.swift`:

```swift
import XCTest
@testable import DockCat

final class OpenRouterUsageProviderTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testSuccess_computesBalanceAndSpent() async throws {
        URLSessionStub.stub(
            urlContains: "openrouter.ai/api/v1/credits",
            status: 200,
            jsonString: """
            {"data": {"total_credits": 100.00, "total_usage": 87.65}}
            """
        )
        let provider = OpenRouterUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-or-test")
        guard case .success(let data) = snapshot.state else {
            return XCTFail("expected .success, got \(snapshot.state)")
        }
        XCTAssertEqual(data.balance, Money(amount: Decimal(12.35), currency: "USD"))
        XCTAssertEqual(data.totalSpent, Money(amount: Decimal(87.65), currency: "USD"))
        XCTAssertEqual(data.totalSpentLabel, .lifetime)
    }

    func testUnauthorized_returnsFailure() async throws {
        URLSessionStub.stub(urlContains: "openrouter.ai", status: 401,
                            jsonString: #"{"error":{"message":"No auth credentials found"}}"#)
        let provider = OpenRouterUsageProvider(session: URLSessionStub.makeSession())
        let snapshot = try await provider.fetchUsage(apiKey: "sk-bad")
        guard case .failure = snapshot.state else {
            return XCTFail("expected .failure")
        }
    }

    func testProviderMetadata() {
        let provider = OpenRouterUsageProvider()
        XCTAssertEqual(provider.id, .openrouter)
        XCTAssertEqual(provider.displayName, "OpenRouter")
        XCTAssertFalse(provider.supportsModelBreakdown)
        XCTAssertFalse(provider.requiresAdminKey)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/OpenRouterUsageProviderTests 2>&1 | tail -20
```

Expected: 编译失败 "cannot find 'OpenRouterUsageProvider'"

- [ ] **Step 3: 实现**

Create `DockCatApp/DockCat/Core/LLMUsage/Providers/OpenRouterUsageProvider.swift`:

```swift
import Foundation

struct OpenRouterUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .openrouter
    let displayName = "OpenRouter"
    let supportsModelBreakdown = false
    let requiresAdminKey = false
    let helpURL = URL(string: "https://openrouter.ai/settings/keys")!

    private let session: URLSession
    private let now: () -> Date

    init(session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/credits")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let state = await fetchState(request: request)
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }

    private func fetchState(request: URLRequest) async -> ProviderUsageSnapshot.State {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(reason: "无效响应")
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(reason: "HTTP \(http.statusCode): \(body.prefix(120))")
            }
            let decoded = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
            let total = Decimal(decoded.data.totalCredits)
            let used = Decimal(decoded.data.totalUsage)
            return .success(UsageData(
                balance: Money(amount: total - used, currency: "USD"),
                totalSpent: Money(amount: used, currency: "USD"),
                totalSpentLabel: .lifetime,
                modelBreakdown: nil
            ))
        } catch let urlError as URLError {
            return .failure(reason: "网络错误：\(urlError.localizedDescription)")
        } catch {
            return .failure(reason: "响应格式异常")
        }
    }
}

private struct OpenRouterCreditsResponse: Decodable {
    let data: CreditsData

    struct CreditsData: Decodable {
        let totalCredits: Double
        let totalUsage: Double

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/OpenRouterUsageProviderTests 2>&1 | tail -20
```

Expected: 3 个测试全过。

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/Providers/OpenRouterUsageProvider.swift DockCatApp/DockCatTests/LLMUsage/OpenRouterUsageProviderTests.swift
git commit -m "feat(llm-usage): add OpenRouterUsageProvider"
```

---

## Task 9: AnthropicUsageProvider

> ⚠️ **接入前要做的事**：spec 的"风险与未决项"提到 Anthropic admin API 的真实响应字段需要实测。
> 实施这一步前，执行者应该用一个真实 admin key 跑一次 `curl -H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=2026-05-01T00:00:00Z`，把响应 JSON 贴到 [docs/superpowers/notes/anthropic-usage-response.json](docs/superpowers/notes/anthropic-usage-response.json) 并据此调整下面测试的 stub JSON 与解码 struct。
> 如果暂时没有真实 admin key，**先按本计划提供的字段名实现**（基于 Anthropic 公开文档），后续真实接口跑通时再调整。

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/Providers/AnthropicUsageProvider.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/AnthropicUsageProviderTests.swift`

- [ ] **Step 1: 写测试**

Create `DockCatApp/DockCatTests/LLMUsage/AnthropicUsageProviderTests.swift`:

```swift
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
        XCTAssertNil(data.balance)  // Anthropic admin API 不返回余额
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
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/AnthropicUsageProviderTests 2>&1 | tail -20
```

Expected: 编译失败 "cannot find 'AnthropicUsageProvider'"

- [ ] **Step 3: 实现**

Create `DockCatApp/DockCat/Core/LLMUsage/Providers/AnthropicUsageProvider.swift`:

```swift
import Foundation

struct AnthropicUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .anthropic
    let displayName = "Anthropic"
    let supportsModelBreakdown = true
    let requiresAdminKey = true
    let helpURL = URL(string: "https://console.anthropic.com/settings/admin-keys")!

    private let session: URLSession
    private let now: () -> Date
    private let calendar: Calendar

    init(session: URLSession = .shared,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .init(identifier: .gregorian)) {
        self.session = session
        self.now = now
        self.calendar = calendar
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        let state = await resolveState(apiKey: apiKey)
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }

    private func resolveState(apiKey: String) async -> ProviderUsageSnapshot.State {
        // 1. 探测 key 是否有效
        do {
            let modelsURL = URL(string: "https://api.anthropic.com/v1/models")!
            let modelsRequest = makeRequest(url: modelsURL, apiKey: apiKey)
            let (_, modelsResp) = try await session.data(for: modelsRequest)
            guard let modelsHttp = modelsResp as? HTTPURLResponse else {
                return .failure(reason: "无效响应")
            }
            if modelsHttp.statusCode == 401 || modelsHttp.statusCode == 403 {
                return .failure(reason: "Invalid API key")
            }
            if modelsHttp.statusCode != 200 {
                return .failure(reason: "HTTP \(modelsHttp.statusCode)")
            }
        } catch let urlError as URLError {
            return .failure(reason: "网络错误：\(urlError.localizedDescription)")
        } catch {
            return .failure(reason: "响应格式异常")
        }

        // 2. 调 usage 端点
        let startISO = monthStartISO8601()
        let usageURL = URL(string:
            "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=\(startISO)")!
        let usageRequest = makeRequest(url: usageURL, apiKey: apiKey)

        let usageResult: Result<AnthropicUsageResponse, Int>
        do {
            let (data, response) = try await session.data(for: usageRequest)
            guard let http = response as? HTTPURLResponse else {
                return .failure(reason: "无效响应")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return .keyValidNoUsageAccess(
                    hint: "此 key 有效，但需要 Admin Key 才能查询用量"
                )
            }
            if http.statusCode != 200 {
                return .failure(reason: "HTTP \(http.statusCode)")
            }
            usageResult = .success(try JSONDecoder().decode(AnthropicUsageResponse.self, from: data))
        } catch let urlError as URLError {
            return .failure(reason: "网络错误：\(urlError.localizedDescription)")
        } catch {
            return .failure(reason: "响应格式异常")
        }

        // 3. 调 cost 端点
        let costURL = URL(string:
            "https://api.anthropic.com/v1/organizations/cost_report?starting_at=\(startISO)")!
        let costRequest = makeRequest(url: costURL, apiKey: apiKey)

        var costsByModel: [String: Money] = [:]
        var totalSpent = Decimal(0)
        do {
            let (data, response) = try await session.data(for: costRequest)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // cost 端点失败不阻塞用量展示
                return buildSuccess(usage: try usageResult.get(),
                                    costsByModel: [:],
                                    totalSpent: 0)
            }
            let costResp = try JSONDecoder().decode(AnthropicCostResponse.self, from: data)
            for entry in costResp.data {
                let amount = Decimal(string: entry.amount) ?? 0
                costsByModel[entry.model] = Money(amount: amount, currency: entry.currency)
                totalSpent += amount
            }
        } catch {
            // 同上，忽略
        }

        return buildSuccess(usage: try! usageResult.get(),
                            costsByModel: costsByModel,
                            totalSpent: totalSpent)
    }

    private func buildSuccess(usage: AnthropicUsageResponse,
                              costsByModel: [String: Money],
                              totalSpent: Decimal) -> ProviderUsageSnapshot.State {
        let breakdown: [ModelUsage] = usage.data.map { row in
            let cost = costsByModel[row.model] ?? Money(amount: 0, currency: "USD")
            return ModelUsage(
                modelName: row.model,
                inputTokens: row.inputTokens,
                outputTokens: row.outputTokens,
                cost: cost
            )
        }
        return .success(UsageData(
            balance: nil,
            totalSpent: Money(amount: totalSpent, currency: "USD"),
            totalSpentLabel: .thisMonth,
            modelBreakdown: breakdown
        ))
    }

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func monthStartISO8601() -> String {
        var components = calendar.dateComponents([.year, .month], from: now())
        components.day = 1
        components.hour = 0; components.minute = 0; components.second = 0
        let date = calendar.date(from: components) ?? now()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private struct AnthropicUsageResponse: Decodable {
    let data: [Row]
    struct Row: Decodable {
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        enum CodingKeys: String, CodingKey {
            case model
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

private struct AnthropicCostResponse: Decodable {
    let data: [Row]
    struct Row: Decodable {
        let model: String
        let amount: String
        let currency: String
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/AnthropicUsageProviderTests 2>&1 | tail -20
```

Expected: 4 个测试全过。

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/Providers/AnthropicUsageProvider.swift DockCatApp/DockCatTests/LLMUsage/AnthropicUsageProviderTests.swift
git commit -m "feat(llm-usage): add AnthropicUsageProvider with admin key fallback"
```

---

## Task 10: OpenAIUsageProvider

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/Providers/OpenAIUsageProvider.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/OpenAIUsageProviderTests.swift`

> 同 Task 9 的提示：执行者最好用真实 admin key 实测 `https://api.openai.com/v1/organization/usage/completions` 与 `costs` 端点的真实响应字段，必要时调整 stub JSON 与解码器。

- [ ] **Step 1: 写测试**

Create `DockCatApp/DockCatTests/LLMUsage/OpenAIUsageProviderTests.swift`:

```swift
import XCTest
@testable import DockCat

final class OpenAIUsageProviderTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func stubModelsOK() {
        URLSessionStub.stub(urlContains: "api.openai.com/v1/models", status: 200,
                            jsonString: #"{"data":[{"id":"gpt-4o"}]}"#)
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
        guard case .failure = snapshot.state else {
            return XCTFail("expected .failure")
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
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/OpenAIUsageProviderTests 2>&1 | tail -20
```

Expected: 编译失败 "cannot find 'OpenAIUsageProvider'"

- [ ] **Step 3: 实现**

Create `DockCatApp/DockCat/Core/LLMUsage/Providers/OpenAIUsageProvider.swift`:

```swift
import Foundation

struct OpenAIUsageProvider: LLMUsageProvider {
    let id: LLMProviderID = .openai
    let displayName = "OpenAI"
    let supportsModelBreakdown = true
    let requiresAdminKey = true
    let helpURL = URL(string: "https://platform.openai.com/settings/organization/admin-keys")!

    private let session: URLSession
    private let now: () -> Date
    private let calendar: Calendar

    init(session: URLSession = .shared,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .init(identifier: .gregorian)) {
        self.session = session
        self.now = now
        self.calendar = calendar
    }

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        let state = await resolveState(apiKey: apiKey)
        return ProviderUsageSnapshot(providerID: id, fetchedAt: now(), state: state)
    }

    private func resolveState(apiKey: String) async -> ProviderUsageSnapshot.State {
        // 1. 探测 key 有效性
        do {
            let modelsURL = URL(string: "https://api.openai.com/v1/models")!
            let (_, response) = try await session.data(for: makeRequest(url: modelsURL, apiKey: apiKey))
            guard let http = response as? HTTPURLResponse else {
                return .failure(reason: "无效响应")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return .failure(reason: "Invalid API key")
            }
            if http.statusCode != 200 {
                return .failure(reason: "HTTP \(http.statusCode)")
            }
        } catch let urlError as URLError {
            return .failure(reason: "网络错误：\(urlError.localizedDescription)")
        } catch {
            return .failure(reason: "响应格式异常")
        }

        // 2. 用量
        let startUnix = monthStartUnix()
        let usageURL = URL(string:
            "https://api.openai.com/v1/organization/usage/completions?start_time=\(startUnix)&group_by=model")!
        let usageResp: OpenAIUsageResponse
        do {
            let (data, response) = try await session.data(for: makeRequest(url: usageURL, apiKey: apiKey))
            guard let http = response as? HTTPURLResponse else {
                return .failure(reason: "无效响应")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return .keyValidNoUsageAccess(
                    hint: "此 key 有效，但需要 Admin Key 才能查询用量"
                )
            }
            if http.statusCode != 200 {
                return .failure(reason: "HTTP \(http.statusCode)")
            }
            usageResp = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
        } catch let urlError as URLError {
            return .failure(reason: "网络错误：\(urlError.localizedDescription)")
        } catch {
            return .failure(reason: "响应格式异常")
        }

        // 3. 花费
        let costsURL = URL(string:
            "https://api.openai.com/v1/organization/costs?start_time=\(startUnix)&group_by=line_item")!
        var costsByModel: [String: Money] = [:]
        var totalSpent = Decimal(0)
        if let (data, response) = try? await session.data(for: makeRequest(url: costsURL, apiKey: apiKey)),
           let http = response as? HTTPURLResponse,
           http.statusCode == 200,
           let costResp = try? JSONDecoder().decode(OpenAICostsResponse.self, from: data) {
            for bucket in costResp.data {
                for entry in bucket.results {
                    let amount = Decimal(entry.amount.value)
                    costsByModel[entry.lineItem] = Money(amount: amount,
                                                        currency: entry.amount.currency)
                    totalSpent += amount
                }
            }
        }

        // 4. 汇总 breakdown
        var byModel: [String: (input: Int, output: Int)] = [:]
        for bucket in usageResp.data {
            for entry in bucket.results {
                var current = byModel[entry.model] ?? (0, 0)
                current.input += entry.inputTokens
                current.output += entry.outputTokens
                byModel[entry.model] = current
            }
        }
        let breakdown: [ModelUsage] = byModel.map { name, tokens in
            ModelUsage(
                modelName: name,
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cost: costsByModel[name] ?? Money(amount: 0, currency: "USD")
            )
        }

        return .success(UsageData(
            balance: nil,
            totalSpent: Money(amount: totalSpent, currency: "USD"),
            totalSpentLabel: .thisMonth,
            modelBreakdown: breakdown
        ))
    }

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func monthStartUnix() -> Int {
        var components = calendar.dateComponents([.year, .month], from: now())
        components.day = 1; components.hour = 0; components.minute = 0; components.second = 0
        let date = calendar.date(from: components) ?? now()
        return Int(date.timeIntervalSince1970)
    }
}

private struct OpenAIUsageResponse: Decodable {
    let data: [Bucket]
    struct Bucket: Decodable { let results: [Row] }
    struct Row: Decodable {
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        enum CodingKeys: String, CodingKey {
            case model
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

private struct OpenAICostsResponse: Decodable {
    let data: [Bucket]
    struct Bucket: Decodable { let results: [Row] }
    struct Row: Decodable {
        let amount: Amount
        let lineItem: String
        enum CodingKeys: String, CodingKey {
            case amount
            case lineItem = "line_item"
        }
    }
    struct Amount: Decodable {
        let value: Double
        let currency: String
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/OpenAIUsageProviderTests 2>&1 | tail -20
```

Expected: 4 个测试全过。

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/Providers/OpenAIUsageProvider.swift DockCatApp/DockCatTests/LLMUsage/OpenAIUsageProviderTests.swift
git commit -m "feat(llm-usage): add OpenAIUsageProvider with admin key fallback"
```

---

## Task 11: LLMUsageService（协调器）

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/LLMUsageService.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/LLMUsageServiceTests.swift`

- [ ] **Step 1: 写测试**

Create `DockCatApp/DockCatTests/LLMUsage/LLMUsageServiceTests.swift`:

```swift
import XCTest
@testable import DockCat

/// 用于注入到 service 测试的可控 provider
struct MockUsageProvider: LLMUsageProvider {
    let id: LLMProviderID
    let displayName: String
    let supportsModelBreakdown: Bool = false
    let requiresAdminKey: Bool = false
    let helpURL = URL(string: "https://example.com")!

    let fetchHandler: @Sendable (String) async throws -> ProviderUsageSnapshot

    func fetchUsage(apiKey: String) async throws -> ProviderUsageSnapshot {
        try await fetchHandler(apiKey)
    }
}

@MainActor
final class LLMUsageServiceTests: XCTestCase {

    private let testService = "com.dockcat.llm-usage.tests.service.\(UUID().uuidString)"
    private var keychain: LLMKeychainStore!
    private var store: LLMUsageStore!
    private var defaults: UserDefaults!
    private let defaultsSuite = "com.dockcat.llm-usage.tests.service.\(UUID().uuidString)"

    override func setUp() async throws {
        try await super.setUp()
        keychain = LLMKeychainStore(service: testService)
        defaults = UserDefaults(suiteName: defaultsSuite)
        store = LLMUsageStore(defaults: defaults)
        for id in LLMProviderID.allCases { try? keychain.delete(id) }
    }

    override func tearDown() async throws {
        for id in LLMProviderID.allCases { try? keychain.delete(id) }
        defaults.removePersistentDomain(forName: defaultsSuite)
        try await super.tearDown()
    }

    private func makeService(providers: [LLMProviderID: any LLMUsageProvider],
                             now: @escaping () -> Date = Date.init) -> LLMUsageService {
        LLMUsageService(providers: providers, keychain: keychain, store: store, now: now)
    }

    func testRefresh_missingKey_setsState() async {
        let mock = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            XCTFail("should not call fetch when no key")
            return ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(), state: .missingKey)
        }
        let service = makeService(providers: [.deepseek: mock])
        await service.refresh(.deepseek)
        XCTAssertEqual(service.snapshots[.deepseek]?.state, .missingKey)
    }

    func testRefresh_withKey_callsProviderAndStoresSnapshot() async throws {
        try keychain.save("sk-test", for: .deepseek)
        let expectedSnapshot = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(UsageData(
                balance: Money(amount: 10, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        )
        let mock = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { key in
            XCTAssertEqual(key, "sk-test")
            return expectedSnapshot
        }
        let service = makeService(providers: [.deepseek: mock])
        await service.refresh(.deepseek)
        XCTAssertEqual(service.snapshots[.deepseek], expectedSnapshot)
        XCTAssertEqual(store.loadAll()[.deepseek], expectedSnapshot)
    }

    func testRefresh_providerThrows_setsFailure() async throws {
        try keychain.save("sk-test", for: .deepseek)
        let mock = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = makeService(providers: [.deepseek: mock])
        await service.refresh(.deepseek)
        guard case .failure(let reason)? = service.snapshots[.deepseek]?.state else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(reason.contains("internet") || reason.contains("Internet")
                      || reason.contains("connected"))
    }

    func testRefreshAll_invokesAllProvidersConcurrently() async throws {
        try keychain.save("k1", for: .deepseek)
        try keychain.save("k2", for: .kimi)
        let provider1 = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(),
                                  state: .success(UsageData(
                                      balance: Money(amount: 1, currency: "CNY"),
                                      totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil)))
        }
        let provider2 = MockUsageProvider(id: .kimi, displayName: "Kimi") { _ in
            ProviderUsageSnapshot(providerID: .kimi, fetchedAt: Date(),
                                  state: .success(UsageData(
                                      balance: Money(amount: 2, currency: "CNY"),
                                      totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil)))
        }
        let service = makeService(providers: [.deepseek: provider1, .kimi: provider2])
        await service.refreshAll()
        XCTAssertNotNil(service.snapshots[.deepseek])
        XCTAssertNotNil(service.snapshots[.kimi])
    }

    func testRefreshAllIfStale_skipsRecent() async throws {
        try keychain.save("k", for: .deepseek)
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_100)
        var callCount = 0
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            callCount += 1
            return ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: fixedNow,
                                         state: .missingKey)
        }
        let service = makeService(providers: [.deepseek: provider], now: { fixedNow })
        // 第一次拉
        await service.refreshAll()
        XCTAssertEqual(callCount, 1)
        // 30s 后再 refreshIfStale(60)，应跳过
        await service.refreshAllIfStale(maxAge: 60)
        XCTAssertEqual(callCount, 1, "should skip fresh snapshot")
    }

    func testSaveKey_storesAndRefreshes() async throws {
        var capturedKey: String?
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { key in
            capturedKey = key
            return ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(),
                                         state: .success(UsageData(
                                             balance: Money(amount: 5, currency: "CNY"),
                                             totalSpent: nil, totalSpentLabel: .thisMonth,
                                             modelBreakdown: nil)))
        }
        let service = makeService(providers: [.deepseek: provider])
        await service.saveKey("sk-new", for: .deepseek)
        XCTAssertEqual(capturedKey, "sk-new")
        XCTAssertEqual(keychain.load(.deepseek), "sk-new")
    }

    func testClearKey_removesKeyAndCacheAndResetsState() async throws {
        try keychain.save("sk-old", for: .deepseek)
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(),
                                  state: .success(UsageData(
                                      balance: Money(amount: 5, currency: "CNY"),
                                      totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil)))
        }
        let service = makeService(providers: [.deepseek: provider])
        await service.refresh(.deepseek)
        service.clearKey(.deepseek)

        XCTAssertNil(keychain.load(.deepseek))
        XCTAssertEqual(service.snapshots[.deepseek]?.state, .missingKey)
        XCTAssertNil(store.loadAll()[.deepseek])
        XCTAssertNil(service.lastSuccessful[.deepseek])
    }

    func testLastSuccessful_retainedAfterFailure() async throws {
        try keychain.save("sk-test", for: .deepseek)
        let successData = UsageData(
            balance: Money(amount: 50, currency: "CNY"),
            totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil
        )
        var callCount = 0
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderUsageSnapshot(providerID: .deepseek, fetchedAt: Date(),
                                             state: .success(successData))
            } else {
                throw URLError(.notConnectedToInternet)
            }
        }
        let service = makeService(providers: [.deepseek: provider])

        // 第一次：成功
        await service.refresh(.deepseek)
        XCTAssertEqual(service.lastSuccessful[.deepseek]?.data, successData)

        // 第二次：网络失败
        await service.refresh(.deepseek)
        if case .failure = service.snapshots[.deepseek]?.state {} else {
            XCTFail("expected current snapshot to be .failure")
        }
        // lastSuccessful 仍保留之前的成功数据
        XCTAssertEqual(service.lastSuccessful[.deepseek]?.data, successData)
    }

    func testLastSuccessful_populatedFromStoreOnInit() async throws {
        // 预写一个 success 快照到 store
        let successData = UsageData(
            balance: Money(amount: 50, currency: "CNY"),
            totalSpent: nil, totalSpentLabel: .thisMonth, modelBreakdown: nil
        )
        let snapshot = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(successData)
        )
        store.save(snapshot)
        // 新构建 service —— 应从 store 恢复 lastSuccessful
        let provider = MockUsageProvider(id: .deepseek, displayName: "DeepSeek") { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = makeService(providers: [.deepseek: provider])
        XCTAssertEqual(service.lastSuccessful[.deepseek]?.data, successData)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/LLMUsageServiceTests 2>&1 | tail -20
```

Expected: 编译失败 "cannot find 'LLMUsageService'"

- [ ] **Step 3: 实现**

Create `DockCatApp/DockCat/Core/LLMUsage/LLMUsageService.swift`:

```swift
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
```

- [ ] **Step 4: 跑测试确认通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/LLMUsageServiceTests 2>&1 | tail -20
```

Expected: 9 个测试全过。

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/LLMUsage/LLMUsageService.swift DockCatApp/DockCatTests/LLMUsage/LLMUsageServiceTests.swift
git commit -m "feat(llm-usage): add LLMUsageService coordinator with concurrent refresh"
```

---

## Task 12: AppStrings 文案

**Files:**
- Modify: `DockCatApp/DockCat/Support/AppStrings.swift`

- [ ] **Step 1: 找到合适的扩展插入位置**

Read `DockCatApp/DockCat/Support/AppStrings.swift` to find an existing `extension AppStrings { ... }` block (e.g. the one starting around line 213 with settings tab strings). The new strings should go in the same extension or a new one.

- [ ] **Step 2: 添加 LLM 用量相关文案**

Append a new `extension AppStrings` block to the bottom of the file (before the file's last line):

```swift
extension AppStrings {
    // LLM 用量 Tab
    var settingsLLMUsageTab: String { language == .chinese ? "LLM 用量" : "LLM Usage" }
    var llmRefreshAll: String { language == .chinese ? "刷新所有" : "Refresh all" }
    var llmRefreshing: String { language == .chinese ? "刷新中…" : "Refreshing…" }
    var llmLastUpdatedPrefix: String { language == .chinese ? "上次更新于" : "Updated at" }
    var llmNeverUpdated: String { language == .chinese ? "未刷新过" : "Never refreshed" }

    var llmBalanceLabel: String { language == .chinese ? "余额" : "Balance" }
    var llmThisMonthSpent: String { language == .chinese ? "本月花费" : "This month" }
    var llmLifetimeSpent: String { language == .chinese ? "累计花费" : "Total spent" }
    var llmUnknownValue: String { "—" }

    var llmMissingKey: String { language == .chinese ? "未配置" : "Not configured" }
    var llmKeyPlaceholder: String { language == .chinese ? "粘贴 API key…" : "Paste API key…" }
    var llmSaveKey: String { language == .chinese ? "保存" : "Save" }
    var llmEditKey: String { language == .chinese ? "修改" : "Edit" }
    var llmClearKey: String { language == .chinese ? "清除" : "Clear" }

    var llmHowToGetAdminKey: String { language == .chinese ? "如何获取?" : "How to get?" }
    var llmKeyValidNoUsageHintPrefix: String {
        language == .chinese
            ? "✓ Key 已连接 · "
            : "✓ Key connected · "
    }

    var llmRetry: String { language == .chinese ? "重试" : "Retry" }
    var llmModelBreakdown: String { language == .chinese ? "模型用量明细" : "Model breakdown" }
    var llmInputTokens: String { language == .chinese ? "输入" : "Input" }
    var llmOutputTokens: String { language == .chinese ? "输出" : "Output" }
    var llmShowMoreModels: String { language == .chinese ? "查看更多" : "Show more" }

    func llmRelativeStaleText(minutes: Int) -> String {
        switch language {
        case .chinese: return "\(minutes) 分钟前"
        case .english: return "\(minutes) min ago"
        }
    }
}
```

- [ ] **Step 3: 编译通过性检查**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add DockCatApp/DockCat/Support/AppStrings.swift
git commit -m "feat(llm-usage): add Chinese/English strings for LLM usage panel"
```

---

## Task 13: LLMUsagePanel SwiftUI

**Files:**
- Create: `DockCatApp/DockCat/UI/Settings/LLMUsagePanel.swift`

无单测（SwiftUI 视图层）—— 后续 Task 16 做手动 smoke test。

- [ ] **Step 1: 实现视图**

Create `DockCatApp/DockCat/UI/Settings/LLMUsagePanel.swift`:

```swift
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
        if isEditing || (snapshot?.state == .missingKey ?? true) {
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
```

- [ ] **Step 2: 编译通过性检查**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DockCatApp/DockCat/UI/Settings/LLMUsagePanel.swift
git commit -m "feat(llm-usage): add LLMUsagePanel SwiftUI view"
```

---

## Task 14: SettingsView 加 Tab

**Files:**
- Modify: `DockCatApp/DockCat/UI/Settings/SettingsView.swift`

- [ ] **Step 1: 读现有 SettingsView 找到 TabView**

Read `DockCatApp/DockCat/UI/Settings/SettingsView.swift:122-153` (body 部分中的 TabView 块)。

- [ ] **Step 2: 加 llmUsageService 参数 + tab**

Edit `DockCatApp/DockCat/UI/Settings/SettingsView.swift`:

在 `SettingsView` 的属性区（约 line 71-89 之间，draft / availableAssetPackIDs / usageStatistics 等属性之后）加一行：

```swift
    private let llmUsageService: LLMUsageService
```

在 init 签名（约 line 92-115）末尾加参数：

```swift
    init(
        settings: AppSettings,
        usageStatistics: UsageStatistics,
        outingCatalog: OutingCatalog,
        collectableInventory: CollectableInventory,
        dialogueImage: NSImage?,
        availableAssetPackIDs: [String],
        llmUsageService: LLMUsageService,                     // ← 新增
        onOpenAssetPacksFolder: @escaping () -> Void,
        onReloadAssetPackIDs: @escaping () -> [String],
        onLoadAssetPack: @escaping (String) -> AssetPackPreviewResult,
        onRestoreData: @escaping () -> Void,
        onSave: @escaping (AppSettings) -> Void
    ) {
        _draft = State(initialValue: settings)
        _availableAssetPackIDs = State(initialValue: availableAssetPackIDs)
        _previewImage = State(initialValue: dialogueImage)
        self.usageStatistics = usageStatistics
        self.outingCatalog = outingCatalog
        self.collectableInventory = collectableInventory
        self.llmUsageService = llmUsageService                // ← 新增
        self.onOpenAssetPacksFolder = onOpenAssetPacksFolder
        self.onReloadAssetPackIDs = onReloadAssetPackIDs
        self.onLoadAssetPack = onLoadAssetPack
        self.onRestoreData = onRestoreData
        self.onSave = onSave
    }
```

在 `var body` 的 TabView 中（约 line 124-136），加新 tab：

```swift
            TabView {
                petTab
                    .tabItem { Text(strings.settingsPetTab) }

                parametersTab
                    .tabItem { Text(strings.settingsParametersTab) }

                collectablesTab
                    .tabItem { Text(strings.settingsCollectablesTab) }

                LLMUsagePanel(service: llmUsageService, language: draft.language)
                    .tabItem { Text(strings.settingsLLMUsageTab) }

                aboutTab
                    .tabItem { Text(strings.settingsAboutTab) }
            }
```

- [ ] **Step 3: 编译通过性检查**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`（不通过会报错说 SettingsWindowController 调用 SettingsView 时缺 llmUsageService 参数，这是预期的 —— Task 15 修。先不要 commit。）

- [ ] **Step 4: 待 Task 15 完成后再 commit**

Task 15 之后一起 commit 这两个变更。

---

## Task 15: SettingsWindowController 透传 service

**Files:**
- Modify: `DockCatApp/DockCat/UI/Settings/SettingsWindowController.swift`

- [ ] **Step 1: 读 SettingsWindowController 的 init 与 SettingsView 构造点**

Read `DockCatApp/DockCat/UI/Settings/SettingsWindowController.swift` 全文，找到：
1. `init` 签名（约 line 30-50）
2. 创建 `SettingsView` 实例的地方（应该在 `makeContentView` 或类似方法中）

- [ ] **Step 2: init 加参数**

在 `SettingsWindowController` 的属性区加：

```swift
    private let llmUsageService: LLMUsageService
```

在 `init` 签名末尾加参数（保持现有参数顺序）：

```swift
    init(
        store: SettingsStore,
        settings: AppSettings,
        usageStatistics: UsageStatistics,
        outingCatalog: OutingCatalog,
        collectableInventory: CollectableInventory,
        dialogueImage: NSImage?,
        llmUsageService: LLMUsageService                  // ← 新增
    ) {
        self.store = store
        self.settings = settings
        self.usageStatistics = usageStatistics
        self.outingCatalog = outingCatalog
        self.collectableInventory = collectableInventory
        self.dialogueImage = dialogueImage
        self.llmUsageService = llmUsageService            // ← 新增
        super.init()
    }
```

- [ ] **Step 3: 构造 SettingsView 时传入**

在构造 `SettingsView(...)` 的地方，加 `llmUsageService: llmUsageService` 参数（位置匹配 Task 14 改后的 init 签名）。

- [ ] **Step 4: 编译通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: 还是会失败，因为 `DockCatApplication` 还没传 llmUsageService 给 controller。Task 16 修。

- [ ] **Step 5: 待 Task 16 完成后再 commit**

---

## Task 16: DockCatApplication 装配 + 全链路 smoke test

**Files:**
- Modify: `DockCatApp/DockCat/App/DockCatApplication.swift`

- [ ] **Step 1: 加 service 属性**

Read `DockCatApp/DockCat/App/DockCatApplication.swift` 找到 store/loader 属性集中声明的位置（约 line 5-22）。

加一行：

```swift
    private let llmUsageService = LLMUsageService()
```

- [ ] **Step 2: 构造 SettingsWindowController 时传入**

在 `applicationDidFinishLaunching` 里找到构造 `settingsWindowController = SettingsWindowController(...)` 的代码块。在参数列表末尾加：

```swift
        settingsWindowController = SettingsWindowController(
            store: settingsStore,
            settings: settings,
            usageStatistics: usageSessionTracker.snapshot,
            outingCatalog: outingCatalog,
            collectableInventory: collectableInventory,
            dialogueImage: renderer.randomPose(for: .dialogue).image,
            llmUsageService: llmUsageService               // ← 新增
        )
```

- [ ] **Step 3: 编译通过**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 跑全部测试**

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: 全部测试通过（约 40+ 个 case）。

- [ ] **Step 5: 手动 smoke test**

打开 Xcode → `Cmd+R` 运行 DockCat。

按下列清单逐项验证：

1. **打开设置 → 切到 "LLM 用量" Tab**
   - [ ] Tab 出现，5 张卡片显示，全部为"未配置"灰圆点
   - [ ] 顶部"刷新所有"按钮可见，"未刷新过"文案出现

2. **粘贴一个 DeepSeek 真实 key（如果有）**
   - [ ] 点保存后，几秒内显示绿色对勾 + CNY 余额
   - [ ] 关闭设置 → 重开 Tab → 仍显示数据（缓存有效）
   - [ ] 点"清除"后立即变回灰色"未配置"

3. **粘贴一个 OpenRouter key**
   - [ ] 显示余额 + 累计花费

4. **粘贴一个 Anthropic 普通 key（非 admin）**
   - [ ] 显示琥珀色感叹号
   - [ ] 文案为 "✓ Key 已连接 · 此 key 有效，但需要 Admin Key 才能查询用量"
   - [ ] 点"如何获取?"打开 Anthropic console 链接

5. **粘贴一个无效 key**
   - [ ] 显示红色 ✗
   - [ ] 显示 "Invalid API key" 错误 + 重试按钮

6. **切换中英文**
   - [ ] 在"宠物设置" Tab 切到 English
   - [ ] LLM 用量 Tab 所有文案变英文

7. **验证原功能未受影响**
   - [ ] 小猫仍出现在 Dock 上
   - [ ] 走动、休息、对话动画正常
   - [ ] 喝水/起身提醒能弹出
   - [ ] "宠物设置" / "参数设置" / "收藏品箱" / "支持" 四个原 Tab 数据正常显示

8. **关闭重启 app**
   - [ ] 已配置的 key 不丢失
   - [ ] 缓存的用量快照仍显示

- [ ] **Step 6: 把所有修改 commit**

```bash
git add DockCatApp/DockCat/App/DockCatApplication.swift \
        DockCatApp/DockCat/UI/Settings/SettingsView.swift \
        DockCatApp/DockCat/UI/Settings/SettingsWindowController.swift
git commit -m "feat(llm-usage): wire LLMUsageService into app and add tab to settings"
```

- [ ] **Step 7: 创建 PR / 收尾**

```bash
git log --oneline | head -20    # 检查 commit 历史
git status                      # 确认无未追踪文件
```

可选：推到远程分支并开 PR。

---

## 完成标准

执行完所有 16 个任务后，应满足：

- [ ] 所有自动化测试通过（`xcodebuild test` 退出码 0）
- [ ] App 启动 → 设置窗口 → "LLM 用量" Tab 可见且可交互
- [ ] 5 家 provider 均支持配置、保存、清除 key（key 落 Keychain）
- [ ] Spec 验收清单（spec 文档第 12 章）全部 ✓
- [ ] 原有功能（小猫、提醒、出门、其它 Tab）完全无回归
- [ ] Git 历史清晰：每个 commit 是独立可回滚的小单元

---

## 备注

- **跨重启回显上次成功**：本期 `lastSuccessful` 仅靠 `LLMUsageStore` 中已 success 的快照在 init 时恢复。如果用户关闭 app 时最新快照是 .failure，重启后 store 里就只有 failure（success 已被覆盖），lastSuccessful 会是空 —— UI 只能显示当前错误。要做到"任何时候关闭重启都能回显上次成功"，需要 `LLMUsageStore` 额外保存一份独立的 last-success 副本。优先级较低，列为后续优化。
- **Admin API 真实响应字段**：Task 9 / Task 10 的 stub JSON 是基于公开文档推断的。执行者拿到真实 admin key 时应该实测一次，必要时调整解码器字段名。
- **Keychain entitlement**：如果首次跑 test 报 `errSecMissingEntitlement`，按 Task 3 Step 4 的提示配置 Xcode capability。
