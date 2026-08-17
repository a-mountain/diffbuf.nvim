NVIM ?= nvim
PLUGIN_ROOT := $(CURDIR)
DEPS_DIR := $(PLUGIN_ROOT)/.test-deps
MINI_DIFF_DIR := $(DEPS_DIR)/mini.diff
MINI_DIFF_URL ?= https://github.com/nvim-mini/mini.diff.git
MINI_DIFF_REV ?= 626b8a5b93874c4d05ca25aedec56cfff0b378fb
CASES := parser tree open lsp_definition review inline panel

.PHONY: test test-live deps helptags clean-deps

deps: $(MINI_DIFF_DIR)

$(MINI_DIFF_DIR):
	@git clone --quiet --filter=blob:none $(MINI_DIFF_URL) $(MINI_DIFF_DIR)
	@git -C $(MINI_DIFF_DIR) checkout --quiet $(MINI_DIFF_REV)

clean-deps:
	@rm -rf $(DEPS_DIR)

test: deps
	@$(NVIM) --version | sed -n '1p'
	@git -C $(MINI_DIFF_DIR) rev-parse --short HEAD | sed 's/^/mini.diff /'
	@set -e; for case in $(CASES); do \
		NVIM_PLUGIN_ROOT="$(PLUGIN_ROOT)" NVIM_DEPS_DIR="$(DEPS_DIR)" $(NVIM) --headless --clean --cmd 'set loadplugins' -u tests/minimal_init.lua -l "tests/cases/$$case.lua"; \
	done

test-live: deps
	@test -n "$(DIFFBUF_LIVE_CWD)" || (echo "DIFFBUF_LIVE_CWD is required" && exit 1)
	@NVIM_PLUGIN_ROOT="$(PLUGIN_ROOT)" NVIM_DEPS_DIR="$(DEPS_DIR)" $(NVIM) --headless --clean --cmd 'set loadplugins' -u tests/minimal_init.lua -l tests/live.lua

helptags:
	@$(NVIM) --headless -u NONE -i NONE '+helptags doc' +qa
