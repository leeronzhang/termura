.PHONY: setup lint format build test clean hook ci-local

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

# ── 清理 ──────────────────────────────────────────────────────
clean:
	xcodebuild clean -scheme Termura
	rm -rf ~/Library/Developer/Xcode/DerivedData/Termura-*

# ── 本地 CI 模拟（提交前完整检查）────────────────────────────
ci-local: format-check lint build test
	@echo ""
	@echo "✓ 本地 CI 全部通过"

# ── 日志查看 ──────────────────────────────────────────────────
logs:
	log stream --predicate 'process == "Termura"' --level debug
