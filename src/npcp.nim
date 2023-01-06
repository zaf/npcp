#[
	Copyright (C) 2023, Lefteris Zafiris <zaf@fastmail.com>
	This program is free software, distributed under the terms of
	the GNU GPL v3 License. See the LICENSE file
	at the top of the source tree.
]#

##  Parallel file copy.
##
##	Usage: npcp [-f] source destination
##
##	The number of parallel threads is by default the number of available CPU threads.
##	To change this set the environment variable PCP_THREADS with the desired number of threads:
##	PCP_THREADS=4 npcp source destination
##
##	To enable syncing of data on disk set the environment variable PCP_SYNC to true:
##	PCP_SYNC=true npcp source destination

import std/os
import std/cpuinfo
import std/parseopt
import std/strutils
import std/threadpool
import std/bitops
import posix

var
  sync = false             # Sync file to disk after done copying data.
  force = false            # Force overwritting of existing file.
  threads = 0              # Number of threads copying data.
  files = newSeq[string]() # Source and destination files.

let
  pageSize = int64(sysconf(SC_PAGESIZE)) # OS memory page size.
  minSize = 256 * pageSize               # File size limit.

proc helpMsg() =
  ## Print a help message
  let binName = splitFile(getAppFilename()).name
  stderr.writeLine("Parallel file copy")
  stderr.writeLine("Usage: ", binName, " [-f] source destination")
  quit(1)

proc pageAlign(size: int64): int64 =
  ## Align to OS page boundaries
  return (size div pageSize) * pageSize

proc mmapcopy(src, dst: FileHandle, startof, endof: int64) {.thread, raises: [IOError].} =
  ## Use mmap to copy file chunks
  let size = int(endof-startof)
  var s = mmap(pointer(nil), size, PROT_READ, MAP_SHARED, src, Off(startof))
  if s == MAP_FAILED:
    raise newException(IOError, "failed to memory map source file")

  let madviseResult = posix_madvise(s, size, POSIX_MADV_SEQUENTIAL)
  if madviseResult != 0:
    stderr.writeLine("warning: madvise() failed")

  var d = mmap(pointer(nil), size, bitor(PROT_READ, PROT_WRITE), MAP_SHARED, dst, Off(startof))
  if d == MAP_FAILED:
    raise newException(IOError, "failed to memory map destination file")

  copyMem(d, s, endof-startof)
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

proc parallelCopy(source, destination: string) {.raises: [IOError].} =
  ## Copy fille contents in parallel
  if fileExists(source) != true or symlinkExists(source) == true:
    raise newException(IOError, source & " does not exist or is not a regular file")

  var src: File
  try:
    src = open(source, fmRead)
  except:
    let e = getCurrentException()
    raise newException(IOError, "failed to open source file", e)
  let srcSize = src.getFileSize()

  var dst: File
  try:
    dst = open(destination, fmReadWrite)
  except:
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
    threads = 1

  let chunk = pageAlign(srcSize div int64(threads))
  var startOffset, endOffset: int64
  endOffset = chunk
  setMaxPoolSize(threads)

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
  if source == destination:
    stderr.writeLine(source, " and ",  destination, " are the same file")
    quit(1)

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
    stderr.write("File ", destination, " already exists, overwrite? (y/N) ")
    let a = toLowerAscii(readLine(stdin))
    if a != "y" and a != "yes":
      stderr.writeLine("not overwritten")
      quit(1)

  try:
    parallelCopy(source, destination)
  except:
    stderr.writeLine(getCurrentExceptionMsg())
    quit(1)

main()
