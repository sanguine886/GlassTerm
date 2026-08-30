# 阶段变更日志

> 每阶段结束追加：交付物清单、验收结果、遗留风险（规范 §6.6.3）。

## P0 — 脚手架与设计系统（2026-08-30）

**交付物**

- XcodeGen 工程定义 `project.yml`（产物不入库，ADR-0001）
- 5 个 SPM 本地包骨架：GlassKit / CoreSSH / TerminalKit / AIAgent / Persistence（依赖方向单向；P0 零第三方依赖，ADR-0002）
- GlassKit：间距令牌（4/8/12/16/24/32）、语义色令牌（ADR-0006）、等宽字体令牌；`GlassCard` / `GlassButton` / `GlassBar` / `ApprovalCard`（含危险红调玻璃形态）
- 根 Tab 框架（服务器/终端/AI/设置）占位页跑通；iOS 26 原生玻璃 Tab Bar
- 本地化：String Catalog，zh-Hans + en 双语（ADR-0007）
- CI（`.github/workflows/ci.yml`）：`macos-26`（Xcode 26）swiftformat --lint → swiftlint → xcodegen → `xcodebuild test`（iPhone 16 Pro 模拟器，缺失时自动创建）
- 单测 4 项（间距刻度、审批卡数据模型）+ UI 冒烟 1 项（四 Tab 切换）
- docs 四件套：ARCHITECTURE 成稿（含 ADR-0001…0007）、SECURITY / AI_AGENT / TERMINAL 初稿

**验收结果**（PR #1，CI run [33317598194](https://github.com/sanguine886/GlassTerm/actions/runs/33317598194)）

- [x] lint 全绿：swiftformat --lint 通过，swiftlint 零警告
- [x] iPhone 16 Pro（iOS 26）模拟器安装运行；UI 冒烟通过（22.5s）
- [x] 单测 4/4 通过，覆盖率已采集（硬门槛自 P1 启用，ADR-0005）
- [x] Swift 6 并发编译零警告（App + 5 包）
- [x] 深浅色：经系统语义色映射，两主题构建均通过；对比度截图复核待真机
- [x] 生成物（xcodeproj / Info.plist）不入库

**遗留风险 / 待办**

- 玻璃折射、形变、光晕等视觉细节未做真机肉眼验收（本机无 Mac；可先走 unsigned ipa + Sideloadly 真机流程）
- 应用图标为空占位（P6 交付真实图标与清晰玻璃变体）
- 深浅色验收截图尚未作为 CI Artifact 产出（P1 起 UI 测试附加截图）
- xccov 报告输出路径在部分 run 中为空，P1 一并修正（不影响覆盖率采集）
- `main` 分支保护未开启（个人账号暂无法强制 PR 审查，以流程纪律代替；公开仓库可开 required status check）
