# GlassTerm

iOS 原生的、Liquid Glass 设计语言的、AI 可接管的 SSH 终端与服务器管理工具。

- **非侵入式**：100% 基于 SSH 协议，不在服务器上安装任何组件
- **手机优先**：为竖屏单手操作深度优化的终端体验
- **安全默认**：秘密只存 Keychain；AI 默认不能静默执行任何写操作
- **最低系统**：iOS 26.0（Liquid Glass 是产品身份）

## 构建

```sh
brew install xcodegen
xcodegen generate          # 生成 GlassTerm.xcodeproj（生成产物，勿手改）
open GlassTerm.xcodeproj
```

CI 在 GitHub Actions（`macos-26`，Xcode 26，iPhone 16 Pro 模拟器）上运行 lint 与全量测试；详见 `.github/workflows/ci.yml`。

## 文档

- [开发提示词](GlassTerm-开发提示词.md)（仓库根目录，唯一需求与规范来源）
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架构与 ADR
- [SECURITY.md](docs/SECURITY.md) / [AI_AGENT.md](docs/AI_AGENT.md) / [TERMINAL.md](docs/TERMINAL.md)
