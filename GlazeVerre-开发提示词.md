# 开发提示词:GlazeVerre —— iOS Liquid Glass 风格 SSH 终端管理软件

> 使用方式:将本文档整体作为开发启动指令(系统提示词/需求基线)交给开发方(人类团队或 AI 编码代理)。
> 开发过程中本文档是唯一需求与规范来源;冲突时以本文档为准。修改规范必须先修订本文档,再动代码。

---

## 0. 你的角色与使命

你是一名资深 iOS 工程师,负责从零构建一款 iPhone 上的远程服务器管理软件:**GlazeVerre(暂定名)**。

它是一款 **SSH 终端 + 服务器管理 + AI 运维助手** 三位一体的原生 iOS 应用:

1. **SSH 基本能力**:多主机管理、密码/密钥认证、安全终端、SFTP 文件管理;
2. **CLI 终端适配**:为手机屏幕深度优化的终端体验(扩展键盘、字体主题、会话管理);
3. **自定义 AI 接入**:用户自带 AI 提供商(OpenAI 兼容 / Anthropic / Gemini),可配置模型;
4. **AI 接管操作**:AI Agent 通过工具调用直接操作服务器,在严格审批策略下执行命令、读写文件。

你的产出必须 **严格遵守本文档第 3 节(技术决策)、第 5 节(设计规范)、第 6 节(工程规范)**,并按第 7 节(开发计划)的阶段顺序推进,每阶段达到退出标准后才进入下一阶段。

---

## 1. 产品定义

### 1.1 一句话
一款 iOS 原生的、Liquid Glass 设计语言的、AI 可接管的 SSH 终端与服务器管理工具。

### 1.2 目标用户
用手机管理自己的 Linux 服务器/云主机的开发者与运维人员。

### 1.3 核心价值
- **非侵入式**:100% 基于 SSH 协议工作,**不在服务器上安装任何守护进程或软件**,不增加服务器攻击面(继承参考项目 MaidKit 的哲学)。
- **手机优先**:为竖屏单手操作重新设计终端交互,而不是把桌面软件缩小塞进手机。
- **安全默认**:所有秘密只存 Keychain;AI 默认不能静默执行任何写操作。
- **玻璃质感**:界面是 iOS 26 原生 Liquid Glass 的一等公民,深浅色双主题,克制而精致。

### 1.4 非目标(v1 红线,明确不做)
- ❌ Android / iPadOS 专属布局优化(代码保持可适配,v1 只交付 iPhone);
- ❌ Mosh、Telnet、串口连接;
- ❌ 服务器端常驻组件/云同步服务(连可选守护进程都不做);
- ❌ MCP 客户端/服务端(v2 预留,接口设计需为其留位);
- ❌ 任何第三方分析/广告/崩溃上报 SDK(崩溃日志本地导出即可);
- ❌ iOS 18 及以下系统支持(最低部署目标 **iOS 26.0**,Liquid Glass 是产品身份,不做降级样式层)。

---

## 2. 必读参考(开工前必须先读完)

| 优先级 | 材料 | 学什么 |
|---|---|---|
| ★★★ | [Solsynth/MaidKit](https://github.com/Solsynth/MaidKit)(本地精读副本在 `maidkit_ref/` 目录) | 模块划分(`servers/`、`agent/`、`containers/`)、终端模拟器**适配器模式**(`docs/TERMINAL_EMU_ADAPTER.md`)、AI Agent 的**提案-审批-执行**边界设计(`ssh_agent_service.dart`、`agent_run_policy.dart`)、凭证库与数据分离纪律、工程验证纪律(`docs/ARCHITECTURE.md` 的 Validation 一节) |
| ★★★ | Apple HIG「Liquid Glass」与 WWDC25 相关 SwiftUI API | `glassEffect` / `GlassEffectContainer` / `glassEffectID` 形变、`buttonStyle(.glass)`、玻璃层的层级与性能约束 |
| ★★☆ | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | `TerminalView` 的接入方式、委托回调、IME、选区、滚动缓冲 |
| ★★☆ | [Citadel](https://github.com/orlandos-nl/Citadel) 与 [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) | SSH 连接、认证、exec、PTY、SFTP 客户端 API |
| ★☆☆ | [OWASP Mobile Top 10](https://owasp.org/www-project-mobile-top-10/) 与 Apple Keychain 指南 | 第 6.4 节安全规范的依据 |

**重要提醒**:MaidKit 只借鉴 **工程架构与功能边界**,绝不借鉴视觉风格——它的 AGENTS.md 明确禁止玻璃效果,而本项目恰恰要求 Liquid Glass。MaidKit 是 Flutter 桌面优先,本项目是 **SwiftUI 原生、手机优先**。

---

## 3. 技术决策(已定稿,不得擅自更改)

### 3.1 头脑风暴结论:为什么是原生 SwiftUI,而不是 Flutter

| 决策点 | 候选 | 结论 | 理由 |
|---|---|---|---|
| UI 框架 | 原生 SwiftUI vs Flutter | **原生 SwiftUI** | 「iOS-Liquid-Glass」是 iOS 26 原生设计语言:`glassEffect` 的实时折射、高光、形变在 Flutter 中只能用 shader/blur 模拟,成熟度与性能都不达标;且手机端键盘附件、IME、触感反馈、Dynamic Type 在原生侧成本最低。产品只面向 iOS,跨平台价值为零 |
| SSH 库 | Citadel(SwiftNIO SSH)vs libssh2 C 绑定 vs NMSSH | **Citadel**(底层 SwiftNIO SSH) | 纯 Swift + async/await,API 现代化,无 C 依赖链维护负担;三个候选库均已核实处于活跃维护状态 |
| 终端模拟 | SwiftTerm vs 自研 VT 解析 vs libghostty | **SwiftTerm** | 生产级 VT100/xterm 实现(支持 ANSI 全集、鼠标上报、bracketed paste、CJK IME),由成熟社区维护;libghostty 需 Zig 工具链,iOS 构建链路脆弱;自研 VT 解析工作量不可控 |
| 状态管理 | SwiftUI @Observable + actors | **@Observable MVVM + Swift Concurrency actors** | SSH 会话与 Agent 循环必须 actor 隔离,天然契合 Swift 6 严格并发 |
| 持久化 | SwiftData + Keychain vs GRDB vs Core Data | **SwiftData(业务数据)+ Keychain(全部秘密)** | 与 SwiftUI 绑定最自然;秘密绝不允许进 SwiftData(与 MaidKit「Drift 不存凭据」同纪律) |
| AI 接入 | 各家 SDK vs 自研薄适配层 | **自研薄适配层(OpenAI 兼容为主)** | 用户要「自定义接入」:任意 baseURL + key + model;官方 SDK 各自为政且重;SSE 流式解析统一自研,协议三选一适配 |
| 最低系统 | iOS 26 vs iOS 18 + 降级 | **iOS 26.0** | 见 1.4 非目标 |

### 3.2 技术栈清单

| 层级 | 技术 |
|---|---|
| 语言 / UI | Swift 6(严格并发语言模式)、SwiftUI、UIKit 桥接(终端视图) |
| 最低部署目标 | iOS 26.0,iPhone 竖屏优先(横屏与 iPad 仅保证不崩) |
| SSH / SFTP | Citadel(SwiftNIO SSH 之上),SFTP 用 Citadel 的 SFTP 客户端 |
| 终端模拟 | SwiftTerm(版本锁定,升级须跑全量终端回归) |
| 持久化 | SwiftData(主机、片段、会话、审计日志);Keychain(kSecAttrAccessibleWhenUnlockedThisDeviceOnly,存密码/私钥/passphrase/AI API Key) |
| 生物识别 | LocalAuthentication(Face ID 门禁) |
| 网络(AI) | URLSession + 自研 SSE 流式解析(OpenAI 兼容 / Anthropic / Gemini 三协议) |
| 加密 | CryptoKit(AES-GCM 审计日志加密)、CommonCrypto PBKDF2(如需) |
| 工程化 | SPM 本地模块化包、XcodeGen 或手写 xcodeproj(二选一后固定)、SwiftLint + swift-format、XCTest |

### 3.3 工程结构(固定)

```
GlazeVerre/
  App/                      # App 入口、根 Tab、路由
  Packages/
    GlassKit/               # Liquid Glass 设计系统:令牌、玻璃组件、动效
    CoreSSH/                # SSH/SFTP 引擎(纯逻辑,无 UI 依赖,可单测)
    TerminalKit/            # SwiftTerm 封装、扩展键盘、主题、会话视图
    AIAgent/                # AI 提供商适配、工具注册、Agent 循环、审批
    Persistence/            # SwiftData 模型与 Keychain 封装
  docs/                     # ARCHITECTURE.md / SECURITY.md / AI_AGENT.md / TERMINAL.md
  maidkit_ref/              # 参考项目精读副本(只读)
```

- 模块依赖方向单向:`App → 各包`;`TerminalKit/AIAgent → CoreSSH`;`GlassKit` 不依赖任何业务包。
- `CoreSSH` 与 `AIAgent` 的公开接口必须是 `protocol`,UI 通过协议依赖,便于测试替身。

---

## 4. 功能规格(按优先级 P0 > P1 > P2,验收标准逐条核对)

### 4.1 主机管理(P0)
- 主机卡片列表(Liquid Glass 卡片),字段:名称、地址、端口、用户名、分组/标签、在线状态与延迟。
- 认证方式:密码;私钥(ED25519/RSA/ECDSA)+ 可选 passphrase;支持从 Files 导入私钥。
- 连接行为:一键连接、断线自动重连(指数退避,最多 5 次)、SSH keepalive(默认 15s,可配)。
- Known Hosts:首次连接展示**服务器主机密钥指纹**,用户确认后 TOFU 固化;密钥变更时阻断并醒目告警,允许手动更新。

### 4.2 SSH 核心引擎(P0)
- Shell 会话(PTY,`xterm-256color`)与单次 exec 通道并存,互不干扰。
- 会话由 actor 管理;App 进入后台尽力保活(后台任务 ~30s),超时挂起,回前台检测连接状态并提示重连;明确告知用户长时间任务建议配合 `tmux`/`screen`(检测到 tmux 会话时提示 attach)。
- 编码:UTF-8 全链路,中文输入输出无损。

### 4.3 终端体验——「CLI 终端适配」(P0)
- SwiftTerm 全功能:ANSI/truecolor、滚动缓冲 ≥ 10000 行、指针选区复制、粘贴、URL/文本智能识别、CJK IME 组合输入。
- **iOS 扩展键盘条**(常驻输入AccessoryView,可自定义按键):Esc / Tab / Ctrl(组合键)/ 方向键 / Home / End / 管道 / 波浪 / 常用符号,长按弹出变体;支持用户编辑按键布局。
- 字体(内置至少两款等宽字体)、字号(8–32pt)、终端配色主题(至少 5 套:含浅色、深色、Solarized、Dracula、Glass 自定义)。
- 多会话管理:标签页式,左滑关闭,底部 Tab 用玻璃材质;会话崩溃/断开有明确状态标记。
- 命令面板(P1):常用命令、已保存片段快捷执行。

### 4.4 SFTP 文件管理(P1)
- 单列表 + 面包屑导航(不做桌面双栏);新建/重命名/删除/移动/权限查看。
- 上传下载:接入 Files App(文档选择器)、分享sheet;下载进度可后台显示(本地通知,仅本地状态)。
- 内置文本编辑器:打开 ≤ 1MB 文本文件,保存写回;行号、语法高亮可后置(P2)。

### 4.5 自定义 AI 接入(P0)
- 提供商配置:自定义名称、协议类型(**OpenAI 兼容 / Anthropic / Gemini**)、BaseURL、API Key(Keychain)、默认模型、温度等参数。
- 模型列表自动发现(OpenAI `GET /models`;Anthropic `GET /v1/models`;Gemini `models.list`),也允许手填模型名。
- 多提供商并存,可切换;连接测试按钮(发一条 1 token 请求验证)。
- 对话:流式输出、Markdown 渲染、代码块一键复制;对话历史本地保存(SwiftData),支持多会话、删除、重命名。
- 所有请求走 TLS;**发送给 AI 的上下文在发送前必须可见**(见 4.6)。

### 4.6 AI 接管——Agent 模式(P0,安全边界最严格的模块)
参照 MaidKit `SshAgentService` 的边界设计:**模型只能提案,永远不能直接执行**。

- **工具集**(对模型暴露的 function):
  - `run_command(command, timeout_s)` — 在当前主机执行一条 shell 命令;
  - `read_file(path)` / `write_file(path, content)` / `list_dir(path)`;
  - `get_system_info()` — OS、发行版、内核、磁盘/内存概况(预置缓存,不浪费轮次);
  - `create_snippet(name, script)` / `run_snippet(name, target)`。
- **审批策略**(用户全局设置,默认 `alwaysAsk`):
  | 策略 | 行为 |
  |---|---|
  | `alwaysAsk`(默认) | 每个工具调用先出**审批卡**:展示命令全文、工作目录、影响摘要,用户 批准 / 编辑后批准 / 拒绝 |
  | `autoReview` | 模型输出 `safe_to_run`(只读、幂等)标记时自动放行,其余仍走审批卡;`safe_to_run` 由模型声明,**本地危险命令分类器二次否决** |
  | 只读模式 | `run_command` 只允许白名单只读命令前缀(`ls/cat/df/free/ps/…`),供不信任的场景 |
- **危险命令分类器**(本地规则,不依赖模型):`rm -rf`(尤其含 `/` 或变量)、`mkfs`、`dd`、`shutdown/reboot`、`chmod -R 777 /`、fork 炸弹、`DROP TABLE/DATABASE`、`> /dev/sd*`、`history -c` 等命中后**无论何种策略都必须人工确认**,高风险项要求**手动输入命令前 4 个字符**确认。
- **执行回路**:审批通过 → 在 SSH exec 通道执行 → 流式回传输出(截断策略:单次 ≤ 8KB,环形保留)→ 作为 tool result 续接对话;**任意时刻提供悬浮「立即中止」按钮**(kill switch:断开当前执行 + 取消后续工具调用)。
- **上下文构建**:系统提示词注入当前主机摘要(别名/OS/当前工作目录/最近 50 行终端输出环形缓冲);每次请求前 UI 展示「将发送给 AI 的内容」预览。
- **审计日志**(P1):每次工具调用记录时间、命令、结果摘要、审批人、策略;本地加密存储,可在设置中导出/清空。
- Agent 思考中在终端侧有可见状态(玻璃光晕动效,见第 5 节)。

### 4.7 安全与隐私(P0)
- Face ID / 设备密码 应用锁(P1 提供「启动时」「后台 5 分钟后」两档)。
- 屏幕共享防护:App 切换器缩略图与录屏时模糊主机地址(P1)。
- 无任何网络遥测;错误日志本地保存,用户手动导出。

---

## 5. 设计规范(Liquid Glass)

### 5.1 三层结构
1. **背景层**:全屏底色,深浅色自适应;允许服务器卡片以环境色产生极淡的色彩晕染(动态、低饱和)。
2. **玻璃层**:导航栏、底部 Tab、审批卡、浮动按钮等浮层使用原生 `.glassEffect(.regular.interactive)`;同屏多个玻璃元素必须包在 `GlassEffectContainer` 中;**同屏玻璃层叠 ≤ 2 层**,防止性能与可读性问题。
3. **内容层**:终端视图、文件列表等实体内容置于玻璃浮层之上,终端区域永不被玻璃覆盖(可读性红线)。

### 5.2 关键动效(克制原则:动效只用于表达状态变化)
- 连接建立:主机卡片 → 终端页用 `glassEffectID` 形变过渡;
- Agent 工作:执行工具时审批卡/状态胶囊发出呼吸光晕,完成后收敛;
- 危险确认:审批卡切换为警示玻璃形态(红调、轻微抖动一次)。
- 禁止:无意义循环动画、页面级渐变横幅、假仪表盘装饰。

### 5.3 基础指标
- 间距刻度 4/8/12/16/24/32;圆角遵循系统连续曲率;
- 文字对比度:玻璃面上正文 ≥ 4.5:1,辅文 ≥ 3:1;
- 全量适配 Dynamic Type;深浅色各出一套截图验收。

---

## 6. 工程规范(严格遵守;违反任何一条视为未完成)

### 6.1 架构规则
1. 严格按 3.3 的模块结构与依赖方向;业务逻辑禁止写进 SwiftUI View;
2. `CoreSSH`、`AIAgent` 不 import SwiftUI/UIKit;
3. SSH 会话由 `actor` 封装;所有跨模块异步接口使用 async/await 与 `AsyncStream`,禁止回调地狱与全局单例共享可变状态;
4. Swift 6 严格并发开启,零数据竞争警告合入;
5. 生成代码(SwiftData 宏展开、xcodegen 产物等)一律不手改。

### 6.2 代码规范
1. SwiftLint + swift-format 强制,CI 中不绿不合;禁用 `try!`、强制解包(测试代码除外);
2. 单文件 > 300 行、单类型 > 400 行需拆分并在 PR 说明;
3. 错误建模为显式 enum(`SSHError`、`AgentError` 等),用户可读的 `LocalizedError` 文案;
4. 日志统一 `os.Logger`,含密钥/主机地址/命令内容的字段必须标 `privacy: .private`;
5. 命名、注释语言:代码与标识符英文;面向用户的文案走 String Catalog,首发 zh-Hans + en 双语。

### 6.3 数据规范
1. 秘密(密码、私钥、passphrase、AI API Key)**只进 Keychain**,`ThisDeviceOnly` 防备份迁移;SwiftData 与日志中出现即违规;
2. SwiftData 模型变更必须写 schema 迁移,禁止破坏性升级;
3. 审计日志 AES-GCM 加密落盘,密钥派生自用户生物识别门禁的授权链。

### 6.4 安全规范
1. 主机密钥校验不可跳过(开发调试例外须用编译 flag 且不出现在 Release);
2. AI 请求默认仅发送 4.6 定义的上下文,禁止附带凭据、主机原始地址(用别名替代)与历史命令中的明文密码;
3. 依赖锁定精确版本;新增第三方依赖必须满足:开源许可证兼容(MIT/Apache/BSD)、GitHub 活跃、无分析 SDK,并在 PR 中列出理由;
4. Release 构建关闭一切 debug 接口;隐私清单(PrivacyInfo.xcprivacy)如实申报。

### 6.5 测试与验收纪律(借鉴 MaidKit 的 Validation 一节)
1. 每阶段退出前必须全绿:
   ```sh
   swiftlint && swiftformat --lint .
   xcodebuild test -scheme GlazeVerre -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
   ```
2. 单测底线:`CoreSSH` 连接管理/known-hosts/重连逻辑、`AIAgent` 审批策略/危险命令分类器/工具回路(fake provider 注入)、`Persistence` 秘密隔离断言,**行覆盖 ≥ 60%**;
3. UI 层为关键流程(新建主机→连接→执行命令→AI 审批放行)编写自动化冒烟;
4. 真机自测清单随阶段交付(开发者自填):弱网重连、后台切换、Face ID 门禁、深浅色。

### 6.6 文档与 Git 规范
1. `docs/` 四份文档随代码同步演进;**结构性变更先改文档再改代码**;
2. Conventional Commits;main 分支保护;一个阶段一个 PR(或按功能拆分),PR 描述含:改动摘要、自测记录、规范核对项;
3. 每阶段结束在 `docs/CHANGELOG-phase.md` 追加:交付物清单、验收结果、遗留风险。

---

## 7. 开发计划(7 个阶段;单人全职约 14–16 周,AI 辅助开发可压缩,但阶段顺序与退出标准不可跳过)

### P0 脚手架与设计系统(约 1.5 周)
**目标**:工程骨架立起来,玻璃组件库可用。
- 交付:Xcode 工程 + 5 个 SPM 本地包 + 依赖锁定;`GlassKit` 完成颜色/字体/间距令牌、`GlassCard`、`GlassBar`、`GlassButton`、审批卡基础组件;根 Tab 框架(服务器/终端/AI/设置)空页跑通;CI(xcodebuild + lint)。
- **退出标准**:iPhone 16 Pro 模拟器安装运行;深浅色切换正常;Swift 6 并发零警告;lint/test 全绿;`docs/ARCHITECTURE.md` 成稿。

### P1 SSH 引擎与主机管理(约 2.5 周)
**目标**:能安全地连上服务器并执行命令(暂用简易 exec 调试页)。
- 交付:`CoreSSH`(连接/认证/known-hosts/重连/keepalive/exec/PTY)、Keychain 封装、主机 CRUD + 列表 UI、指纹确认页;单测覆盖连接与重连逻辑。
- **退出标准**:对真实 Linux 主机(密码与密钥两种认证)连接稳定 30 分钟不掉线;主机密钥变更被阻断并有告警;秘密仅存 Keychain(代码审计确认);冒烟测试通过。

### P2 终端体验(约 2.5 周)
**目标**:好用的手机终端,本项目第一体验门槛。
- 交付:`TerminalKit`(SwiftTerm 封装)、扩展键盘条(含自定义布局)、字体/字号/主题设置、多会话标签页、复制粘贴与 IME 验证、tmux 检测提示。
- **退出标准**:vim/htop/top 渲染正常无花屏;中文输入法组合输入正确;10000 行滚动不卡顿( Instruments 无明显掉帧);扩展键盘在 Gmail 等第三方键盘场景不遮挡。

### P3 SFTP 与运维工具(约 2 周)
**目标**:从「能进终端」到「能管理服务器」。
- 交付:SFTP 浏览器(上传/下载/删除/重命名/移动)、内置文本编辑器、命令片段库(创建/执行/流式输出)、端口转发(L/R,UI + 生命周期管理)、跳板机连接。
- **退出标准**:10MB 文件往返无损;编辑保存写回成功;片段在多会话执行输出不串流;隧道断开自动重建。

### P4 自定义 AI 接入(约 1.5 周)
**目标**:对话可用,三协议全通。
- 交付:提供商配置 UI、三协议适配器(OpenAI 兼容/Anthropic/Gemini,含流式)、模型发现、对话 UI(Markdown/代码块)、会话持久化、「将发送的内容」预览面板。
- **退出标准**:三种协议各接一个真实端点流式对话成功;切换主机上下文后系统提示词正确;API Key 仅存 Keychain;断流重试不重复计费请求(幂等处理)。

### P5 AI 接管 Agent(约 2.5 周,安全重点)
**目标**:模型可提案、审批可执行、风险有底线。
- 交付:工具注册与 JSON Schema、Agent 循环(actor 隔离)、三种审批策略、危险命令分类器、审批卡与编辑后批准、kill switch、审计日志、Agent/终端双视图联动(把 Agent 执行回显到可选的终端环形缓冲)。
- **退出标准**:fake provider 单测覆盖 全部策略分支 + 分类器词表 ≥ 40 条;真机演示「让 AI 查磁盘占用并清理临时文件」全程经审批完成;kill switch 在命令执行中 ≤ 1s 生效;审计日志完整记录;**无任何策略组合可绕过危险命令人工确认**(专项测试证明)。

### P6 安全打磨与发布(约 1.5 周)
**目标**:可上 TestFlight 的完成度。
- 交付:Face ID 门禁、屏幕共享防护、错误日志导出、隐私清单、图标(含 iOS 26 清晰玻璃变体)、zh-Hans/en 文案全覆盖、无障碍审查(Dynamic Type + VoiceOver 主要路径)、性能 passes、TestFlight 构建。
- **退出标准**:验收清单(第 8 节)全项通过;TestFlight 内测包发出。

---

## 8. 最终验收清单(逐项勾选,不得自评跳过)

- [ ] 新建主机 → 首连确认指纹 → 进入终端 → 执行命令 → 断网 30s 内重连,全流程顺滑;
- [ ] 终端:vim 编辑中文文档、Ctrl+C 中断、复制粘贴、第三方键盘切换,均正常;
- [ ] SFTP:上传下载编辑各一次,进度与取消可用;
- [ ] 自定义接入:三种协议 + 自定义 BaseURL 均可对话,Key 不出 Keychain;
- [ ] AI 接管:只读模式下 AI 无法执行写命令;`alwaysAsk` 下每次执行都有审批卡;危险命令在任何策略下都被拦截;kill switch 有效;审计可导出;
- [ ] 深浅色两套截图(服务器列表/终端/审批卡/设置)通过设计规范 5.3 对比度检查;
- [ ] 全部第 6 节验证命令绿;文档四件套与代码同步;
- [ ] 代码中 grep 不到任何秘密写入 SwiftData/日志/UserDefaults 的痕迹。

---

## 9. 工作方式要求

1. **按阶段推进**:每阶段结束输出「演示 + 自测记录 + 遗留风险」,达标后再进入下一阶段;禁止把 P5 的安全逻辑留到「以后补」。
2. **歧义决策顺序**:本文档规范 > 参考项目 MaidKit 的既有设计 > 通用最佳实践;每次依据该顺序做出的裁量,以一行 ADR(架构决策记录)写入 `docs/ARCHITECTURE.md` 附录。
3. **不得擅自扩大范围**:发现「顺手可以做」的增强功能,一律记入 backlog 汇报,不实现。
4. **透明汇报**:被阻塞超过半天必须汇报阻塞点与已尝试方案,不静默绕过。
5. 涉及真实服务器的开发测试,只允许使用开发方自有测试主机;禁止对任何未授权主机发起连接。

---

*规范版本 v1.0(2026-08-30)。本文档本身纳入 Git 管理;修订需留版本记录。*
