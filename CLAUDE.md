# Termura — Claude Code 主上下文

> 终端的交互体验，重新设计。编辑器级输入 · 智能输出 · 知识持久化

---

## 产品概述

**Termura** 是一款 macOS 原生终端应用，目标用户为 AI 编程工具（Claude Code、Codex、Aider 等）的重度使用者。核心差异：无需登录、原生轻量、Open Core。

**三大支柱**：
1. **编辑器级输入**：NSTextView/TextKit 2，鼠标点击定位、多行编辑、词级导航、语法高亮
2. **智能输出分块**：结构化渲染代替文本洪流，独立滚动、一键复制、可折叠
3. **知识持久化**：Session 自动保存/全文搜索、集成 Markdown 笔记、Token 监控

**技术栈**：SwiftUI + AppKit · macOS 14+ · SwiftTerm · GRDB · Highlightr · KeyboardShortcuts

---

## 开发路线图

| Phase | 周期 | 目标 |
|-------|------|------|
| **Phase 1** | Wk 1–3 | 基础终端、竖排侧边栏、多 Session、Visor 模式、基础主题 |
| **Phase 2** | Wk 4–6 | Shell Integration (OSC 133)、编辑器输入、输出分块、Token 监控 |
| **Phase 3** | Wk 7–9 | Markdown 笔记、Session 持久化/搜索、侧边栏增强 |
| **Phase 4** | Wk 10–12 | Session Timeline、可交互元素、后台监控、主题引擎 |

---

## 安全门禁

> **CRITICAL**: 所有代码变更必须严格遵守，违反直接拒收。

1. **日志脱敏**：Release 构建禁止 `print`/`NSLog`，必须使用 `OSLog`。DEBUG 禁止打印完整 Session 内容，仅打印摘要或 ID。
2. **零信任输入**：所有外部输入（Shell 输出、URL Scheme、文件导入）必须经过校验和 Sanitization。
3. **本地数据安全**：用户 Session 数据仅存储在本地 `~/.termura/`，严禁未经授权的网络传输。

---

## AI 代码质量门禁

> **生产级要求**：所有代码必须通过以下质量验证，优先级高于一切默认习惯。

### 1. 架构与依赖注入

- **严格 DI**：ViewModel/Service 必须通过 `init` 接收依赖。
  - ✅ `init(sessionRepository: SessionRepository)`
  - ⛔️ 内部直接调用 `AppServices.shared`
- **协议驱动**：所有外部依赖（Repository、Terminal Engine、Storage）必须抽象为 `Protocol`。
- **Clean Architecture**：View 层禁止直接访问 GRDB/SwiftTerm。必须通过 ViewModel → Service/Repository。
- **单例约束**：单例内的有状态依赖必须用 `let` + `init` 显式初始化，禁止 `lazy var`。

### 2. 代码安全与现代并发 (P0)

- **零强制解包**：绝对禁止 `!`（Force Unwrap/Try/Cast）。
  - ✅ `guard let`、`if let`、`?? default`
  - ⛔️ `value!`、`try!`、`as!`
- **结构化并发**：全面使用 `async/await`。
  - ⛔️ 禁止 `DispatchQueue.main.async` / `asyncAfter` → 使用 `Task { @MainActor in ... }`
  - ⛔️ 禁止 `DispatchQueue.global()` → 使用 `Task.detached`
  - ⚠️ Combine `.receive(on:)` 必须使用 `RunLoop.main`，不用 `DispatchQueue.main`

### 3. 性能铁律

- **主线程洁癖**：UI 操作仅在 `@MainActor` 上执行。GRDB 读写必须在后台执行。
- **Terminal 渲染**：SwiftTerm 回调处理必须非阻塞，复杂解析移至后台 Task。
- **原子化原则**：单函数 ≤ 50 行，单文件 ≤ 300 行（超出必须拆分）。
- **SLO 强制标准**：
  - **Launch**：< 2s (P95)
  - **Session Switch**：< 100ms
  - **Full-text Search**：< 200ms (P99)
  - **Terminal Input Latency**：< 16ms (1 frame)

### 4. 错误处理 (P0)

- **零吞错**：严禁空 `catch` 块，任何 `catch` 必须包含日志或 UI 反馈。
- **禁止 `try?`**：业务逻辑层（ViewModel/Repository/Service）禁止 `try?` 吞没异常。
- **显式传播**：优先 `throws` 显式抛出，禁用 `Optional` 代替可处理异常。

### 5. 资源管理 (P1)

- **内存安全**：闭包捕获 `self` 根据生命周期使用 `[weak self]` 或 `[unowned self]`。
- **Terminal 缓冲**：Session 终端缓冲区必须有上限（默认 10000 行），防止内存泄漏。
- **GRDB 连接**：数据库连接池由 `DatabaseService` 统一管理，禁止多处独立创建连接。
- **临时清理**：文件导出产生的临时文件必须用 `defer` 确保清理。

### 6. 并发审查清单

提交前必须自查：
- [ ] 无 `DispatchQueue.main` / `DispatchQueue.global`？
- [ ] 修改 UI 状态的方法已标记 `@MainActor`？
- [ ] 延迟使用 `Task.sleep` 而非 `asyncAfter`？
- [ ] Combine 的 `.receive(on:)` 使用 `RunLoop.main`？
- [ ] 跨 Task 传输数据是 `Sendable` 类型？
- [ ] 长时间任务能响应 `Task.isCancelled`？

### 7. 配置管理 (P0)

- **零魔法数字**：所有全局配置（缓冲行数、超时时间、限制值）必须定义在 `AppConfig.swift`。
- **延迟常量化**：`Task.sleep` 必须使用 `AppConfig.Runtime` 中的命名常量。

### 8. 可测试性 (P1)

- **Mock 友好**：关键 Repository/Service 必须提供 `Mock` 实现。
- **时间解耦**：时间敏感逻辑注入 `Clock` 协议，禁止直接使用系统时间。
- **测试隔离**：单元测试禁止依赖真实文件系统或 SwiftTerm 实例。

---

## 模块架构

```
Sources/Termura/
├── App/           # TermuraApp, AppCommands, AppConfig
├── Views/         # SwiftUI Views (只负责布局和交互绑定)
├── Terminal/      # SwiftTerm 集成、PTY 管理、ANSI 解析
├── Input/         # NSTextView/TextKit2 编辑器输入区
├── Output/        # 输出分块检测与渲染
├── Session/       # Session 状态管理
├── Notes/         # Markdown 笔记（分屏编辑、捕获）
├── Theme/         # 主题 Token 系统
└── Services/      # GRDB 持久化、搜索、Shell Integration
```

**数据流**：`View → ViewModel → Service/Repository → GRDB / SwiftTerm / FileSystem`

**Shell Integration**：使用 OSC 133 协议（与 iTerm2/Warp 相同）在 `.zshrc`/`.bashrc` 注入轻量 hook，检测提示符/命令/退出码边界。

---

## 开发工作流

```bash
# 生成 Xcode 项目（修改 project.yml 后执行）
xcodegen generate

# 代码质量检查
swiftlint lint --strict

# 代码格式化
swiftformat Sources/ --verbose

# 构建验证
xcodebuild -scheme Termura -configuration Debug build

# 查看应用日志
log stream --predicate 'process == "Termura"'
```

---

## Git 工作流

```bash
# 功能分支
git checkout -b feature/phase1-swiftterm-integration

# 提交规范
feat(terminal): integrate SwiftTerm with basic ANSI support
fix(input): correct cursor positioning on click
perf(session): move GRDB reads off main thread
docs(claude): update architecture notes
```

### 提交检查清单
- [ ] 编译通过，零警告
- [ ] `swiftlint lint --strict` 无 error
- [ ] 核心逻辑变更附有单元测试
- [ ] 相关文档已更新

---

## 快捷键规划

| 快捷键 | 功能 |
|--------|------|
| `Cmd+T` | 新建 Session |
| `Cmd+W` | 关闭 Session |
| `Cmd+[1-9]` | 切换到第 N 个 Session |
| `Shift+Enter` | 输入区换行（多行模式） |
| `Enter` / `Cmd+Enter` | 提交命令 |
| `Cmd+Shift+F` | 跨 Session 全文搜索 |
| `Cmd+Shift+N` | 新建 Markdown 笔记 |
| `Option+S` | 切换侧边栏 |
| `` Cmd+` `` | Visor 模式全局唤起 |

---

**最后更新**：2026-03-13 · Phase 1 开发中
