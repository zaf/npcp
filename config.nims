#[
	Copyright (C) 2023, Lefteris Zafiris <zaf@fastmail.com>
	This program is free software, distributed under the terms of
	the GNU GPL v3 License. See the LICENSE file
	at the top of the source tree.
]#

# npcp build config

var source = "src/npcp.nim"
var formatting = @["src/npcp.nim", "config.nims"]
var binary = toExe("npcp")

hint("Conf", false)

switch("threads", "on")
switch("mm", "arc")
switch("app", "console")

task release, "Build release version":
  switch("define", "release")
  switch("passC", "-flto=auto")
  switch("passL", "-flto=auto")
  switch("passL", "-s")
  switch("out", binary)
  setCommand "compile", source

task debug, "Build debug version (default)":
  switch("define", "debug")
  switch("debugger", "native")
  switch("out", binary)
  setCommand "compile", source

task profile, "Build profiling version":
  switch("profiler", "on")
  switch("stackTrace", "on")
  switch("out", binary)
  setCommand "compile", source

task build, "Build binary":
  debugTask()

task pretty, "Run nimpretty":
  let np = findExe("nimpretty")
  if np != "":
    for file in formatting:
      if fileExists(file):
        echo "Formatting " & file
        exec(np & " --maxLineLen=160 " & file)

task clean, "Remove compiled binaries":
  if fileExists(binary):
    echo "Removing binary " & binary
    rmFile(binary)
