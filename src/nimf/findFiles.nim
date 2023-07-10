# File path text finding --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## File path finding, posix only currently as it uses stat.

import ./[common, find, handling], std/[os, paths, locks, atomics, posix], pkg/malebolgia, pkg/adix/[lptabz, althash]

proc `&`(p: Path; c: char): Path {.inline, borrow.}
proc add(x: var Path; y: char) {.inline.} = x.string.add y
proc hash(x: Path): Hash {.inline, borrow.}

type
  File = object
    path*: Path
    case kind*: PathComponent
    of pcFile:
      stat*: Stat
    of pcLinkToFile:
      broken*: bool
    else: discard
  Findings = object
    found*: tuple[paths: seq[Found], lock: Lock]
    dirs*: tuple[paths: LpSetz[Path, int8, 6], lock: Lock]

proc toFound(file: File, path: Path, matches: seq[(int, int)]): Found =
  result = Found(path: path, matches: matches, kind: file.kind)
  case file.kind
  of pcFile:
    result.stat = file.stat
  of pcLinkToFile:
    result.broken = file.broken
  else: discard

proc init(T: typedesc[Findings]): T =
  result.dirs.paths = initLpSetz[Path, int8, 6]()
  initLock(result.found.lock)
  initLock(result.dirs.lock)

template withLock(lock: Lock; body: untyped): untyped =
  acquire(lock)
  {.gcsafe.}:
    try: body
    finally: release(lock)

proc addImpl(findings: var Findings; found: Found) {.inline.} =
  withLock(findings.found.lock):
    findings.found.paths.add found

proc seenOrInclImpl(findings: var Findings; dir: Path): bool {.inline.} =
  withLock(findings.dirs.lock):
    result = findings.dirs.paths.containsOrIncl dir

template add(findings: var Findings; found: Found) = {.gcsafe.}: addImpl(findings, found)
template seenOrIncl(findings: var Findings; dir: Path): bool = {.gcsafe.}: seenOrInclImpl(findings, dir)

var findings = Findings.init()

proc findPath*(path: Path; patterns: openArray[string]): seq[(int, int)] =
  ## Variant of `find` which searches the filename for patterns following the last pattern with a directory separator
  if patterns.len == 0: return @[]

  var filenameSep = -1
  for i in countdown(patterns.high, patterns.low):
    if '/' in patterns[i]:
      filenameSep = i
      break
  let lastSep = path.string.rfind("/", last = path.string.high - 1).get(0)

  result = newSeq[(int, int)](patterns.len)
  var last = path.string.high

  let sensitive = patterns.containsAny({'A'..'Z'})
  template smartrfind(args: varargs[untyped]): untyped =
    if sensitive: rfind(args) else: rfindI(args)

  for i in countdown(patterns.high, patterns.low):
    if last < 0: return @[]
    let pattern = patterns[i]
    if pattern.len == 0:
      result[i] = (0, 0)
    else:
      let found = smartrfind(path.string, pattern, start = if i > filenameSep: lastSep else: 0, last)
      if found.isNone: return @[]
      result[i][1] = found.unsafeGet
      result[i][0] = result[i][1] - pattern.high
      last = result[i][0] - 1

iterator walkDirStat*(dir: string; relative = false, checkDir = false): File {.tags: [ReadDirEffect].} =
  var d = opendir(dir)
  if d == nil:
    if checkDir:
      raiseOSError(osLastError(), dir)
  else:
    defer: discard closedir(d)
    while true:
      var x = readdir(d)
      if x == nil: break
      var result = File(kind: pcFile)
      result.path = Path($cast[cstring](addr x.d_name))
      if result.path notin [Path ".", Path ".."]:
        let path = Path(dir) / result.path
        if not relative:
          result.path = path

        proc getSymlinkFileKind(path: Path): tuple[pc: PathComponent, broken: bool] =
          var s: Stat
          assert(path != Path "")
          result = (pcLinkToFile, true)
          if stat(path.cstring, s) == 0'i32:
            if S_ISDIR(s.st_mode):
              result = (pcLinkToDir, false)
            elif S_ISREG(s.st_mode):
              result = (pcLinkToFile, false)

        template resolveSymlink() =
          (result.kind, result.broken) = getSymlinkFileKind(path)

        template kSetGeneric() = # pure Posix component `k` resolution
          if lstat(path.cstring, result.stat) < 0'i32: continue  # don't yield
          elif S_ISDIR(result.stat.st_mode):
            result.kind = pcDir
          elif S_ISLNK(result.stat.st_mode):
            resolveSymlink()

        when defined(linux) or defined(macosx) or
             defined(bsd) or defined(genode) or defined(nintendoswitch):
          case x.d_type
          of DT_DIR: result.kind = pcDir
          of DT_LNK:
            resolveSymlink()
          of DT_UNKNOWN:
            kSetGeneric()
          else: # DT_REG or special "files" like FIFOs
            discard
        else:  # assuming that field `d_type` is not present
          kSetGeneric()

        yield result

var printQueue = newStringOfCap(8192)
var numFailed: Atomic[int] # To print often even if there's a lot of filtering but few matches
var printLock: Lock

proc writePrintQueue() {.inline.} =
  stdout.write printQueue
  printQueue.setLen 0
  numFailed.store(0)

proc print(s: string) {.inline.} =
  withLock(printLock):
    printQueue.add s & '\n'
    if printQueue.len >= 8192:
      writePrintQueue()

proc notFoundPrint() {.inline.} =
  if ({.gcsafe.}: printQueue.len) > 0 and numFailed.fetchAdd(1) > 16384:
    withLock(printLock):
      writePrintQueue()

proc findDirRec(m: MasterHandle; dir: Path; patterns: openArray[string]; kinds: set[PathComponent]; followSymlinks: bool; behavior: runOption) {.gcsafe.} =
  let absolute = isAbsolute(dir)
  for descendent in dir.string.walkDirStat(relative = not absolute):
    template format(path: Path): Path =
      if absolute or dir.string in [".", "./"]: path
      else: dir / path

    template absolute(path: Path): Path =
      if absolute: path
      else: absolutePath(path)

    template wasFound =
      case behavior
      of plainPrint: print path.string
      of coloredPrint: print ({.gcsafe.}: color(descendent.toFound(path, matches = found), patterns))
      of collect: findings.add descendent.toFound(path, matches = found)

    if descendent.kind == pcDir:
      var path = format(descendent.path) & '/'
      if followSymlinks:
        let absPath = path.absolute
        if findings.seenOrIncl absPath: continue
      m.spawn findDirRec(m, path, patterns, kinds, followSymlinks, behavior)
      if pcDir in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          wasFound()
        elif behavior in {plainPrint, coloredPrint}:
          notFoundPrint()

    elif followSymlinks and descendent.kind == pcLinkToDir:
      let path = format(descendent.path)
      var resolved = Path(expandSymlink(path.string))
      if resolved == Path("/"): continue # Special case this
      var absResolved = absolute(resolved)
      if absResolved.string[^1] != '/': absResolved &= '/'
      if resolved.string[^1] != '/': resolved &= '/'
      if not findings.seenOrIncl absResolved:
        m.spawn findDirRec(m, resolved, patterns, kinds, followSymlinks, behavior)

      if pcLinkToDir in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          wasFound()
        elif behavior in {plainPrint, coloredPrint}:
          notFoundPrint()

    elif descendent.kind in kinds:
      let path = format(descendent.path)
      let found = path.findPath(patterns)
      if found.len > 0:
        wasFound()
      elif behavior in {plainPrint, coloredPrint}:
        notFoundPrint()

proc stripDot(p: Path): Path {.inline.} =
  if p.string.len > 2 and p.string[0..1] == "./": Path(p.string[2..^1])
  else: p

proc traverseFind*(paths: openArray[Path]; patterns: seq[string]; kinds = {pcFile, pcDir, pcLinkToFile, pcLinkToDir}; followSymlinks = false; behavior: runOption): seq[Found] =
  var m = createMaster()
  m.awaitAll:
    for i, path in paths:
      let info = getFileInfo(path.string)
      if info.kind == pcDir:
        m.spawn findDirRec(getHandle m, path, patterns, kinds, followSymlinks, behavior)
      elif info.kind in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          template statFound: Found =
            case info.kind
            of pcFile:
              var s: Stat
              if lstat(cstring path.string, s) < 0'i32: continue
              Found(path: path.stripDot, kind: pcFile, matches: found, stat: s)
            of pcLinkToFile:
              var s: Stat
              let broken = stat(cstring path.string, s) < 0'i32
              Found(path: path.stripDot, kind: pcLinkToFile, matches: found, broken: broken)
            else:
              Found(path: path.stripDot, kind: info.kind, matches: found)
          case behavior
          of plainPrint: print path.string
          of coloredPrint: print color(statFound(), patterns)
          of collect: findings.add statFound()
        else: notFoundPrint()
  case behavior
  of plainPrint, coloredPrint:
    if printQueue.len > 0: stdout.write printQueue
  of collect: result &= findings.found.paths
