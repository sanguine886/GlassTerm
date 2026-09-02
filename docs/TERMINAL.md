# GlazeVerre 终端设计

> 与代码同步演进。对应规范 §4.3（CLI 终端适配，P0 第一体验门槛在 P2 兑现）。

## 1. 终端内核

- SwiftTerm（版本锁定，升级须全量终端回归）：ANSI 全集 / truecolor、bracketed paste、
  鼠标上报、CJK IME、滚动缓冲 ≥ 10000 行；
- PTY 会话 `xterm-256color`；UTF-8 全链路。

## 2. 手机优先交互（P2）

- 常驻扩展键盘条（输入附件视图）：Esc / Tab / Ctrl 组合 / 方向 / Home / End /
  管道 / 波浪 / 常用符号，长按变体，布局可编辑；
- 多会话标签页（玻璃材质，左滑关闭）；断开/崩溃状态标记；
- 第三方键盘场景不遮挡（退出标准之一）。

## 3. 外观

- 内置 ≥ 2 款等宽字体；字号 8–32pt；≥ 5 套配色主题（浅色/深色/Solarized/Dracula/Glass）；
- 终端区域永不被玻璃覆盖（规范 §5.1 红线）；玻璃光晕仅表达 Agent 工作状态（§5.2）。

## 4. 退出标准（P2）

vim/htop/top 无花屏；中文组合输入正确；10000 行滚动不卡顿
（CI 以 `XCTHitchMetric` 断言，真机复核）；tmux 会话检测提示 attach。

## 当前状态（P0）

`TerminalKit` 为模块骨架；SwiftTerm 依赖与全部终端能力随 P2 落地（ADR-0002）。
