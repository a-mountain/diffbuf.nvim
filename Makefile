NVIM ?= nvim
PLUGIN_ROOT := $(CURDIR)
CASES := parser open lsp_definition

.PHONY: test test-live helptags

test:
	@$(NVIM) --version | sed -n '1p'
	@set -e; for case in $(CASES); do \
		NVIM_PLUGIN_ROOT="$(PLUGIN_ROOT)" $(NVIM) --headless --clean --cmd 'set loadplugins' -u tests/minimal_init.lua -l "tests/cases/$$case.lua"; \
	done

test-live:
	@test -n "$(DIFFBUF_LIVE_CWD)" || (echo "DIFFBUF_LIVE_CWD is required" && exit 1)
	@NVIM_PLUGIN_ROOT="$(PLUGIN_ROOT)" $(NVIM) --headless --clean --cmd 'set loadplugins' -u tests/minimal_init.lua -l tests/live.lua

helptags:
	@$(NVIM) --headless -u NONE -i NONE '+helptags doc' +qa
