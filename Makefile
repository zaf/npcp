bin := npcp

buildFlags := --threads:on --app=console  --mm:arc  --out:$(bin)
debugFlags := -d:debug --checks:on --debugger:native --lineTrace:on
releaseFlags := -d:release --passC:-flto --passL:-flto

.PHONY: clean

default: debug

debug: ## Build debug version (default)
debug: src/npcp.nim
	nim c $(buildFlags) $(debugFlags) $?

release: ## Build release version
release: src/npcp.nim
	nim c $(buildFlags) $(releaseFlags) $?

clean: ## Remove compiled binaries
clean:
	@rm -f $(bin)

help: ## Show this help.
	@egrep '^(.+)\:\ ##\ (.+)' ${MAKEFILE_LIST} | column -t -c 2 -s ':#'