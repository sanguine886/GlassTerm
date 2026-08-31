# 阶段变更日志

> 每阶段结束追加：交付物清单、验收结果、遗留风险（规范 §6.6.3）。

## P1 — SSH 引擎与主机管理（2026-08-31）

**交付物**

- `CoreSSH` 引擎（8 个源文件）：actor 会话 `SSHSession`（连接/exec/PTY/keepalive/指数退避重连，状态流广播）、Citadel 传输层（密码/密钥认证、`xterm-256color` shell、exec）、TOFU known-hosts（首次指纹确认、密钥变更阻断 + 重 pin）、`ReconnectPolicy`、`HostKeyFingerprint`（RFC 4253 wire 格式 + SEC1 未压缩点）、`SSHHostConfig`、`SSHError`（LocalizedError）
- `Persistence`：`HostRecord`（SwiftData 模型，秘密仅存 Keychain 引用 `secretRef`）、`HostStore`、`KeychainStore`（`ThisDeviceOnly`，replace-or-add 语义）
- App 层：主机列表（Glass 卡片）/ 新增编辑表单 / 指纹确认页（`.new` 与 `.changed` 警示双形态）/ exec 调试页；`HostManager` 编排（CRUD + 运行时从 Keychain 即时取密）
- 单测 6 文件共 49 用例：连接/重连/TOFU 三态/指纹（ed25519 + P256/P384/P521 与 `ssh-keygen -lf` 逐一对账）/ 密钥解析（ed25519 明密文、RSA OpenSSH）/ shell 信号原语
- 新增 ADR-0008（反射指纹提取 + Guard 测试钉死内部布局）、ADR-0009（exec 通道 keepalive）

**验收结果**（PR #4，CI run [33373451822](https://github.com/sanguine886/GlassTerm/actions/runs/33373451822) 全绿）

- [x] lint 全绿：swiftformat + swiftlint 零违规
- [x] CoreSSH `swift test` 49/49 通过；行覆盖率 **62.1%** ≥ 60%（ADR-0005）
- [x] Persistence 行覆盖率 **96.0%**（121/126）≥ 60%（SPM 包编译进 App 二进制，按 `Packages/Persistence/` 源路径过滤统计）
- [x] 模拟器 Build & Test：App 单测 15 + UI 冒烟 1 全过；Unsigned IPA 设备构建成功
- [ ] 真机：真实 Linux 主机（密码与密钥两种认证）连接稳定 30 分钟 —— **待测**
- [ ] 真机：主机密钥变更阻断 + 告警走查 —— **待测**

**CI 修复过程中发现并修复的真实缺陷**

- ECDSA 指纹：`rawRepresentation` 是 64 字节裸 `X||Y`，而 `ssh-keygen` 哈希 65 字节未压缩点（`0x04||X||Y`）；改用 `x963Representation` 后 P256/P384/P521 指纹与 `ssh-keygen -lf` 完全一致
- RSA 私钥认证死分支：`BEGIN OPENSSH PRIVATE KEY` 是 ed25519/RSA 共用容器，原判定把所有 RSA 私钥送进 Curve25519 解析必然失败；改为按算法标记 + OpenSSH 容器内先探测 ed25519（保护密文密钥）再降级 RSA

**遗留风险 / 待办**

- PKCS#1 格式 RSA 私钥不被 Citadel 解析（`keyParseFailed`）；OpenSSH 格式可用，PKCS#1 转换层记 backlog
- 真机自测清单待完成：弱网重连、后台切换、Face ID 门禁（P6）、深浅色截图归档 `docs/screenshots/p1/`
- `UIRequiresFullScreen` 自 iOS 26 弃用（P6 移除）
- 覆盖率先行约定：CoreSSH 用 `swift test` + llvm-cov（profdata），Persistence 用 xcodebuild xcresult + 源路径过滤；两处口径不同，P2 若出现口径分歧再统一

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
- [x] 深浅色：经系统语义色映射，两主题构建均通过；**真机截图验收通过**（iPhone 真机，深浅色各 4 页共 8 张，见 `docs/screenshots/p0/`）
- [x] 生成物（xcodeproj / Info.plist）不入库

**真机截图验收记录（2026-08-30）**

- 三层玻璃结构与 ≤2 层叠放合规；玻璃折射质感、连续圆角、间距刻度（4/8/12/16/24/32）真机观感正常；
- 审批卡双主题可读性好（命令块等宽字体、批准/拒绝按钮层次清晰）；Tab 玻璃胶囊与选中态正常；
- 发现并修复：GlassCard 宽度随内容收缩导致同屏卡片宽度不一（已加 `maxWidth: .infinity`）；
- 对比度实测结论：浅色主题辅文（secondaryLabel ≈ 3.45:1）满足规范「辅文 ≥ 3:1」；**正文信息自 P1 起必须用 primary label（≥ 4.5:1）**，不得用 secondary 呈现关键内容。

**遗留风险 / 待办**

- ~~玻璃折射、形变、光晕等视觉细节未做真机肉眼验收~~（已由真机截图验收覆盖；形变过渡与 Agent 光晕动效属 P5 交付时再验）
- 应用图标为空占位（P6 交付真实图标与清晰玻璃变体）
- 深浅色验收截图尚未纳入 CI Artifact（P1 起 UI 测试附加截图，真机截图继续人工采集归档于此目录）
- xccov 报告输出路径在部分 run 中为空，P1 一并修正（不影响覆盖率采集）
- `main` 分支保护未开启（个人账号暂无法强制 PR 审查，以流程纪律代替；公开仓库可开 required status check）
