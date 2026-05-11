# Termura Engineering Policy

本文件是 Termura 的项目级工程约束。目标不是帮助 AI 更快生成代码，而是从一开始就避免把项目推向“能用但难以维护”的中等质量区间。

规则分两类：
- `P0`: 违反即拒收
- `P1`: 默认必须遵守，只有明确说明例外时才允许偏离

历史代码中已存在一部分技术债。新改动不得扩大这些债务；凡触及相关区域，优先顺手收敛。

## 1. Primary Goal

优先级固定如下：
1. 架构边界清晰
2. 生命周期正确
3. 并发可证明安全
4. 可测试
5. 可观测
6. 功能完成

“先做出来以后再整理”不是默认策略。

## 2. Required Workflow

每次开始实现前，必须先明确这 5 件事：
1. 模块边界
2. 状态归属
3. 副作用归属
4. 取消 / 退出 / 恢复路径
5. 测试计划

如果这 5 项说不清，不允许直接写实现。

## 3. Architecture Rules

### 3.1 Layering (P0)

- `View` 只负责渲染、交互绑定、轻量事件分发。
- `ViewModel / Store` 负责可观察状态与编排，不直接承担底层持久化和平台资源访问。
- `Service / Repository / Adapter` 负责副作用。
- `Composition Root` 只装配依赖，不承载业务逻辑、迁移策略、恢复策略、退出策略。

禁止方向：
- `Views -> GRDB / FileManager / UserDefaults / NSApp / Process`
- `Session / Input / Output` 直接依赖具体 `Services` 类型
- `Repository` 返回语义不一致的实体

### 3.2 Dependency Injection (P0)

以下能力必须可注入，禁止在业务逻辑中直接使用全局单例：
- clock / time
- file system
- persistence
- notifications
- app state
- external process
- environment
- clipboard / system bridge

典型禁止项：
- `UserDefaults.standard`
- `FileManager.default`
- `NotificationCenter.default`
- `Date()`
- `NSApp`
- `ProcessInfo.processInfo`

允许例外：
- 值类型默认参数中的 `Date()`
- 平台 adapter / bridge / app lifecycle 层
- 必须在 code review 中说明原因

### 3.3 Optional Runtime Dependencies (P0)

运行时必须存在的依赖，禁止声明为 Optional 后静默跳过：

- `init(repository: any SessionRepositoryProtocol)`：允许
- `init(repository: (any SessionRepositoryProtocol)? = nil)`：禁止
- `guard let repo else { return }`：对核心依赖禁止

`Optional` 依赖只允许两类：
- observability / diagnostics
- feature gate / open-core capability

必须在参数行内联说明原因。

### 3.4 Test Doubles (P1)

新写的 `Mock*` 不应进入 `Sources/Termura/`。应放入：
- `Tests/...`
- `TestingSupport` 模块

迁移期约束：
- 历史遗留 `Mock*` 若仍在 `Sources/Termura/`，必须包在 `#if DEBUG`
- 新增代码不得继续扩大该模式

### 3.5 Modularization (P1)

主 target `Sources/Termura/` 已超过 3 万行，应持续向独立模块收敛：

- 新增领域逻辑优先放入独立 Swift Package target（如 `TermuraNotesKit`），主 target 仅保留 View 层和组装层。
- 已有领域若逻辑自洽（模型 + Service + Repository 形成闭环），触及时应评估是否可拆出。
- 独立模块不得反向依赖 `Termura` 主 target；跨模块通信通过协议注入。
- 拆分粒度以"可独立编译、可独立测试"为判据，不以文件数为目标。
- 纯 UI 组件（仅渲染、无领域状态）可留在主 target，不强制拆分。

### 3.6 Mirrored Remote State Freshness (P1)

任何 UI 可观察的、镜像了远端 peer 状态的属性（典型场景：iOS 端镜像 Mac 端的 session 列表、Mac 端镜像 iOS 端的 paired 设备等），必须满足以下两条**至少之一**：

1. **Push-on-change subscription**：远端状态发生变化时主动推送到本端，本端在 `inbox` / receive handler 中更新本地镜像。推送必须从可观察的真实状态源（`@Observable` / `Combine` / 可枚举 mutation 点）发起，而不是定时轮询。
2. **Explicit lifecycle re-request**：在能体现"用户重新关注"的 UI 生命周期事件上重新拉取（如 SwiftUI `scenePhase == .active`、`onAppear`、应用回前台、重连完成）。

**禁止**仅在初次配对 / 重连各拉一次后就再无更新机制（pull-once-on-pair 反模式）。

**Why**：曾出现 iOS 端 `RemoteStore.sessions` 仅在 pair 完成与 reconnect 时各请求一次，配对后 Mac 上新开 / 关闭的 session 在 iOS 上完全不可见的 bug。Mac 推送 + iOS scenePhase 兜底是当前的标准修法。

**How to apply**：
- Code review 时，凡新增 iOS / cross-device UI 可观察属性，确认其有 push 订阅或 lifecycle 钩子。
- 缺少两者者拒收，或要求作者在 PR 描述里说明该属性"本质上不会跨连接变化"的原因。
- 配套要求：每项跨设备镜像态都应有"Mac 侧变 → iOS 在 N ms 内观察到"的回归测试（contract test，§8.3）。

## 4. Concurrency And Lifecycle

### 4.1 Structured Concurrency First (P0)

- 默认使用结构化并发
- 禁止无解释地使用 `Task.detached`
- 禁止 `DispatchQueue.main.async` / `DispatchQueue.global`
- 延迟统一使用 `Task.sleep`

### 4.2 Ownership Of Background Work (P0)

任何后台任务都必须回答：
1. 谁创建它
2. 谁拥有它
3. 谁取消它
4. 谁在退出 / 销毁 / flush 时等待它完成

凡出现以下能力，必须能说清所有权：
- `Task.detached`
- `Process()`
- `AsyncStream`
- `NotificationCenter` observer
- `Timer`

推荐在相关代码附近加固定标签：
- `WHY:`
- `OWNER:`
- `TEARDOWN:`
- `TEST:`

### 4.3 Shutdown / Close / Restore (P0)

所有有生命周期的对象必须具备对称路径：
- create / open / start / register
- close / stop / unregister / flush

要求：
- 应用退出不能依赖“希望任务自己结束”
- 超时逻辑必须真的中断等待链，而不是表面 race
- close / terminate 路径必须有测试

### 4.4 Actor Isolation (P0)

- 只有持有 UI 可观察状态的类型才应标注 `@MainActor`
- Service / Repository / Parser / Detector 默认不用 `@MainActor`
- `nonisolated(unsafe)` 只允许用于 `deinit` 访问模式
- 禁止用 `nonisolated(unsafe)` 存储回调闭包

### 4.5 `@unchecked Sendable` 使用政策 (P0)

`@unchecked Sendable` 只允许在以下两类语境使用，并必须在声明处上方紧邻位置有解释线程安全机制的注释（≥1 行，说明可变状态的同步策略）：

1. **NSXPCConnection 桥接类**：`final class T: NSObject, @objc protocol P, @unchecked Sendable`。NSXPCConnection 要求 `@objc` 协议实现派生 NSObject，NSObject 不是 Sendable，因此 `@unchecked Sendable` 是 Apple 官方模式，无替代。
2. **不可避免的桥接 wrapper**：仅在 ObjC reply block / NSXPCConnection / 类似边界处包装一个 immutable 字段以承认编译器无法穿透的 ABI 不变性时使用。

**禁止**用 `@unchecked Sendable` 替代以下场景：
- 存非 `@Sendable` 闭包的简单 struct（应改用 `let f: @Sendable () -> X`）
- weak 引用的 wrapper（应改用 `let getter: @Sendable () -> X?` 闭包弱捕获）
- 任何**纯 Swift**类型的"我懒得想清楚"绕过

code review 要求：
- 凡新增 `@unchecked Sendable` 必须在 PR 描述说明属于上述 1/2 中哪一类
- 上方没有线程安全注释 → 拒收
- 不属于 1/2 → 拒收，要求重构

### 4.6 `@preconcurrency import` 使用政策 (P0)

`@preconcurrency import M` 是 Swift 6 提供的过渡机制——对未完成 Sendable 注解的模块，它在 import 边界放宽 strict-concurrency 检查。**只允许**用于以下两类 import：

1. **Objective-C 互操作模块**：`@preconcurrency import TermuraAgentXPCInterfaces`（NSXPC 协议头、ObjC class 头）。Apple 没有为所有 ObjC 类型标注 Sendable，且 ObjC 没有 Sendable 概念；`@preconcurrency` 是 Apple 官方推荐的 ObjC interop 方式。
2. **未升级到 Swift 6 的第三方模块**：仅在该模块尚未发布 Swift 6 兼容版本时短期使用，**必须在导入行同行添加 `// TODO: drop @preconcurrency once <module> ships Swift 6` 注释，否则拒收**。

**禁止**：
- 在 Swift 模块上使用 `@preconcurrency`（应升级该模块的 Sendable 注解）
- 用 `@preconcurrency` 替代单点 `@unchecked Sendable`（粒度更粗）
- 用于符号声明（`@preconcurrency func foo()` 等），仅限 import 行

code review 要求：
- 凡新增 `@preconcurrency import` 必须在 PR 描述说明属于上述 1/2 中哪一类
- 第 2 类必须有"何时撤销"的同行 TODO 注释，否则拒收

### 4.7 `nonisolated(unsafe)` 例外语境 (P0)

§4.4 已限定 `nonisolated(unsafe)` 只允许 `deinit` 模式。补充例外：

3. **C 函数指针 / 信号处理器**：`@convention(c)` callback 无法捕获 actor 状态，必须从全局静态变量读取 actor 实例。例如 SIGTERM/SIGINT handler 通过 `nonisolated(unsafe) static var shared: AgentLifecycle?` 访问 lifecycle。**必须在声明处上方紧邻位置加注释**说明属于此类。

code review 要求：
- 上方没有"signal-handler"/"@convention(c)"或类似 marker → 拒收
- 即使是该例外，存储仍必须是 immutable-after-init（init 写一次，handler 只读）

## 5. Error Handling And Logging

### 5.1 Error Policy (P0)

- 禁止空 `catch`
- 业务逻辑层禁止 `try?`
- 错误优先 `throws` 显式传播
- log-only catch 必须说明是 `Non-critical`

### 5.2 Logging Policy (P1)

- Release 禁止 `print` / `NSLog`
- 统一使用 `OSLog`
- 热路径禁止逐事件 `logger.info`
- `fault` 只用于真正不可恢复状态；若后续继续执行，使用 `error` 或 `warning`

### 5.3 Security And Input Handling (P0)

- 外部输入默认零信任
- Shell 输出、导入文件、URL、外部进程输出必须校验和清洗
- 本地数据未经明确授权不得网络传输

### 5.4 Error Surfacing (P0)

任何**自定义 Swift error 类型**（命名以 `Error` 结尾的 `enum` / `struct`），凡有可能流向 UI（SwiftUI `Text`、`Alert`、绑定到 `@Observable` / `@State` 的字符串字段，或写入 `lastError` / `errorMessage` 类管线），都**必须**符合 `LocalizedError`，并提供有意义的 `errorDescription`。

**Why**：曾出现一次远端控制开关报错 `"The operation couldn't be completed. (TermuraRemoteProtocol.CloudKitSubscriptionError error 0.)"`——`CloudKitSubscriptionError` 携带的 CKError reason 完全被 Foundation 的默认 `localizedDescription`（fallback 渲染为 `"<Module>.<Type> error N."`）盖住，用户只看到一串无法行动的字符串。任何 `enum X: Error` 不conform `LocalizedError` 都会触发这种回退。

**How to apply**：
- 直接 `enum X: Error, LocalizedError` 或同文件 `extension X: LocalizedError { var errorDescription: String? }`。
- 即便错误目前看起来"只在内部流转"，也要补上——后续接入 UI 表面只是一行 `errorMessage = error.localizedDescription` 的距离。
- 纯内部控制流且永远不会 surface 的极个别例外，必须在 `scripts/check-error-localization.sh` 的 `EXEMPT_ENUMS` 中显式加注释说明原因。
- Fast Gate 的 `check-error-localization.sh` 阻断新增违规：所有 `enum *Error: Error...` 必须能找到对应的 `LocalizedError` 装饰。

## 6. Code Size And Complexity

### 6.1 Size Budget (P1)

- 单函数目标：`<= 50` 行
- 单文件软上限：`250` 行
- 单文件硬上限：`360` 行

超出软上限不一定立刻拒收，但必须解释为何暂不拆。
超出硬上限默认拒收。

### 6.2 Big Configuration Buckets (P1)

禁止把配置长期堆进单一巨型 `AppConfig`。配置必须按领域拆分，并与模块一起演进。

### 6.3 Comments Do Not Replace Design (P1)

长注释通常意味着设计过重。若一段实现需要大段文字解释“为什么这么绕”，优先重构结构。

## 7. Performance Rules

### 7.1 Main Thread Hygiene (P0)

- UI 操作仅在 `@MainActor`
- 磁盘 I/O、DB、文件读取、外部进程等待不得阻塞主线程
- 高频路径中禁止重复 `subviews` 遍历、重复正则全量扫描、重复 O(n) 累积统计

### 7.2 SLO (P1)

- Launch P95: `< 2s`
- Session switch: `< 100ms`
- Full-text search P99: `< 200ms`
- Input latency: `< 16ms`

新增或修改关键性能路径时，应同步更新对应性能测试。

## 8. Testing Rules

### 8.1 Minimum Test Set (P1)

新功能默认至少包含：
- 1 个 happy path
- 1 个 error path
- 1 个 lifecycle / cancellation / restore path

### 8.2 High-Risk Changes Require Tests (P0)

只要改动涉及以下能力，必须补测试：
- persist
- restore
- timeout
- debounce
- single-flight
- background task
- teardown
- shutdown
- migration

### 8.3 Contract Tests (P1)

对关键 `Protocol`：
- 有真实实现
- 有 mock
- 有 contract test

目标是防止 mock 漂移，而不是只追求方便写单元测试。

## 9. Gate Alignment

规则必须尽量落到脚本，不依赖“大家记得”。

### 9.1 Fast Gate

- SwiftLint
- SwiftFormat
- suppressions check
- redundant imports
- bare `Date()`
- layer dependencies
- hardcoded AppKit strings
- forbidden Swift patterns

### 9.2 Design Gate

- file size budget
- lifecycle ownership advisory
- view-layer global access advisory
- legacy mock placement advisory

### 9.3 Full Gate

以下是 CI / 发布前应逐步补齐的完整门禁，不代表当前 `scripts/quality-gate.sh` 已全部执行：
- build
- unit test
- integration test
- contract test
- perf test

## 10. Legacy Migration Policy

当前仓库仍有几类历史债：
- `Sources/Termura/` 中存在 `Mock*`
- View / ViewModel 中仍有全局单例直连
- 个别大文件仍超出理想体积
- 个别退出 / flush 路径仍需继续收敛

处理原则：
- 不扩大
- 触及即清理
- 无法当场清理时，在 PR 中说明边界和偿还计划

## 11. Daily Commands

```bash
# 格式与静态检查
bash scripts/quality-gate.sh --staged

# 本地全量质量检查
bash scripts/quality-gate.sh

# 生成工程文件
xcodegen generate

# 构建
xcodebuild -scheme Termura -configuration Debug build

# 日志
log stream --predicate 'process == "Termura"'
```

## 12. Open-Core Boundary (P0)

公开 `termura` 仓与私有 `termura-remote` 仓边界已经从"Mac 也分公私"收窄为"只有 iOS 是私有"。任何新代码都按以下规则归属：

### 12.1 谁住公开 `termura/`

允许追踪：
- `Sources/Termura/**` 完整 Mac app 源，含 `Harness/`（CorruptionDetector / ExperienceCodifier / RuleFile* / HarnessViewModel + `Harness/Remote/` 全部 RemoteServerHarness / RemoteEnvelopeRouter / CloudKit gateways / PtyStream / AgentBridge / AgentXPC / Agent / Ingress 子树）
- `Sources/TermuraNotesKit/**`
- `Packages/TermuraRemoteKit/**` 共享 wire 库（Protocol + Server + Client transports）
- `Packages/AgentXPCInterfaces/**` ObjC clang module（XPC protocol surface + NSSecureCoding marshaling 类）
- `Packages/LaunchAgent/**` SPM executable `termura-remote-agent`（daemon helper）+ 它的测试 bundle
- `Resources/`、`Tests/`、`vendor/ghostty/` submodule
- `.swiftlint.yml`、`.swiftformat`、`project.yml.example`、`scripts/` 等可重现配置
- `CLAUDE.md`、`README.md`

**禁止**追踪：
- `project.yml`（per-machine 签名/路径，需 cp from `.example`）
- `Termura.xcworkspace/`（含 `../termura-remote/iOS/...` 引用）
- `*.xcodeproj/`（生成物）
- `.github/workflows/` 中除 `ci.yml` 外的私有流水线
- `docs/` 内部文档
- 任何 `iOS/` 目录或 iOS-specific 代码（iOS Remote app 是付费 IAP，仅住私仓）

### 12.2 谁住私有 `termura-remote/`

私仓只有 iOS Remote app + 必要的 iOS 构建配置：
- `iOS/`：完整 iOS app（TermuraRemote + TermuraRemoteTests + project-ios.yml + Versions.xcconfig）
- `README.md`、`CLAUDE.md`（iOS 专属纪律，如有）
- iOS-specific 的 `scripts/`（如有）

私仓 iOS app 通过 SPM `path: ../termura/Packages/TermuraRemoteKit` 引用公仓的 `TermuraRemoteProtocol` + `TermuraRemoteClient` product。**禁止**反向：私仓里不放公仓代码副本，也不混入开源协议层 / Mac 服务端实现。

### 12.3 字面量泄漏红线

任何**已追踪**到公开 `termura` 仓的文件中，禁止包含：
- 私仓相对路径片段：`../termura-remote/`、`termura-remote/`（防开发者本地脚本/笔记不小心 commit 把 sibling repo 路径写进 history）
- 真实 Apple Developer Team ID：`DEVELOPMENT_TEAM` 在 `project.yml.example` 必须写 `REPLACE_WITH_YOUR_TEAM_ID`

`scripts/pre-commit` 在 commit 前 grep staged 文件命中以上路径字面量；命中即拒绝。**LEAK_PATTERN 是 path-only by design**——开源边界收窄后再无 Mac 私实现 type 名要防。如有未来再次出现 sibling repo 跨仓 type 引用的需求，仍由 review 把守。

**禁止**扩展 LEAK_PATTERN 加入 type 名条目。任何 PR 试图扩展 pattern → review 应直接拒绝。

**5 文件级豁免**：`SELF_EXCLUDE_FILES` 列出的 5 个文件——4 个 scanner / cross-repo orchestrator 脚本（`scripts/pre-commit`、`scripts/regen-all.sh`、`scripts/quality-gate.sh`、`scripts/check-baseline-drift.sh`），以及 `CLAUDE.md` 自身（§12 文档边界必须点名 `termura-remote`）。它们物理上必须自包含被检测字符串才能履行各自职责。任何 PR 试图把第 6 个文件加入豁免 → review 应直接拒绝。

**Baseline 锁定**：`scripts/check-baseline-drift.sh` 在每次 commit 前由 hook 调用，强制三条不变量（LEAK_PATTERN 必须路径 only、SELF_EXCLUDE_FILES 必须恰好 5 项、WHITELIST_REGEX 不得重新引入）。

当前锁定的具体值由脚本本身打印，避免 CLAUDE.md 与实际 baseline 漂移：

```bash
bash scripts/check-baseline-drift.sh --print
```

任何想改这三条的 PR 必须先修 `scripts/check-baseline-drift.sh` 的预期值——这就把"扩张白名单"变成必须 reviewer 主动同意的显式动作。

### 12.4 操作纪律

- **绝不 `git add -f`** 跨过 `.gitignore` 强制提交 `Termura.xcworkspace/` 或 `project.yml`——这会把签名 / 私仓路径写进 git history。
- **新增公仓代码前**确认它能脱离 `../termura-remote/` 编译（cp `project.yml.example` → `project.yml` → `xcodegen generate` → Mac build）。后开源边界收窄后这是 trivially 成立——`scripts/check-open-core.sh` 仍保留作 regression guard，防止后续 build phase 不小心写入 sibling 路径。
- **新增私仓 iOS 代码前**确认其只依赖公仓 `Packages/TermuraRemoteKit` 的 Protocol + Client product 表面，不引用任何 Server-side 类型。

### 12.5 工程文件再生成纪律 (P0)

公仓 + 私仓 iOS 一共 **2 个 Xcode project**，每个由独立的 yml 通过 xcodegen 生成。两者的 `sources:` 互不重叠：公仓 project 只扫自己的 `Sources/` + `Packages/`；私仓 iOS project 只扫自己的 `iOS/TermuraRemote/`。

**新增 / 删除 / 重命名任何 `.swift` 文件后**，必须**重新生成相关的 pbxproj**。**绝不**直接调 `xcodegen generate -s ...`（容易漏一个 yml）；**永远用统一入口**：

```bash
bash scripts/regen-all.sh
```

该脚本顺序执行公仓 + 私仓 iOS 两个 xcodegen，私仓不存在时静默跳过（公仓单独 clone 友好）。

**防呆**：两个 yml 都注册了 `Verify pbxproj is fresh (xcodegen check)` pre-build phase，每次 ⌘B 之前调 `regen-all.sh --check` 验证 pbxproj 不落后于磁盘上的 .swift。一旦发现 pbxproj 漏文件 → build 失败 → 错误信息直接告诉你跑哪条命令。

## 13. Daily Commands

```bash
# 格式与静态检查
bash scripts/quality-gate.sh --staged

# 本地全量质量检查
bash scripts/quality-gate.sh

# 首次 clone：从模板生成 project.yml（替换团队 ID）
cp project.yml.example project.yml

# 重新生成所有 Xcode project（公仓 + 私仓 iOS，仅当 sibling 私仓存在时含后者）
# 同时会把 Xcode UI 里的 Version / Build 编辑反向同步进 Versions.xcconfig，
# 是版本号唯一的写入入口——不要直接改 yml 或 pbxproj。
bash scripts/regen-all.sh

# 仅检查 pbxproj 是否落后（pre-build phase 自动调用）
bash scripts/regen-all.sh --check

# Main currency audit — 分支状态 + 跨仓 wire 协调 (§15.6)
# 私仓需 export TERMURA_REMOTE_ROOT=<absolute path of private repo>
# （legacy TERMURA_HARNESS_ROOT 仍被识别但已 deprecated，请尽快迁移）
bash scripts/check-main-currency.sh             # advisory，列分支与漂移
bash scripts/check-main-currency.sh --strict    # stale 分支 / wire 漂移 → exit 1
bash scripts/check-main-currency.sh --no-wire   # 跳过跨仓 wire 扫描（秒级返回）

# 构建
xcodebuild -scheme Termura -configuration Debug build

# 日志
log stream --predicate 'process == "Termura"'
```

## 14. Review Checklist

提交前至少自查：
- [ ] 没有新增层级越权
- [ ] 没有新增全局单例直连到 UI / ViewModel
- [ ] 后台任务有 owner / cancel / flush 路径
- [ ] 退出 / 关闭路径不会卡死或静默丢数据
- [ ] repository 返回语义一致
- [ ] 新增高风险逻辑带测试
- [ ] 没有新增未受控的大文件 / 大类型
- [ ] 通过质量门禁
- [ ] **没有 open-core 边界泄漏**（pre-commit 扫描通过，私仓路径未进公仓追踪文件——type 名保护已不再需要，详见 §12.3）
- [ ] **在 feat 分支上提交**（不直接 commit / push 到 main，参见 §15.1；hook 已落地此保护）
- [ ] **未引入 main 漂移**（`bash scripts/check-main-currency.sh` 通过；该看一眼分支健康度，参见 §15.6）

## 15. Branching & Merge Policy

### 15.1 Never Commit Directly to main (P0)

`main` 是稳定基线，是 CI / submodule consumer / 其他分支起点的契约。所有改动必须走 feat 分支：

- 每件工作（feature / fix / refactor）从 main 起一条短命 feat 分支
- 命名约定：`feat/<theme>` / `fix/<scope>` / `refactor/<scope>` / `chore/<theme>`
- 在 feat 分支上累积 commit、跑 gate、push、必要时 review
- 完成后 ff-merge 进 main，再删 feat 分支（本地用 `git branch -d`，远端按 §15.5 走）
- main 在日常 `git status` 中只应短暂出现——merge 的那一刻

**禁止**：
- 在 main 上直接 `git commit` / `git commit --amend`
- 在 main 上 `git reset --hard` / `git rebase` / 任何修改历史的操作
- `git push --force` 到 main / `origin/main`（参见 §15.5）

### 15.2 Public + Private Repo Merge Coordination (P0)

公仓 `termura/` 与私仓 `termura-remote/` 是两个独立 git remote。私仓 iOS app 通过 sibling SPM path 依赖公仓 `Packages/TermuraRemoteKit` 的 Protocol + Client product。merge 时序：

- 涉及 wire API 变更（`TermuraRemoteProtocol` 公开类型 / 函数签名）时：**公仓 main 先合**或与私仓 main **同时合**——不允许私仓 main 引用公仓 main 还没合并的 wire API（私仓 iOS 编译断）。
- 不涉及 wire API 的公仓改动（Mac 服务端实现、harness 内部重构、UI、文档）：私仓不受影响，无需协调。
- push / merge / fetch 命令的 cwd 必须与目标 remote 一致——`git -C /absolute/path` 显式指明 path 比依赖 cwd 更安全。
- **绝不**跨仓 push（公仓内容 push 到私仓 remote 或反之）——pre-commit 的 LEAK_PATTERN 只防路径字面量，不拦跨仓 push 这种操作错误。

### 15.3 Merge Strategy: Fast-Forward Default (P1)

- **首选 fast-forward** (`git merge --ff-only`)：保留 atomic commit、保留 bisect 能力、与历史 commit 风格一致
- **squash 仅用于**：feat 分支上累积了大量 WIP / fixup commit 不值得保留 atomic 历史的情况；squash commit message body 必须列每个 squash 进来的逻辑单元
- **绝不**在 main 上 `rebase`：main 是 published 历史，rebase 会导致 force-push 等价行为，破坏其他分支基线

### 15.4 Branch Cleanup (P1)

合进 main 后：

- **本地** feat 分支：`git branch -d <feat>`（小写 d，未合并的分支会被拒绝，安全）
- **远端** feat 分支：保留无功能影响，删除让分支列表信号更干净；任何远端删除按 §15.5 走

### 15.5 Destructive Remote Operations Require Explicit Authorization (P0)

以下操作修改 GitHub 共享状态且不可立刻撤销，每次执行前必须有用户**明确授权**（不是泛泛的"好"/"ok"）：

- `git push origin --delete <branch>`
- `git push --force` / `--force-with-lease`（包括到 main / 任何 published 分支）
- 关闭 / 强制 merge GitHub PR
- 删除 GitHub release / tag 远端
- amend / reset 已 push 的 commit 后再 force push

**禁止**：把 reversible 的 local 操作（`git branch -d`、`git reset --soft`、editing files）和 destructive 的 remote 操作打包到同一条命令——必须分两步，第二步前显式确认。

Auto mode active 不豁免这条规则——auto mode 系统提示明确说"Auto mode is not a license to destroy"。

### 15.6 Main Currency: Audit + Merge Cadence (P1)

> 目的：让"main 是最新最全合并后的"成为可被脚本验证的不变量，而不是靠记忆。

**执行实际 merge / cherry-pick / ff-only 的动作永远是人为触发——脚本只负责拦截违规操作和报告漂移状态，不替你做合并决策。** §15.3 的策略选择（ff / no-ff / cherry-pick / squash）由人判断，§15.2 的跨仓顺序由人判断。

#### 15.6.1 三层机制

**预防层（hook 自动拦截）**：
- `scripts/pre-commit` 拒绝在 main 上的手写 commit（§15.1 落地）。允许：merge / cherry-pick / revert / rebase 进行中的 commit。逃生闸：`TERMURA_ALLOW_MAIN_COMMIT=1`，仅限紧急。
- `scripts/pre-push` 拒绝 force-push / delete-push 到 `refs/heads/main`（§15.5 落地）。逃生闸：`TERMURA_ALLOW_MAIN_FORCE=1`，仅在用户已显式授权后使用。

**检测层（按需 audit）**：
- `scripts/check-main-currency.sh` — 两仓 main vs 所有 published 分支的状态矩阵，含跨仓 wire 协调检测。
- `--strict`：未合且非 `archive/` / `wip/` 的分支若超过年龄阈值则 exit 1（用于 CI / release 节点）。
- `--no-wire`：跳过 wire 检测，秒级返回（用于 quality-gate 集成）。
- `--quiet`：抑制 per-branch 表格，仅保留 summary。

**流程层（quality-gate 集成）**：
- `bash scripts/quality-gate.sh`（非 `--staged` 路径）末尾自动追加一次 `--no-wire` advisory；每次 quality-gate 跑都能看到一眼分支健康度。

#### 15.6.2 分支命名约定（噪音控制）

- `feat/*` / `fix/*` / `chore/*` / `refactor/*` / `docs/*` / `build/*` — 默认合并候选。超过 `STALE_DAYS`（默认 3 天）未合且未声明 ready/archive/wip 即报警。
- `ready/*` — 显式声明完成态、等待合并。`READY_STALE_DAYS`（默认 1 天）即报警。
- `archive/*` — 永久保留作历史备份，永不报警，无论年龄。
- `wip/*` — 主动进行中的长命分支，不要求合并，永不报警。

#### 15.6.3 合并触发节点（**人为决策**）

| 触发节点 | 该合 | 备注 |
|---|---|---|
| 一个工作单元完成 + quality-gate 全绿 | ✅ | **默认节点** |
| 跨仓 wire 改动落地 | ✅ | 公仓先合，私仓紧跟（§15.2） |
| Release / 重要节点前 | ✅ (strict) | 调 `--strict`，零容忍未合 |
| 每个 commit / push 后 | ❌ | feat 分支会失去原子意义 |
| 心血来潮 | ⚠️ | 容易漏 conflict / wire 协调，不建议 |

**策略矩阵**（合的时候选哪一种）：

| 分支状态 | 推荐策略 | 命令 |
|---|---|---|
| ff-mergeable（main 是 ancestor） | **fast-forward**（默认，§15.3） | `git merge --ff-only <branch>` |
| diverged 单 commit | **cherry-pick**（线性 atomic，保留分支为备份） | `git cherry-pick <sha>` |
| diverged 多 commit 内容自洽 | **`--no-ff` merge commit**（保留分支作为一个合并单元） | `git merge --no-ff <branch>` |
| diverged 累积大量 WIP / fixup | **squash**（§15.3） | `git merge --squash <branch>` |
| 跨仓 wire 改动 | 按 §15.2 协调顺序，先公仓后私仓 | — |

#### 15.6.4 Audit Cadence

- **每次完成一次 push** → 跑 `bash scripts/check-main-currency.sh`（advisory，看一眼）。
- **每周 / release / 重要里程碑前** → 跑 `--strict`，目标 exit 0。
- **跨仓 wire 改动前后** → 跑双仓 audit，确认私仓引用的 protocol 类型都在公仓 main 已存在。
- **想保留某条不打算合的分支** → 重命名为 `archive/...` 或 `wip/...`，把"为什么留着"落到分支名里，让 audit 自动闭嘴。
