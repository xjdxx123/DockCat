# 摸摸·余额气泡 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户点"摸摸"时，小猫除了换姿势/反转方向外，**额外弹气泡**显示某 provider 的余额；同时升级 `SpeechBubbleView` 背景到 Liquid Glass (macOS 26+)，旧系统 fallback。

**Architecture:** 在 `petCat()` 中加 1 行调用；balance message 抽成纯函数 `PetBalanceMessenger.message(...)` 方便单元测试；Liquid Glass 用 `#available(macOS 26.0, *)` 守卫，老系统保留 layer 样式。

**Tech Stack:** Swift, AppKit (`NSView`/`NSGlassEffectView`), XCTest.

**Spec:** `docs/superpowers/specs/2026-05-27-pet-balance-bubble-design.md`

---

## 项目背景（执行者必读）

- 项目根：`/Users/clintongao/coding/DockCat`
- Xcode 工程：`DockCatApp/DockCat.xcodeproj`
- Deployment target：`macOS 12.0`（重要！Liquid Glass 必须 availability 守卫）
- 源代码：`DockCatApp/DockCat/`
- 测试代码：`DockCatApp/DockCatTests/`
- 用 `PBXFileSystemSynchronizedRootGroup`：新增 `.swift` 文件自动入构建，**不要碰 `project.pbxproj`**
- 测试命令：`xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS'`
- Build 命令：`xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS'`

**已存在的相关代码**（前一个 feature 已落地）：
- `LLMUsageService` 中已经维持 `snapshots: [LLMProviderID: ProviderUsageSnapshot]` 和 `lastSuccessful: [LLMProviderID: LastGood]`，这两个是本期取数据的来源
- `CatWindowController.showBubble(message:primaryTitle:secondaryTitle:onPrimary:onSecondary:)` 已存在
- `SpeechBubbleView` 在 `DockCatApp/DockCat/UI/CatWindow/SpeechBubbleView.swift`

---

## 文件结构总览

新增：
```
DockCatApp/DockCat/Core/LLMUsage/PetBalanceMessenger.swift   # 纯函数 + LLMProviderID 扩展
DockCatApp/DockCatTests/LLMUsage/PetBalanceMessengerTests.swift
```

修改：
```
DockCatApp/DockCat/Support/AppStrings.swift           # +3 个属性 + 1 个 func
DockCatApp/DockCat/App/DockCatApplication.swift       # 改 petCat + 加 1 个私有方法
DockCatApp/DockCat/UI/CatWindow/SpeechBubbleView.swift  # 背景 Liquid Glass 升级
```

---

## Task 1: 添加 PetBalanceMessenger 纯函数 + `LLMProviderID.displayName`

**Files:**
- Create: `DockCatApp/DockCat/Core/LLMUsage/PetBalanceMessenger.swift`
- Create: `DockCatApp/DockCatTests/LLMUsage/PetBalanceMessengerTests.swift`

### Step 1: 写测试

Create `DockCatApp/DockCatTests/LLMUsage/PetBalanceMessengerTests.swift`:

```swift
import XCTest
@testable import DockCat

final class PetBalanceMessengerTests: XCTestCase {

    private let chineseStrings = AppStrings(language: .chinese)
    private let englishStrings = AppStrings(language: .english)

    private func successSnapshot(_ id: LLMProviderID, balance: Money?, spent: Money?) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .success(UsageData(
                balance: balance,
                totalSpent: spent,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ))
        )
    }

    private func failureSnapshot(_ id: LLMProviderID) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            fetchedAt: Date(),
            state: .failure(.unknown(detail: "network down"))
        )
    }

    // 注：randomPicker 注入让测试可确定性地选第一个候选

    func testNoData_returnsNoLLMMessage() {
        let result = PetBalanceMessenger.message(
            snapshots: [:],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "还没配置任何 LLM 账号呢")
    }

    func testNoData_english() {
        let result = PetBalanceMessenger.message(
            snapshots: [:],
            lastSuccessful: [:],
            strings: englishStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "No LLM accounts configured yet")
    }

    func testSuccessSnapshot_withBalance_chinese() {
        let snap = successSnapshot(.deepseek,
                                   balance: Money(amount: Decimal(string: "25.46")!, currency: "USD"),
                                   spent: nil)
        let result = PetBalanceMessenger.message(
            snapshots: [.deepseek: snap],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "你在 DeepSeek 还剩 $25.46")
    }

    func testSuccessSnapshot_withBalance_english() {
        let snap = successSnapshot(.deepseek,
                                   balance: Money(amount: Decimal(string: "25.46")!, currency: "USD"),
                                   spent: nil)
        let result = PetBalanceMessenger.message(
            snapshots: [.deepseek: snap],
            lastSuccessful: [:],
            strings: englishStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "You have $25.46 left on DeepSeek")
    }

    func testSuccessSnapshot_balanceNil_usesSpentLine() {
        let snap = successSnapshot(.openai,
                                   balance: nil,
                                   spent: Money(amount: Decimal(string: "42.18")!, currency: "USD"))
        let result = PetBalanceMessenger.message(
            snapshots: [.openai: snap],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "你这个月在 OpenAI 花了 $42.18")
    }

    func testLastSuccessful_usedWhenCurrentSnapshotFailed() {
        let last = LLMUsageService.LastGood(
            data: UsageData(
                balance: Money(amount: Decimal(string: "45.20")!, currency: "CNY"),
                totalSpent: nil,
                totalSpentLabel: .thisMonth,
                modelBreakdown: nil
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let result = PetBalanceMessenger.message(
            snapshots: [.kimi: failureSnapshot(.kimi)],
            lastSuccessful: [.kimi: last],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "你在 Kimi 还剩 ¥45.20")
    }

    func testMissingKeySnapshot_skipped() {
        let missing = ProviderUsageSnapshot(
            providerID: .deepseek,
            fetchedAt: Date(),
            state: .missingKey
        )
        // 只有 missingKey，没有 lastSuccessful → 算空
        let result = PetBalanceMessenger.message(
            snapshots: [.deepseek: missing],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        XCTAssertEqual(result, "还没配置任何 LLM 账号呢")
    }

    func testFailureSnapshot_skippedFromPool() {
        let fail = failureSnapshot(.deepseek)
        let success = successSnapshot(.kimi,
                                      balance: Money(amount: Decimal(string: "10.00")!, currency: "CNY"),
                                      spent: nil)
        let result = PetBalanceMessenger.message(
            snapshots: [.deepseek: fail, .kimi: success],
            lastSuccessful: [:],
            strings: chineseStrings,
            randomPicker: { $0.first }
        )
        // pool 应只含 kimi，failure 被跳过
        XCTAssertEqual(result, "你在 Kimi 还剩 ¥10.00")
    }

    func testProviderID_displayName() {
        XCTAssertEqual(LLMProviderID.anthropic.displayName, "Anthropic")
        XCTAssertEqual(LLMProviderID.openai.displayName, "OpenAI")
        XCTAssertEqual(LLMProviderID.openrouter.displayName, "OpenRouter")
        XCTAssertEqual(LLMProviderID.deepseek.displayName, "DeepSeek")
        XCTAssertEqual(LLMProviderID.kimi.displayName, "Kimi")
    }
}
```

### Step 2: 跑测试确认失败

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/PetBalanceMessengerTests 2>&1 | tail -20
```

Expected: 编译失败 ("Cannot find 'PetBalanceMessenger' in scope" + "'displayName' has no member" 等)

### Step 3: 实现

Create `DockCatApp/DockCat/Core/LLMUsage/PetBalanceMessenger.swift`:

```swift
import Foundation

extension LLMProviderID {
    var displayName: String {
        switch self {
        case .anthropic:  return "Anthropic"
        case .openai:     return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .deepseek:   return "DeepSeek"
        case .kimi:       return "Kimi"
        }
    }
}

enum PetBalanceMessenger {
    /// 从快照里随机选一个有数据的 provider，生成气泡文案。
    /// 完全无数据时返回"未配置"提示。
    /// - Parameter randomPicker: 注入用于测试（默认 `randomElement()`）
    static func message(
        snapshots: [LLMProviderID: ProviderUsageSnapshot],
        lastSuccessful: [LLMProviderID: LLMUsageService.LastGood],
        strings: AppStrings,
        randomPicker: ([(LLMProviderID, UsageData)]) -> (LLMProviderID, UsageData)? = { $0.randomElement() }
    ) -> String {
        let pool: [(LLMProviderID, UsageData)] = LLMProviderID.allCases.compactMap { id in
            if let snapshot = snapshots[id], case .success(let data) = snapshot.state {
                return (id, data)
            }
            if let last = lastSuccessful[id] {
                return (id, last.data)
            }
            return nil
        }
        guard let pick = randomPicker(pool) else {
            return strings.petBubbleNoLLM
        }
        return strings.petBubbleMessage(providerID: pick.0, data: pick.1)
    }
}
```

**注意**：这个文件用到 `strings.petBubbleNoLLM` 和 `strings.petBubbleMessage(providerID:data:)`，它们要在 Task 2 才会在 AppStrings 加上。所以**此时编译会失败**，等 Task 2 完成才会通过。**Task 1 不能单独 commit**，要和 Task 2 一起 commit。

### Step 4: 暂停，进 Task 2

不要 commit。等 Task 2 加完文案再一起验证。

---

## Task 2: AppStrings 新增文案

**Files:**
- Modify: `DockCatApp/DockCat/Support/AppStrings.swift`

### Step 1: 找到 AppStrings 文件底部

Read `DockCatApp/DockCat/Support/AppStrings.swift` 看到现有多个 `extension AppStrings { ... }` 块。新加的扩展追加到文件**最末尾**。

### Step 2: 追加新 extension

```swift
extension AppStrings {
    // 摸摸·余额气泡
    var petBubbleNoLLM: String {
        language == .chinese ? "还没配置任何 LLM 账号呢" : "No LLM accounts configured yet"
    }

    var petBubbleDismiss: String {
        language == .chinese ? "好的" : "OK"
    }

    func petBubbleMessage(providerID: LLMProviderID, data: UsageData) -> String {
        let name = providerID.displayName
        if let balance = data.balance {
            return language == .chinese
                ? "你在 \(name) 还剩 \(balance.formattedDisplay())"
                : "You have \(balance.formattedDisplay()) left on \(name)"
        } else if let spent = data.totalSpent {
            return language == .chinese
                ? "你这个月在 \(name) 花了 \(spent.formattedDisplay())"
                : "You spent \(spent.formattedDisplay()) on \(name) this month"
        } else {
            return language == .chinese
                ? "\(name) 现在没数据呢"
                : "\(name) has no data right now"
        }
    }
}
```

### Step 3: 跑 PetBalanceMessenger 测试

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' -only-testing:DockCatTests/PetBalanceMessengerTests 2>&1 | tail -20
```

Expected: 9 个测试全过。

### Step 4: Commit Task 1 + Task 2 一起

```bash
git add DockCatApp/DockCat/Core/LLMUsage/PetBalanceMessenger.swift \
        DockCatApp/DockCatTests/LLMUsage/PetBalanceMessengerTests.swift \
        DockCatApp/DockCat/Support/AppStrings.swift
git commit -m "feat(pet-bubble): add PetBalanceMessenger + bubble strings"
```

---

## Task 3: 修改 petCat() 添加余额气泡

**Files:**
- Modify: `DockCatApp/DockCat/App/DockCatApplication.swift`

### Step 1: 找到 petCat() 函数

`grep -n "private func petCat" DockCatApp/DockCat/App/DockCatApplication.swift` —— 应该在大约 line 1000。

### Step 2: 修改 petCat() 调用新方法

Replace existing `petCat()`:

```swift
private func petCat() {
    switch stateMachine.state {
    case .resting:
        let pose = renderer.randomPose(for: .resting, fallback: .dialogue)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        let point = clampedCatPoint(stateMachine.position)
        stateMachine.updateLongDurationPosition(point)
        catWindow.show(at: point)
        showPetBalanceBubble()
    case .walking:
        walkDirection *= -1
        catWindow.setMirrored(walkDirection < 0)
        showPetBalanceBubble()
    default:
        return
    }
}
```

### Step 3: 加新私有方法 `showPetBalanceBubble`

紧跟 `petCat()` 之后加：

```swift
private func showPetBalanceBubble() {
    let message = PetBalanceMessenger.message(
        snapshots: llmUsageService.snapshots,
        lastSuccessful: llmUsageService.lastSuccessful,
        strings: strings
    )
    catWindow.showBubble(
        message: message,
        primaryTitle: strings.petBubbleDismiss,
        secondaryTitle: nil,
        onPrimary: { [weak self] _ in self?.catWindow.hideBubble() },
        onSecondary: nil
    )
}
```

### Step 4: 兼容性校验

执行者注意：`catWindow.showBubble(...)` 的当前签名可能是：
```swift
func showBubble(
    message: String,
    primaryTitle: String,
    secondaryTitle: String,    // 可能是非可选
    onPrimary: (String?) -> Void,
    onSecondary: () -> Void
)
```

如果 `secondaryTitle` / `onSecondary` 是 **非可选** 必填：

**方案 A**：先扩展 `showBubble` 让 secondaryTitle 与 onSecondary 都接受 nil（修改 `CatWindowController` + `SpeechBubbleView`），再调用。

**方案 B（最小改动）**：传空串 + 空闭包，然后修改 `SpeechBubbleView.configure(...)` 在 secondaryTitle 为空时隐藏 secondary 按钮。

实施时按当前签名决定。先用 `grep -A 10 "func showBubble" DockCatApp/DockCat/UI/CatWindow/CatWindowController.swift` 看现有签名。

### Step 5: Build 通过性检查

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

### Step 6: Commit

```bash
git add DockCatApp/DockCat/App/DockCatApplication.swift
# 如果改了 CatWindowController 或 SpeechBubbleView 加签名兼容性，也 add 它们
git commit -m "feat(pet-bubble): show balance bubble on pet menu action"
```

---

## Task 4: SpeechBubbleView 升级到 Liquid Glass

**Files:**
- Modify: `DockCatApp/DockCat/UI/CatWindow/SpeechBubbleView.swift`

### Step 1: 读现有 init

Read `DockCatApp/DockCat/UI/CatWindow/SpeechBubbleView.swift`，line 33-40 左右是 `init(frame:)` 的开头几行，含 layer 背景设置。

### Step 2: 替换背景设置

把：

```swift
override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
    layer?.cornerRadius = 8
    layer?.borderColor = NSColor.separatorColor.cgColor
    layer?.borderWidth = 1

    // ... 其它原 label/button 配置不变
}
```

改为：

```swift
override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    if #available(macOS 26.0, *) {
        // Liquid Glass background (macOS 26 Tahoe+)
        let glass = NSGlassEffectView()
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        glass.cornerRadius = 16
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
    } else {
        // Fallback for macOS 12-25
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
    }

    // ... 其它原 label/button 配置不变
}
```

### Step 3: API 校准（可能需要）

`NSGlassEffectView` 在 macOS 26 SDK 中的精确 API 可能与 spec 描述不完全一致。如果出现：

- "Cannot find type 'NSGlassEffectView'" → 在当前 Xcode SDK 中此类型不存在；改用 `NSVisualEffectView` 作为近似（`.material = .hudWindow`、`.blendingMode = .behindWindow`、`.state = .active`），把 `#available` 改成 `if #available(macOS 11.0, *)`（即一直用 NSVisualEffectView）。代码块外加 TODO 注释说明：
  ```swift
  // TODO: 切回 NSGlassEffectView when macOS 26 SDK available
  ```
- "Value of type 'NSGlassEffectView' has no member 'cornerRadius'" → 改用 `glass.layer?.cornerRadius = 16`
- 其它编译错 → 用 Xcode 自动补全看真实 API。**保持 availability 守卫的结构**：新系统走新 API，老系统走 layer fallback。

### Step 4: Build 通过性检查

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat build -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`（可能伴随 1 个 `@available` warning，可以忽略）

### Step 5: 跑所有测试确认无回归

```
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat test -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: 之前的 49 个测试 + 新 9 个 = **58 测试全过**。

### Step 6: Commit

```bash
git add DockCatApp/DockCat/UI/CatWindow/SpeechBubbleView.swift
git commit -m "feat(speech-bubble): upgrade background to Liquid Glass on macOS 26+"
```

---

## Task 5: Push 到 fork

### Step 1: 检查 git 状态

```bash
git log --oneline | head -10
git status
```

Expected: 工作树干净，3 个新 commits（Task 1+2 合并、Task 3、Task 4）

### Step 2: Push 到 origin (即用户的 fork)

```bash
git push origin main 2>&1 | tail -5
```

Expected: 推送成功

---

## 完成标准

- [ ] 所有自动化测试通过（58/58）
- [ ] Build 在 macOS 12 deployment target 下成功
- [ ] 右键菜单 "摸摸" 在 resting/walking 状态触发气泡
- [ ] dialogue/outing 状态时摸摸不弹气泡
- [ ] 无 provider 配置时显示 "还没配置..." 提示
- [ ] PetBalanceMessenger 9 个测试场景都覆盖
- [ ] SpeechBubbleView 在 macOS 26+ 用 Liquid Glass / 在老系统保留原样式（任一可编译通过）
- [ ] Push 到 origin/main

---

## 备注 / 风险

- **NSGlassEffectView 真实 API**：若当前 Xcode SDK 还没暴露此类型，按 Task 4 Step 3 的 fallback 切到 NSVisualEffectView，保持视觉接近。
- **`showBubble` 签名**：实施时先 grep 确认 signature。如果 secondaryTitle 必填，按 Task 3 Step 4 的方案 A 或 B 处理。
- **Pure function 的优势**：把 message 逻辑放在 `PetBalanceMessenger` 是为了独立测试。`DockCatApplication.showPetBalanceBubble()` 只是个 thin wrapper。
- **不动 state machine**：本期 `petCat()` 仍不修改 cat state；bubble 纯 UI 覆盖。
