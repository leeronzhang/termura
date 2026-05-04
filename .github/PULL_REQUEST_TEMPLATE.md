<!--
  Termura PR template — see CLAUDE.md §14 for the full review checklist.
  Delete sections that don't apply, but keep the open-core boundary
  checklist on every PR (it catches the highest-impact regressions).
-->

## Summary

<!-- 1-3 bullet points explaining what this PR changes and why. -->

## Open-core boundary

- [ ] No new private-repo path literal in tracked public files — pre-commit blocks the canonical form; double-check after rebase
- [ ] No new private type-name leak in `Sources/Termura/Harness/*.swift` stubs (review-only; run `bash scripts/check-baseline-snapshots.sh`)
- [ ] If `.swiftlint.yml`, `.gitignore` `Sources/Termura/Harness/` reverse-glob, or stub private-symbol set changed: corresponding file in `scripts/baseline/` is updated (will fail otherwise)

## Quality gate

- [ ] `bash scripts/quality-gate.sh` passes locally (0 errors, 0 warnings)
- [ ] If touching SwiftLint config or baseline files: re-ran `bash scripts/check-baseline-drift.sh` and committed any deliberate updates

## Test plan

<!--
  Markdown checklist of how this change was verified. Include the actual
  commands you ran, not just the categories.
  -->

- [ ] ...
