# Termura

> Terminal UX, redesigned. Editor-grade input · Structured output · Knowledge persistence

A native macOS terminal built for power users of AI coding tools (Claude Code, Codex, Aider, etc.). No login required. Lightweight. Open Core.

[中文版](#termura-中文)

---

## Why Termura

Traditional terminals dump thousands of lines of unstructured text. AI coding tools make this worse — massive diffs, long explanations, streaming output. Termura fixes this with three pillars:

- **Editor-grade Input** — TextKit 2 powered composer with click-to-position cursor, multi-line editing, word-level navigation, and syntax highlighting
- **Structured Output** — Command output rendered as collapsible, independently scrollable blocks with one-click copy, exit code display, and execution metadata
- **Knowledge Persistence** — Sessions auto-saved with full-text search, integrated Markdown notes, token usage tracking, and session export

## Features

### Terminal & Sessions

- GPU-accelerated terminal rendering via [libghostty](https://github.com/ghostty-org/ghostty) (Metal)
- Multi-session management with sidebar navigation
- Session persistence across app restarts (GRDB/SQLite)
- Session branching — create alternative exploration branches, merge back with summaries
- Session export to HTML or JSON
- Full-text search (FTS5) across sessions and notes
- Visor mode (global hotkey drop-down terminal)

### Dual-Pane Mode

- Side-by-side terminals for parallel operations
- Independent scrolling per pane
- Drag sessions between panes
- Focus indicator with blue accent line

### AI Agent Integration

- Auto-detects running AI agents: Claude Code, Codex, Aider, OpenCode, Gemini, Pi
- Real-time agent status tracking (idle, thinking, tool execution, waiting, error, completed)
- Token counting and cost estimation parsed from agent output
- Context window monitoring with visual progress bar
- Risk detection — alerts for high-risk agent operations (file deletion, destructive commands)
- Agent resume support with pre-filled launch commands

### Editor-grade Composer

- NSTextView/TextKit 2 powered input field
- Click-to-position cursor, multi-line editing
- Word-level navigation and selection
- Input history (Cmd+Up/Down)
- File attachments for AI agent context
- Auto-save of unsent text

### Tabs & Content Types

- Terminal tabs, split tabs, note tabs, file tabs, diff tabs, preview tabs
- Tab persistence across restarts
- Double-click to rename

### Sidebar

- **Sessions** — session list, inline rename, context menu, agent status badges
- **Agents** — multi-agent dashboard across all sessions, "needs attention" highlighting
- **Notes** — markdown notes list with search
- **Project** — file tree with git integration, branch/commit display, changed file stats, staged/unstaged toggle, problems panel

### Markdown Notes

- Capture terminal output to notes
- Full markdown editor in tabs
- Auto-save with debounce
- Full-text search integration

### Project Integration

- Git status: branch, commit hash, ahead/behind, remote host detection
- File tree with git status icons
- Staged vs working tree diffs
- File editing with syntax highlighting (120+ languages via Highlightr)
- QuickLook preview for images, PDFs, Office documents
- Problems/diagnostics panel

### Shell Integration

- OSC 133 protocol for structured output (prompt, command, execution, exit code markers)
- One-click shell hook installation (bash, zsh)

### Appearance

- Theme system with design tokens
- Multiple bundled themes with import support
- Font customization (family + size)
- Dark mode support

### Privacy

- Zero telemetry, zero login, fully offline
- All data stored locally in `~/.termura/`
- No network transmission of user data

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI + AppKit |
| Terminal | [libghostty](https://github.com/ghostty-org/ghostty) (Metal GPU rendering) |
| Syntax Highlighting | [Highlightr](https://github.com/raspu/Highlightr) |
| Database | [GRDB](https://github.com/groue/GRDB.swift) (SQLite + FTS5) |
| Shortcuts | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| Collections | [Swift Collections](https://github.com/apple/swift-collections) |
| Build | XcodeGen + Swift 6.0 |

## Getting Started

### Requirements

- macOS 14.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme Termura -configuration Debug build
```

### Development

```bash
# Lint
swiftlint lint --strict

# Format
swiftformat Sources/ --verbose
```

## Roadmap

Phase 1-3 (terminal core, shell integration, editor input, output chunking, notes, search) — done.

Phase 4 (dual-pane, agent dashboard, session branching, project integration) — in progress.

Next up: plugin system, custom workflows, advanced session analytics.

## Contributing

Contributions are welcome! Please read the project guidelines before submitting a PR.

## License

[Apache License 2.0](LICENSE) — see [LICENSE](LICENSE) for details.

---

<a id="termura-中文"></a>

# Termura (中文)

> 重新设计终端体验。编辑器级输入 · 结构化输出 · 知识持久化

一款为 AI 编程工具（Claude Code、Codex、Aider 等）深度用户打造的原生 macOS 终端。无需登录，轻量级，Open Core 开源。

## 为什么选择 Termura

传统终端将数千行非结构化文本一股脑倾泻到屏幕上。AI 编程工具让这个问题更加严重 — 大量 diff、冗长解释、流式输出。Termura 通过三大核心理念解决这一问题：

- **编辑器级输入** — 基于 TextKit 2 的输入组件，支持点击定位光标、多行编辑、词级导航和语法高亮
- **结构化输出** — 命令输出以可折叠、独立滚动的卡片呈现，支持一键复制、退出码显示和执行元数据
- **知识持久化** — 会话自动保存，支持全文搜索、集成 Markdown 笔记、Token 用量追踪和会话导出

## 功能特性

### 终端与会话管理

- 基于 [libghostty](https://github.com/ghostty-org/ghostty) 的 GPU 加速终端渲染（Metal）
- 侧边栏多会话管理
- 会话跨重启持久化（GRDB/SQLite）
- 会话分支 — 从任意节点创建探索分支，完成后可合并回主线
- 会话导出为 HTML 或 JSON
- 全文搜索（FTS5），覆盖会话和笔记
- Visor 模式（全局快捷键下拉终端）

### 双面板模式

- 并排终端，适用于并行操作
- 各面板独立滚动
- 拖拽会话到不同面板
- 蓝色高亮指示当前聚焦面板

### AI Agent 集成

- 自动检测运行中的 AI Agent：Claude Code、Codex、Aider、OpenCode、Gemini、Pi
- 实时 Agent 状态追踪（空闲、思考中、工具执行、等待输入、错误、已完成）
- 从 Agent 输出中解析 Token 计数和费用估算
- 上下文窗口监控，带可视化进度条
- 风险检测 — 对高风险 Agent 操作（文件删除、破坏性命令）发出警告
- Agent 恢复支持，预填充启动命令

### 编辑器级输入组件

- 基于 NSTextView/TextKit 2 的输入区域
- 点击定位光标、多行编辑
- 词级导航和选择
- 输入历史（Cmd+Up/Down）
- 文件附件，为 AI Agent 提供上下文
- 未发送文本自动保存

### 标签页与内容类型

- 终端标签、分屏标签、笔记标签、文件标签、Diff 标签、预览标签
- 标签页跨重启持久化
- 双击标签标题可重命名

### 侧边栏

- **会话** — 会话列表、内联重命名、右键菜单、Agent 状态徽章
- **Agents** — 跨所有会话的多 Agent 仪表盘，"需要关注"高亮提示
- **笔记** — Markdown 笔记列表，支持搜索
- **项目** — 文件树（含 Git 集成）、分支/提交显示、变更文件统计、暂存区/工作区切换、问题面板

### Markdown 笔记

- 捕获终端输出到笔记
- 标签页内完整 Markdown 编辑器
- 自动保存（带防抖）
- 全文搜索集成

### 项目集成

- Git 状态：分支名、提交哈希、领先/落后提交数、远程仓库检测
- 带 Git 状态图标的文件树
- 暂存区 vs 工作区 Diff 查看
- 文件编辑，支持语法高亮（Highlightr 支持 120+ 语言）
- QuickLook 预览图片、PDF、Office 文档
- 问题/诊断面板

### Shell 集成

- OSC 133 协议实现结构化输出（提示符、命令、执行、退出码标记）
- 一键安装 Shell Hook（bash、zsh）

### 外观

- 设计令牌系统的主题引擎
- 多套内置主题，支持导入自定义主题
- 字体自定义（字体族 + 字号）
- 深色模式支持

### 隐私

- 零遥测、零登录、完全离线
- 所有数据本地存储于 `~/.termura/`
- 不进行任何用户数据的网络传输

## 技术栈

| 组件 | 技术 |
|------|------|
| UI | SwiftUI + AppKit |
| 终端 | [libghostty](https://github.com/ghostty-org/ghostty)（Metal GPU 渲染） |
| 语法高亮 | [Highlightr](https://github.com/raspu/Highlightr) |
| 数据库 | [GRDB](https://github.com/groue/GRDB.swift)（SQLite + FTS5） |
| 快捷键 | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| 集合类型 | [Swift Collections](https://github.com/apple/swift-collections) |
| 构建 | XcodeGen + Swift 6.0 |

## 快速开始

### 环境要求

- macOS 14.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### 构建

```bash
# 生成 Xcode 项目
xcodegen generate

# 构建
xcodebuild -scheme Termura -configuration Debug build
```

### 开发

```bash
# 代码检查
swiftlint lint --strict

# 代码格式化
swiftformat Sources/ --verbose
```

## 路线图

Phase 1-3（终端核心、Shell 集成、编辑器输入、输出分块、笔记、搜索）— 已完成。

Phase 4（双面板、Agent 仪表盘、会话分支、项目集成）— 进行中。

后续计划：插件系统、自定义工作流、高级会话分析。

## 贡献

欢迎贡献代码！提交 PR 前请阅读项目规范。

## 许可证

[Apache License 2.0](LICENSE) — 详见 [LICENSE](LICENSE)。
