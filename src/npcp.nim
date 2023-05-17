#[
	Copyright (C) 2023, Lefteris Zafiris <zaf@fastmail.com>
	This program is free software, distributed under the terms of
	the GNU GPL v3 License. See the LICENSE file
	at the top of the source tree.
]#

##
##  Parallel file copy.
##
## The npcp utility copies the contents of the source file to the destination file.
## It maps the contets of the files in memory and copies data in parallel using
## a number of threads that by default is the number of available CPU threads.
##

when compileOption("profiler"):
  import nimprof

import std/os
import std/cpuinfo
import std/parseopt
import std/strutils
import std/bitops
import posix

let helpMsg = """

Options:
  -f, --force:
    Overwrite destination file if it exists.

  -s, --sync:
    Sync file to disk after done copying data.

  -t=[threads], --threads=[threads]:
    Specifies the number of threads used to copy data simultaneously.
    This number is by default the number of available CPU threads."""


type chunkData = tuple[src, dst: FileHandle, startOff, endOff: int64]

var
  sync = false             # Sync file to disk after done copying data.
  force = false            # Force overwritting of existing file.
  jobs = 0                 # Number of parallel threads copying data.
  files = newSeq[string]() # Source and destination files.

let
  pageSize = int64(sysconf(SC_PAGESIZE)) # OS memory page size.
  minSize = 256 * pageSize               # File size limit.

proc printHelpMsg(full: bool) =
  ## Print a help message
  let binName = splitFile(getAppFilename()).name
  stderr.writeLine("Parallel file copy")
  stderr.writeLine("Usage: ", binName, " [options] source destination")
  if full:
    stderr.writeLine(helpMsg)
  quit(1)

proc pageAlign(size: int64): int64 =
  ## Align to OS page boundaries
  return (size div pageSize) * pageSize

proc mmapcopy(data: chunkData) {.thread, raises: [IOError].} =
  ## Use mmap to copy file chunks
  let size = int(data.endOff-data.startOff)
  let s = mmap(pointer(nil), size, PROT_READ, MAP_SHARED, data.src, Off(data.startOff))
  if s == MAP_FAILED:
    raise newException(IOError, "failed to memory map source file")

  let madviseResult = posix_madvise(s, size, POSIX_MADV_SEQUENTIAL)
  if madviseResult != 0:
    stderr.writeLine("warning: madvise() failed")

  let d = mmap(pointer(nil), size, bitor(PROT_READ, PROT_WRITE), MAP_SHARED, data.dst, Off(data.startOff))
  if d == MAP_FAILED:
    raise newException(IOError, "failed to memory map destination file")

  copyMem(d, s, size)
  if sync:
    let msyncResult = msync(d, size, MS_SYNC)
    if msyncResult != 0:
      raise newException(IOError, "msync() failed")

  let munpapSourceResult = munmap(s, size)
  if munpapSourceResult != 0:
    stderr.writeLine("warning: failed to unmap source file")

  let munpapDestResult = munmap(d, size)
  if munpapDestResult != 0:
    raise newException(IOError, "failed to unmap destination file")

proc parallelCopy(source, destination: string) {.raises: [IOError, ResourceExhaustedError].} =
  ## Copy fille contents in parallel
  if fileExists(source) != true or symlinkExists(source) == true:
    raise newException(IOError, source & " does not exist or is not a regular file")

  var src: File
  try:
    src = open(source, fmRead)
  except CatchableError:
    let e = getCurrentException()
    raise newException(IOError, "failed to open source file", e)
  defer: src.close()
  let srcSize = src.getFileSize()

  var dst: File
  try:
    dst = open(destination, fmReadWrite)
  except CatchableError:
    let e = getCurrentException()
    raise newException(IOError, "failed to open destination file", e)
  defer: dst.close()

  let ftruncateResult = ftruncate(dst.getFileHandle(), Off(srcSize))
  if ftruncateResult != 0:
    raise newException(IOError, "failed to resize destination file")

  if srcSize == 0:
    return

  # Don't run parallel jobs for small files
  if srcSize < minSize:
    jobs = 1

  let chunk = pageAlign(srcSize div int64(jobs))
  var startOffset, endOffset: int64
  endOffset = chunk

  var threads = newSeq[Thread[chunkData]](jobs)

  for i in 0..threads.high:
    if i == threads.high:
      endOffset = srcSize
    createThread(threads[i], mmapcopy, (src.getFileHandle(), dst.getOsFileHandle(), startOffset, endOffset))
    startOffset += chunk
    endOffset += chunk

  joinThreads(threads)
  return

# main()
proc main() =
  # Parse flags
  var jobsVal: string
  var p = initOptParser()
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      files.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "force", "f": force = true
      of "sync", "s": sync = true
      of "threads", "t": jobsVal = val
      of "help", "h": printHelpMsg(full = true)
    of cmdEnd: printHelpMsg(full = true)

  if files.len != 2:
    printHelpMsg(full = false)

  let source = files[0]
  let destination = files[1]
  if source == destination:
    stderr.writeLine(source, " and ", destination, " are the same file")
    quit(1)

  if jobsVal != "":
    try:
      jobs = parseInt(jobsVal)
    except CatchableError:
      stderr.writeLine("error setting number of threads: ", getCurrentExceptionMsg())

  if jobs < 1:
    jobs = countProcessors()

  if force != true and fileExists(destination):
    stderr.write("File ", destination, " already exists, overwrite? (y/N) ")
    let a = toLowerAscii(readLine(stdin))
    if a != "y" and a != "yes":
      stderr.writeLine("not overwritten")
      quit(1)

  try:
    parallelCopy(source, destination)
  except CatchableError:
    stderr.writeLine(getCurrentExceptionMsg())
    quit(1)

main()
