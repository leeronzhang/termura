---
name: Dynamic SQL scan completed 2026-03-30
description: All dynamic SQL string interpolation in the codebase was comprehensively scanned and resolved; no outstanding instances remain
type: feedback
---

All dynamic SQL string interpolation instances were scanned and resolved on 2026-03-30.

**Why:** Code review flagged `SessionRepository.reorder` for SQL constructed via string interpolation without explaining why it was safe. Google-style review requires explicit rationale or query-builder pattern for any dynamic SQL structure.

**How to apply:** When encountering `let sql = "... \(variable) ..."` patterns in future changes, always add a `// Dynamic SQL: safe.` comment block or a whitelist precondition before review. Do not introduce new dynamic SQL construction without one of these two mitigations.

**Resolved locations (2026-03-30):**
- `SessionRepository.swift` — `reorder()`: added 5-line safety comment explaining `cases`/`holders` are static placeholder skeletons only
- `ProjectMigrationService.swift` — `copyTable()`: added `allowedMigrationTables` whitelist + `precondition` hard guard + doc comment safety contract
- No other dynamic SQL interpolation found in the codebase after full scan
