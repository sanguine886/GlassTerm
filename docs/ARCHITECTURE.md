# GlassTerm 架构

> 本文与代码同步演进；结构性变更先改本文，再改代码（规范 §6.6.1）。
> 每次依据「规范 > MaidKit > 通用最佳实践」顺序做出的裁量，以 ADR 记入文末附录。

## 1. 概述

GlassTerm 是 iOS 26 原生 SwiftUI 应用：SSH 终端 + 服务器管理 + AI 运维助手。
架构三原则：**非侵入**（100% SSH，无服务端组件）、**手机优先**、**安全默认**
（秘密只进 Keychain；AI 只能提案，执行必须经人审批）。

## 2. 模块结构与依赖方向

```
App/                      # 入口、根 Tab、路由（SwiftUI）
Packages/
  GlassKit/               # Liquid Glass 设计系统：令牌、玻璃组件、动效
  CoreSSH/                # SSH/SFTP 引擎（纯逻辑，无 UI 依赖）
  TerminalKit/            # SwiftTerm 封装、扩展键盘、主题、会话视图
  AIAgent/                # AI 提供商适配、工具注册、Agent 循环、审批
  Persistence/            # SwiftData 模型与 Keychain 封装
```

依赖方向（单向，禁止反向）：

- `App → 各包`
- `TerminalKit / AIAgent → CoreSSH`
- `GlassKit` 不依赖任何业务包
- `CoreSSH`、`AIAgent` 禁止 import SwiftUI/UIKit；公开接口一律 protocol

## 3. 并发与状态模型

- Swift 6 语言模式（严格并发），零数据竞争警告合入；
- SSH 会话与 Agent 循环由 `actor` 封装（P1/P5 落地）；
- 跨模块异步接口使用 async/await 与 `AsyncStream`，禁止回调地狱与全局可变单例；
- UI 状态用 `@Observable` MVVM，业务逻辑不进 View。

## 4. 测试与验证（Validation）

借鉴 MaidKit ARCHITECTURE 的 Validation 纪律：**每阶段退出前必须全绿**。

```sh
swiftlint --quiet && swiftformat --lint .
xcodebuild test -project GlassTerm.xcodeproj -scheme GlassTerm \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -enableCodeCoverage YES
```

CI（`.github/workflows/ci.yml`）在 `macos-26`（Xcode 26，iOS 26 SDK）上执行上述全部命令。
单测底线与覆盖率门槛见规范 §6.5.2；P0 阶段为纯骨架，覆盖率硬门槛自 P1 引入（ADR-0005）。

## 5. 生成物纪律

- `GlassTerm.xcodeproj` 由 XcodeGen 生成，**不入库、不手改**；
- `App/Info.plist` 由 XcodeGen 从 `project.yml` 的 `info:` 块生成，不入库；
- SwiftData 宏展开同理（落地后）。

## 6. ADR 附录

| # | 决策（一行） |
|---|---|
| ADR-0001 | 工程文件用 XcodeGen 从 `project.yml` 生成，产物 gitignore，本地与 CI 均先 `xcodegen generate` |
| ADR-0002 | P0 零第三方依赖；依赖精确版本（exactVersion）锁定自首次引入生效——P1 引入 Citadel、P2 引入 SwiftTerm，即「依赖锁定」交付物的落地方式 |
| ADR-0003 | 单测集中放在宿主 App 的 `GlassTermTests` / `GlassTermUITests`（仅依赖公开 API，不用 @testable），保证单一 `xcodebuild test -scheme GlassTerm` 入口；包内不设独立 test target |
| ADR-0004 | `maidkit_ref/` 为本地只读精读副本，不入公共仓库（第三方代码再分发的许可风险），在 .gitignore 固定 |
| ADR-0005 | 60% 覆盖率硬门槛自 P1（首个有真实逻辑的阶段）起在 CI 启用；P0 只采集覆盖率报告不做断言 |
| ADR-0006 | 颜色令牌直接映射系统语义色（label / secondaryLabel / systemBackground 等），深浅色对比度由系统保证，不自绘调色板 |
| ADR-0007 | 文案走 String Catalog（`App/Resources/Localizable.xcstrings`），首发 zh-Hans + en；代码标识符一律英文 |
