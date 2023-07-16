# File path text finding --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Main logic for nimf.
## Posix only currently as it uses stat.

import ./[common, find, handling], std/[os, paths, locks, posix], pkg/malebolgia, pkg/adix/[lptabz, althash]

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

func preceedsWith(text, substr: openArray[char]; last, subStart, subEnd: Natural): Option[(Natural, Natural)] {.inline.} =
  ## Checks if `substr[subStart..subEnd]` is in `text` ending at `last`
  for i in substr.low..subEnd - subStart:
    if text[last - (subEnd - subStart - i)] != substr[i + subStart]: return
  result = some (Natural(last - (subEnd - subStart)), last)

func preceedsWith(text, substr: openArray[char]; last, subStart, subEnd: Natural; cmp: proc): Option[(Natural, Natural)] {.inline.} =
  ## Checks if `substr[subStart..subEnd]` is in `text` ending at `last`, custom comparison procedure variant
  for i in substr.low..subEnd - subStart:
    if not cmp(text[last - (subEnd - subStart - i)], substr[i + subStart]): return
  result = some (Natural(last - (subEnd - subStart)), last)

func preceedsWith(path: Path, substr: openArray[char]; last: Natural; sensitive: bool): Option[(Natural, Natural)] {.inline.} =
  ## preceedsWith but treats the beginning and end of the `text` the same as a `/` character
  template redirect(last = last; subStart = substr.low; subEnd = substr.high): untyped =
    if sensitive: path.string.preceedsWith(substr, last, subStart, subEnd)
    else: path.string.preceedsWith(substr, last, subStart, subEnd, cmp = cmpInsensitive)

  if substr.len == 1:
    if path.string[last] == substr[0]: return some (last, last) else: return
  if last == path.string.high and substr[^1] == '/' and path.string[^1] != '/':
    redirect(subEnd = substr.high - 1)
  elif last == substr.high and substr[0] == '/' and path.string[0] != '/':
    redirect(last - 1, subStart = substr.low + 1)
  else: redirect()

func rfind(path: Path, pattern: openArray[char]; start, last: Natural; sensitive: bool): Option[(Natural, Natural)] {.inline.} =
  for i in countdown(last, start):
    let ret = path.preceedsWith(pattern, i, sensitive)
    if ret.isSome: return ret
  result = none (Natural, Natural)

proc findPath*(path: Path; patterns: openArray[string]): seq[(int, int)] =
  ## Variant of `find` which searches the filename for patterns following the last pattern with a directory separator
  if patterns.len == 0: return @[]
  result = newSeq[(int, int)](patterns.len)

  var filenameSep = -1
  for i in countdown(patterns.high, patterns.low):
    if '/' in patterns[i]:
      filenameSep = i
      break
  let lastSep = block:
    if path.string.len == 1: 0
    else: path.string.rfind("/", last = path.string.high - 1).get(0)

  var last = path.string.high
  let sensitive = patterns.containsAny({'A'..'Z'})

  for i in countdown(patterns.high, patterns.low):
    if last < 0: return @[]
    let pattern = patterns[i]
    if pattern.len == 0:
      result[i] = (0, 0)
    else:
      let found = rfind(path, pattern, start = if i > filenameSep: lastSep else: 0, last, sensitive)
      if found.isNone: return @[]
      result[i] = found.unsafeGet
      last = result[i][0] - 1

iterator walkDirStat*(dir: string; relative = false, checkDir = false): File {.tags: [ReadDirEffect].} =
  # `walkDir` which yields an object containing the `Stat` if the path was a file
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

        template getSymlinkFileKind(path: Path) =
          var s: Stat
          assert(path != Path "")
          if stat(path.cstring, s) == 0'i32:
            if S_ISDIR(s.st_mode):
              result.kind = pcLinkToDir
            elif S_ISREG(s.st_mode):
              (result.kind, result.broken) = (pcLinkToFile, false)
            else: (result.kind, result.broken) = (pcLinkToFile, true)
          else: (result.kind, result.broken) = (pcLinkToFile, true)

        template resolveSymlink() =
          getSymlinkFileKind(path)

        template kSetGeneric() = # pure Posix component `k` resolution
          if lstat(path.cstring, result.stat) < 0'i32: continue  # don't yield
          elif S_ISDIR(result.stat.st_mode):
            result.kind = pcDir
          elif S_ISLNK(result.stat.st_mode):
            resolveSymlink()

        {.cast(uncheckedAssign).}: # Assigning `result.kind`
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
var printLock: Lock
var numFailed = 0 # To print often even if there's a lot of filtering but few matches
var numPrinted = 0 # If there's a low number of matches printing directly can be faster than batching

{.push inline.}

proc writePrintQueue() =
  stdout.write printQueue; stdout.flushFile()
  reset printQueue
  numFailed = 0

func wrapHyperlink(path: Path, prefix, cwd: string, display = path.string): string =
  result = prefix
  if not path.isAbsolute:
    result.add cwd
  result.add encodeHyperlink(path.string)
  result.add "\e\\"
  result.add display
  result.add "\e]8;;\e\\"

proc print(path: Path; behavior: runOption; display = path.string) =
  template output: string =
    (if behavior.hyperlink: wrapHyperlink(path, behavior.hyperlinkPrefix, behavior.cwd, display)
     else: display) & (if behavior.null: '\0' else: '\n')

  if numPrinted < 8192:
    stdout.write output(); stdout.flushFile()
    inc numPrinted
  else:
    withLock(printLock):
      printQueue.add output()
      if printQueue.len >= 8192:
        writePrintQueue()

proc notFoundPrint() =
  {.gcsafe.}:
    if printQueue.len > 0:
      inc numFailed
      if numFailed > 16384:
        withLock(printLock):
          writePrintQueue()

{.pop inline.}

proc findDirRec(m: MasterHandle; dir: Path; patterns: openArray[string]; kinds: set[PathComponent]; followSymlinks: bool; behavior: runOption) {.gcsafe.} =
  let absolute = isAbsolute(dir)
  for descendent in dir.string.walkDirStat(relative = not absolute):
    template format(path: Path): Path =
      if absolute or dir.string in [".", "./"]: path
      else: dir / path

    template absolute(path: Path): Path =
      if absolute: path
      else: absolutePath(path)

    template wasFound(found: seq[(int, int)]) =
      case behavior.kind
      of plainPrint:
        print(path, behavior)
      of coloredPrint:
        print(path, behavior, ({.gcsafe.}: color(descendent.toFound(path, matches = found), patterns)))
      of collect: findings.add descendent.toFound(path, matches = found)
      of exec: run(m, behavior.cmds, descendent.toFound(path, matches = found))

    template match(path: Path) =
      let found = path.findPath(patterns)
      if found.len > 0:
        wasFound(found)
      elif behavior.kind in {plainPrint, coloredPrint}:
        notFoundPrint()

    if descendent.kind == pcDir:
      let path = format(descendent.path) & '/'
      if followSymlinks:
        let absPath = path.absolute
        if findings.seenOrIncl absPath: continue
      m.spawn findDirRec(m, path, patterns, kinds, followSymlinks, behavior)
      if pcDir in kinds:
        match(path)

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
        match(path)

    elif descendent.kind in kinds:
      let path = format(descendent.path)
      match(path)

func stripDot(p: Path): Path {.inline.} =
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

          case behavior.kind
          of plainPrint:
            print(path, behavior)
          of coloredPrint:
            print(path, behavior, color(statFound(), patterns))
          of collect: findings.add statFound()
          of exec: run(m.getHandle, behavior.cmds, statFound())
        elif behavior.kind in {plainPrint, coloredPrint}:
          notFoundPrint()

  case behavior.kind
  of plainPrint, coloredPrint:
    if printQueue.len > 0: stdout.write printQueue; stdout.flushFile()
  of collect: result &= findings.found.paths
  else: discard
