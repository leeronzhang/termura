.PHONY: setup lint format build test clean hook ci-local contract-test mock-audit perf-test

# ── 安装开发工具 ───────────────────────────────────────────────
setup:
	brew install swiftlint swiftformat xcodegen
	@echo "✓ 工具安装完毕"
	$(MAKE) hook

# ── 安装 pre-commit hook ──────────────────────────────────────
hook:
	cp scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "✓ pre-commit hook 已安装"

# ── 代码质量 ──────────────────────────────────────────────────
lint:
	swiftlint lint --strict

lint-fix:
	swiftlint --fix && swiftlint lint --strict

format:
	swiftformat Sources/ --verbose

format-check:
	swiftformat --lint Sources/ --quiet

# ── 构建 ──────────────────────────────────────────────────────
gen:
	xcodegen generate

build:
	xcodebuild \
		-scheme Termura \
		-configuration Debug \
		-destination 'platform=macOS' \
		build \
		| xcpretty 2>/dev/null || xcodebuild \
		-scheme Termura \
		-configuration Debug \
		-destination 'platform=macOS' \
		build

build-release:
	xcodebuild \
		-scheme Termura \
		-configuration Release \
		-destination 'platform=macOS' \
		build

# ── 测试 ──────────────────────────────────────────────────────
test:
	xcodebuild test \
		-scheme Termura \
		-destination 'platform=macOS' \
		-enableCodeCoverage YES \
		| xcpretty 2>/dev/null || xcodebuild test \
		-scheme Termura \
		-destination 'platform=macOS'

# ── Contract Tests（Mock/Real 一致性验证）─────────────────
contract-test:
	xcodebuild test \
		-scheme Termura \
		-destination 'platform=macOS' \
		-only-testing:TermuraTests/ContractTests \
		| xcpretty 2>/dev/null || xcodebuild test \
		-scheme Termura \
		-destination 'platform=macOS' \
		-only-testing:TermuraTests/ContractTests

# ── 性能测试（SLO 基准验证）──────────────────────────────
perf-test:
	xcodebuild test \
		-scheme Termura \
		-destination 'platform=macOS' \
		-only-testing:TermuraTests/PerformanceSLOTests \
		-only-testing:TermuraTests/PerformanceXCTMetricTests \
		| xcpretty 2>/dev/null || xcodebuild test \
		-scheme Termura \
		-destination 'platform=macOS' \
		-only-testing:TermuraTests/PerformanceSLOTests \
		-only-testing:TermuraTests/PerformanceXCTMetricTests

# ── Mock/Protocol 配对审计 ────────────────────────────────
mock-audit:
	@echo "=== Protocol/Mock Completeness Audit ==="
	@MISSING=0; \
	for proto in $$(find Sources/Termura -name "*Protocol.swift" \
	                -not -name "DatabaseServiceProtocol.swift"); do \
		base=$$(basename "$$proto" | sed 's/Protocol\.swift$$//'); \
		mock=$$(find Sources/Termura -name "Mock$${base}.swift" | head -1); \
		if [ -z "$$mock" ]; then \
			echo "  FAIL: $${base}Protocol -> Mock$${base} missing"; \
			MISSING=$$((MISSING + 1)); \
		else \
			echo "  OK: $${base}Protocol -> $$(basename $$mock)"; \
		fi; \
	done; \
	if [ "$$MISSING" -gt 0 ]; then \
		echo "$$MISSING protocol(s) missing Mock"; exit 1; \
	fi; \
	echo "=== All protocols have matching mocks ==="

# ── 清理 ──────────────────────────────────────────────────────
clean:
	xcodebuild clean -scheme Termura
	rm -rf ~/Library/Developer/Xcode/DerivedData/Termura-*

# ── 本地 CI 模拟（提交前完整检查）────────────────────────────
ci-local: format-check lint mock-audit build test contract-test
	@echo ""
	@echo "+ Local CI passed (lint + mock-audit + build + test + contract-test)"

# ── 日志查看 ──────────────────────────────────────────────────
logs:
	log stream --predicate 'process == "Termura"' --level debug
