# GlazeVerre

iOS 原生的、Liquid Glass 设计语言的、AI 可接管的 SSH 终端与服务器管理工具。

- **非侵入式**：100% 基于 SSH 协议，不在服务器上安装任何组件
- **手机优先**：为竖屏单手操作深度优化的终端体验
- **安全默认**：秘密只存 Keychain；AI 默认不能静默执行任何写操作
- **最低系统**：iOS 26.0（Liquid Glass 是产品身份）

## 构建

```sh
brew install xcodegen
xcodegen generate          # 生成 GlazeVerre.xcodeproj（生成产物，勿手改）
open GlazeVerre.xcodeproj
```

CI 在 GitHub Actions（`macos-26`，Xcode 26，iPhone 16 Pro 模拟器）上运行 lint 与全量测试；详见 `.github/workflows/ci.yml`。

## 文档

- [开发提示词](GlazeVerre-开发提示词.md)（仓库根目录，唯一需求与规范来源）
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架构与 ADR
- [SECURITY.md](docs/SECURITY.md) / [AI_AGENT.md](docs/AI_AGENT.md) / [TERMINAL.md](docs/TERMINAL.md)

## 二期路线图（v1.1+）

一期（P0–P5）已交付：SSH/SFTP 引擎、终端（SwiftTerm）、自定义 AI 接入（三协议）、AI 接管 Agent（审批/审计/kill switch）。以下为二期更新需求：

- **端口转发（L/R）+ 跳板机**：基于 Citadel 0.12.1 `createDirectTCPIPChannel` / `withRemotePortForward`，补齐 NIO 生命周期管理与 UI（含断开自动重建）
- **片段库流式输出**：CoreSSH exec 通道流式化，替代当前整块返回
- **审计日志加密落盘**：AES-GCM（密钥派生自生物识别门禁，规范 §6.3.3）
- **Agent/终端双视图真机联动**：Agent 执行回显进真实终端环形缓冲
- **P6 交付**：Face ID 门禁、隐私清单、错误日志导出、真实图标（iOS 26 清晰玻璃变体）、TestFlight

阶段交付与验收详见 [CHANGELOG-phase.md](docs/CHANGELOG-phase.md)。
