#[
	Copyright (C) 2023, Lefteris Zafiris <zaf@fastmail.com>
	This program is free software, distributed under the terms of
	the GNU GPL v3 License. See the LICENSE file
	at the top of the source tree.
]#

# npcp build config

var source = "src/npcp.nim"
var binary = toExe("npcp")

hint("Conf", false)

switch("threads", "on")
switch("mm", "orc")
switch("app", "console")
switch("out", binary)

task release, "Build release version":
  switch("define", "release")
  switch("passC", "-flto")
  switch("passL", "-flto")
  setCommand "c", source

task debug, "Build debug version (default)":
  switch("define", "debug")
  switch("checks", "on")
  switch("debugger", "native")
  switch("linetrace", "on")
  setCommand "c", source

task build, "Build binary":
  debugTask()

task pretty, "Run nimpretty":
  if fileExists(source):
    let np = findExe("nimpretty")
    if np != "":
      echo "Formatting " & source
      exec(np & " --maxLineLen=160 " & source)

task clean, "Remove compiled binaries":
  if fileExists(binary):
    echo "Removing binary " & binary
    rmFile(binary)
