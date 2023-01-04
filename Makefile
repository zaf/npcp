src := npcp.nim
bin := npcp

buildFlags := --threads:on --app=console --out:$(bin)
debugFlags := -d:debug --checks:on --debugger:native --lineTrace:on
releaseFlags := -d:release

.PHONY: clean

default: debug

debug:
	nim c $(buildFlags) $(debugFlags) $(src) 

release:
	nim c $(buildFlags) $(releaseFlags) $(src)

clean:
	@rm -f $(bin)
