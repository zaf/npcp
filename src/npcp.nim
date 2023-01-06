#[
	Copyright (C) 2023, Lefteris Zafiris <zaf@fastmail.com>
	This program is free software, distributed under the terms of
	the GNU GPL v3 License. See the LICENSE file
	at the top of the source tree.
]#

#[
	Parallel file copy.

	Usage: npcp [-f] source destination

	The number of parallel threads is by default the number of available CPU threads.
	To change this set the environment variable PCP_THREADS with the desired number of threads:
	PCP_THREADS=4 npcp source destination

	To enable syncing of data on disk set the environment variable PCP_SYNC to true:
	PCP_SYNC=true npcp source destination
]#

import std/os
import std/cpuinfo
import std/parseopt
import std/strutils
import std/threadpool
import std/bitops
import posix

var
  sync = false                               # Sync file to disk after done copying data.
  force = false                              # Force overwritting of existing file.
  threads = 0                                # Number of threads copying data.
  files = newSeq[string]()                   # Source and destination files.
  binName = splitFile(getAppFilename()).name # Command name.

# Print help message
proc helpMsg() =
  stderr.writeLine("Usage ", binName, " [-f] source destination")
  quit(1)

# Get OS page size
proc getpagesize(): cint {.importc, header: "<unistd.h>".}

# Align to OS page boundaries
proc align(size: int64): int64 =
  let pageSize = int64(getpagesize())
  return (size div pageSize) * pageSize

# Use mmap to copy file chunks
proc mmapcopy(src, dst: FileHandle, startof, endof: int64) {.thread.} =
  let size = int(endof-startof)
  var s = mmap(pointer(nil), size, PROT_READ, MAP_SHARED, src, Off(startof))
  defer: discard munmap(s, size)
  discard posix_madvise(s, size, POSIX_MADV_SEQUENTIAL)

  var d = mmap(pointer(nil), size, bitor(PROT_READ, PROT_WRITE), MAP_SHARED, dst, Off(startof))
  defer: discard munmap(d, size)

  copyMem(d, s, endof-startof)
  if sync:
    discard msync(d, size, MS_SYNC)

# Copy fille contents in parallel
proc parallelCopy(source, destination: string): string =
  if fileExists(source) != true or symlinkExists(source) == true:
    return source & " does not exist or is not a regular file"

  var src: File
  try:
    src = open(source, fmRead)
  except:
    return "failed to open source file: " & getCurrentExceptionMsg()
  defer: src.close()
  let srcSize = src.getFileSize()

  var dst: File
  try:
    dst = open(destination, fmReadWrite)
  except:
    return "failed to open destination file: " & getCurrentExceptionMsg()
  defer: dst.close()

  try:
    discard ftruncate(dst.getFileHandle(), Off(srcSize))
  except:
    return "failed to resize destination file: " & getCurrentExceptionMsg()

  if srcSize == 0:
    return

  # Don't run parallel jobs for small files
  if srcSize < int64(256 * getpagesize()):
    threads = 1

  let chunk = align(srcSize div int64(threads))
  var startOffset, endOffset: int64
  endOffset = chunk
  setMinPoolSize(threads)

  for i in 1..threads:
    if i == threads:
      endOffset = srcSize
    spawn mmapcopy(src.getFileHandle(), dst.getOsFileHandle(), startOffset, endOffset)
    startOffset += chunk
    endOffset += chunk

  threadpool.sync()
  return

# main()
proc main() =
  # Parse flags
  var p = initOptParser()
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      files.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "force", "f": force = true
      of "help", "h": helpMsg()
    of cmdEnd: assert(false)

  if files.len != 2:
    helpMsg()

  let source = files[0]
  let destination = files[1]

  if toLowerAscii(getEnv("PCP_SYNC")) == "true":
    sync = true

  let t = getEnv("PCP_THREADS")
  if t != "":
    try:
      threads = parseInt(t)
    except:
      stderr.writeLine("error setting threads number from PCP_THREADS var: ", getCurrentExceptionMsg())

  if threads < 1:
    threads = countProcessors()

  if threads > MaxThreadPoolSize:
    stderr.writeLine("warning: threads number can't be bigger than ", $MaxThreadPoolSize)
    threads = MaxThreadPoolSize

  if force != true and fileExists(destination):
    echo "File ", destination, " already exists, overwrite? (y/N)"
    let a = toLowerAscii(readLine(stdin))
    if a != "y" and a != "yes":
      stderr.writeLine("not overwritten")
      quit(1)

  let err = parallelCopy(source, destination)
  if err != "":
    stderr.writeLine(err)
    quit(1)

main()
