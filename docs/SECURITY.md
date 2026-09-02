# GlazeVerre 安全规范

> 与代码同步演进。安全红线见开发提示词 §4.6 / §4.7 / §6.4。

## 1. 秘密管理（P1 ✅）

- 密码、私钥、passphrase、AI API Key **只存 Keychain**，属性
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，禁止备份迁移；
- SwiftData、日志（os.Logger）、UserDefaults 出现秘密即违规；
- 秘密隔离有专项单测（Persistence 模块，P1 起随阶段补充）。

## 当前状态（P1）

- 秘密管理已落地：密码 / 私钥 / 口令仅存 Keychain（`ThisDeviceOnly`），HostRecord 只持 opaque 引用（有单测断言）；
- 主机密钥 TOFU 已落地：SHA256 指纹首连确认、变更阻断告警、人工核实后可重固定；
- 错误与连接日志不落盘；调试页输出仅存内存。

## 2. 主机密钥校验（P1 ✅）

- 首连展示指纹，用户确认后 TOFU 固化；密钥变更即阻断并醒目告警；
- 校验不可跳过；调试例外必须用编译 flag 且不出现在 Release。

## 3. AI 边界（P4/P5）

- 模型只能提案，永远不能直接执行（提案-审批-执行）；
- 审批策略默认 `alwaysAsk`；危险命令分类器本地规则，任何策略下不可绕过；
- 发送给 AI 的上下文发送前必须可见；禁止附带凭据与主机原始地址（用别名）。

## 4. 日志与遥测

- 零网络遥测、零第三方分析/崩溃 SDK；
- `os.Logger` 中含密钥/主机地址/命令内容的字段标 `privacy: .private`；
- 错误日志本地保存，用户手动导出。

## 5. Release 纪律（P6）

- 关闭一切 debug 接口；`PrivacyInfo.xcprivacy` 如实申报；
- 图标、Face ID 门禁、屏幕共享防护随 P6 交付。

## 当前状态（P0）

工程骨架阶段：无网络面、无秘密存储、无遥测。上述条款自对应阶段起强制执行。
