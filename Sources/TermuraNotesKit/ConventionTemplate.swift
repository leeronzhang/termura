import Foundation

/// Static template content for the knowledge sinking convention.
/// Lives in Kit so MCP Server can reference it in the future.
public enum ConventionTemplate {
    /// Marker string used to detect whether CLAUDE.md already has the reference.
    public static let claudeMarker = "## Knowledge Sinking Convention"

    /// Short reference snippet to append to the project's CLAUDE.md.
    public static let claudeReferenceSnippet = """

    ## Knowledge Sinking Convention

    本项目启用 Termura Notes 知识管理。Agent 在工作过程中应主动沉淀知识到 `.termura/knowledge/` 目录。

    完整规约见: `.termura/knowledge/CONVENTION.md`

    Agent 首次操作 notes 前必须阅读该文件。
    """

    /// Full convention document written to .termura/knowledge/CONVENTION.md.
    public static let conventionContent = """
    # Knowledge Sinking Convention

    本项目使用 Termura Notes 管理项目知识。Agent 在工作过程中应主动沉淀知识。

    ---

    ## 何时沉淀

    | 触发场景 | 动作 | 标题示例 |
    |---------|------|---------|
    | 解决 bug | 创建 note，记录根因 + 修复方案 | `auth-token-refresh-bug` |
    | 做出架构/设计决策 | 创建 note，记录决策 + 理由 + 备选方案 | `decision-grdb-vs-coredata` |
    | 学到新知识/模式 | 创建或追加到已有 note | `swift-concurrency-patterns` |
    | 调研外部资料 | import 到 sources/，编写摘要 note | `oauth2-rfc-summary` |
    | 完成一轮重要对话 | 关键结论追加到相关 note | 追加到已有 note |

    ## 何时不沉淀

    - 一次性的小修改（typo、格式调整）
    - 已在 git commit message 中充分记录的内容
    - 纯机械性操作（rename、move file）

    ---

    ## 三层目录

    | 目录 | 用途 | 写入方 |
    |------|------|--------|
    | `sources/` | 静态外部素材（文章、PDF、代码片段、截图） | 人 + agent import |
    | `log/` | 人 ↔ AI 对话记录（append-only） | agent capture |
    | `notes/` | 整理产物（主要输出层） | agent create/append |

    ---

    ## Tag 命名规范

    每个 note **至少 1 个 tag**。使用 kebab-case。

    **领域 tag**（按项目模块扩展）：

    `auth`, `ui`, `terminal`, `notes`, `session`, `perf`, `infra`, `build`

    **类型 tag**：

    `bug-fix`, `decision`, `learning`, `reference`, `how-to`, `incident`

    Frontmatter 示例：`tags: [auth, bug-fix]`

    ---

    ## Frontmatter 要求

    **必填**：
    - `title` — 描述性 kebab-case 名称
    - `tags` — 至少 1 个

    **推荐**：
    - `references` — 引用的源文件路径或外部链接

    ---

    ## Note 标题规范

    - 使用 kebab-case 描述性名称
    - 具体优于笼统：`swift-actor-reentrancy-pitfall` > `concurrency-notes`
    - Bug / incident 类加日期：`auth-token-bug-2026-04`

    ---

    ## Backlink

    当 note A 引用 note B 时，在正文中使用 `[[B 的标题]]` 语法。
    Agent 应主动在相关 note 间建立 backlink。

    ---

    ## CLI 命令参考

    ```bash
    # 创建 note
    tn create --title "note-title" --body "内容" --tags "tag1,tag2"

    # 追加内容
    tn append --to "note-title" "追加的内容"

    # 搜索
    tn search "关键词"

    # 建立 backlink
    tn link --from "note-a" --to "note-b"

    # 导入素材
    tn import file /path/to/file
    tn import url https://example.com/article
    ```

    ## MCP 工具参考

    如果已配置 MCP Server (`tn mcp`)，可通过以下工具直接操作：

    - `list_notes` — 列出所有 notes
    - `read_note` — 读取 note 内容
    - `search_notes` — 全文搜索
    - `create_note` — 创建新 note（支持 title, body, tags）
    - `append_to_note` — 追加内容到已有 note
    - `link_notes` — 建立 backlink
    """
}
