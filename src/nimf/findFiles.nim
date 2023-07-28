# File path text finding --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Main logic for nimf.
## Posix only currently as it uses stat.
import ./[common, find, handling, ignore], std/[paths, locks, atomics, posix, sets, hashes], pkg/malebolgia
import std/os except getCurrentDir
from   std/sequtils import anyIt
export load

proc `&`(p: Path; c: char): Path {.inline, borrow.}
proc add(x: var Path; y: char) {.inline.} = x.string.add y
proc high(p: Path): int {.inline, borrow.}
proc len(p: Path): int {.inline, borrow.}
proc hash(x: Path): Hash {.inline, borrow.}

type
  File = object
    path*: string
    case kind*: PathComponent
    of pcFile:
      stat*: Option[Stat]
    of pcLinkToFile:
      broken*: bool
    else: discard
  Locked[T] = object
    value*: T
    lock*: Lock
  Findings = object
    found*: Locked[seq[Found]]
    dirs*: Locked[HashSet[Path]]

proc toFound(file: File, path: Path, matches: seq[(int, int)]): Found =
  result = Found(path: path, matches: matches, kind: file.kind)
  case file.kind
  of pcFile:
    result.stat = file.stat
  of pcLinkToFile:
    result.broken = file.broken
  else: discard

proc toFound(file: tuple[kind: PathComponent, path: string], path: Path, matches: seq[(int, int)]): Found =
  Found(path: path, matches: matches, kind: file.kind)

proc init(T: typedesc[Findings]): T =
  result.dirs.value = initHashset[Path]()
  initLock(result.found.lock)
  initLock(result.dirs.lock)

template withLock(lock: Lock; body: untyped): untyped =
  acquire(lock)
  {.gcsafe.}:
    try: body
    finally: release(lock)

proc addImpl(findings: var Findings; found: Found) {.inline.} =
  withLock(findings.found.lock):
    findings.found.value.add found

proc seenOrInclImpl(findings: var Findings; dir: Path): bool {.inline.} =
  withLock(findings.dirs.lock):
    result = findings.dirs.value.containsOrIncl dir

template add(findings: var Findings; found: Found) = {.gcsafe.}: addImpl(findings, found)
template seenOrIncl(findings: var Findings; dir: Path): bool = {.gcsafe.}: seenOrInclImpl(findings, dir)

var findings = Findings.init()

func preceedsWith(text, substr: openArray[char]; last, subStart, subEnd: Natural): Option[(Natural, Natural)] {.inline.} =
  ## Checks if `substr[subStart..subEnd]` is in `text` ending at `last`
  for i in 0..subEnd - subStart:
    if text[last - (subEnd - subStart - i)] != substr[i + subStart]: return
  result = some (Natural(last - (subEnd - subStart)), last)

func preceedsWith(text, substr: openArray[char]; last, subStart, subEnd: Natural; cmp: proc): Option[(Natural, Natural)] {.inline.} =
  ## Checks if `substr[subStart..subEnd]` is in `text` ending at `last`, custom comparison procedure variant
  for i in 0..subEnd - subStart:
    if not cmp(text[last - (subEnd - subStart - i)], substr[i + subStart]): return
  result = some (Natural(last - (subEnd - subStart)), last)

func rfind(path: Path, pattern: openArray[char]; start, last: sink Natural; sensitive: bool): Option[(Natural, Natural)] {.inline.} =
  template preceedsWith(last = last; patStart = pattern.low; patEnd = pattern.high): untyped =
    if sensitive: path.string.preceedsWith(pattern, last, patStart, patEnd)
    else: path.string.preceedsWith(pattern, last, patStart, patEnd, cmp = cmpInsensitive)

  template returnSome[T](o: Option[T]): untyped =
    let ret = o
    if ret.isSome: return ret

  # Special handling for / and $ as start and end of line
  if pattern.len > 1:
    if pattern[^1] == '$':
      let last = if path.string[last] == '/': last - 1 else: last
      let patEnd = pattern.high - (if pattern.len > 2 and pattern[^2] == '/': 2 else: 1)
      if last - patEnd >= 0:
        returnSome preceedsWith(last, 0, patEnd)
    if pattern[0] == '/' and path.string[0] != '/':
      let patStart = pattern.low + 1
      if pattern[^1] == '$': # $pattern/, check exact match
        let last = if path.string[last] == '/': last - 1 else: last
        let patEnd = pattern.high - (if pattern.len > 2 and pattern[^2] == '/': 2 else: 1)
        if last == patEnd - patStart:
          returnSome preceedsWith(last, patStart, patEnd)
      returnSome preceedsWith(pattern.high - patStart, patStart, pattern.high)

  for i in countdown(last, start):
    returnSome preceedsWith(i)
  result = none (Natural, Natural)

proc findPath*(path: Path; patterns: openArray[string]; sensitive: bool): seq[(int, int)] =
  ## Variant of `find` which searches the filename for patterns following the last pattern with a directory separator
  if patterns.len == 0: return @[]
  result = newSeq[(int, int)](patterns.len)

  var filenameSep = -1
  for i in countdown(patterns.high, patterns.low):
    if '/' in patterns[i]:
      filenameSep = i
      break
  let lastSep =
    if path.len == 1: 0
    else: path.string.rfind("/", last = path.high - 1).get(0)

  var last = path.high
  for i in countdown(patterns.high, patterns.low):
    if last < 0: return @[]
    if patterns[i].len == 0:
      result[i] = (0, 0)
    else:
      template start: untyped = (if i > filenameSep: lastSep + patterns[i].high else: patterns[i].high)
      let found = rfind(path, patterns[i], start, last, sensitive)
      if found.isNone: return @[]
      result[i] = found.unsafeGet
      last = result[i][0] - 1

func pathMatches(path: Path; pattern: openArray[char]): bool {.inline.} =
  rfind(path, pattern, pattern.high, path.high, true).isSome

template pathMatches(path: string; pattern: openArray[char]): bool =
  pathMatches(Path(path), pattern)

iterator walkDirStat*(dir: string; relative = false, checkDir = false): File {.tags: [ReadDirEffect].} =
  # `walkDir` which yields an object also containing what was read from `Stat`
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
      result.path = $cast[cstring](addr x.d_name)
      if result.path notin [".", ".."]:
        let path = dir / result.path
        if not relative:
          result.path = path

        template getSymlinkFileKind(path: string) =
          var s: Stat
          assert(path != "")
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
          if lstat(path.cstring, result.stat.get) < 0'i32: continue  # don't yield
          elif S_ISDIR(result.stat.unsafeGet.st_mode):
            result.kind = pcDir
          elif S_ISLNK(result.stat.unsafeGet.st_mode):
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
          else:   # assuming that field `d_type` is not present
            kSetGeneric()

        yield result

var printQueue = newStringOfCap(8192)
var printLock: Lock
var numFailed = 0 # To print often even if there's a lot of filtering but few matches
var numPrinted = 0 # If there's a low number of matches printing directly can be faster than batching
var numFound*: Atomic[int]
var numMatches*: int

{.push inline.}

func wrapHyperlink(path: Path, hyperlinkPrefix: string, encodedCwd: string, display = path.string): string =
  result = hyperlinkPrefix
  if not path.isAbsolute:
    result.add encodedCwd
  result.add encodeHyperlink(path.string)
  result.add "\e\\"
  result.add display
  when false: result.add "\e]8;;\e\\" # Hyperlinks are closed on exit

proc print(path: Path; behavior: RunOption; display = path.string) =
  template line: string =
    (if behavior.hyperlink: wrapHyperlink(path, behavior.hyperlinkPrefix, behavior.hyperlinkCwd, display)
     else: display) & (if behavior.null: '\0' else: '\n')
  {.gcsafe.}:
    if numPrinted < 8192:
      stdout.write line; stdout.flushFile()
      inc numPrinted
    else:
      acquire(printLock)
      if printQueue.len + line.len > 8192:
        let output = move(printQueue)
        release(printLock)
        stdout.write output & line
        stdout.flushFile()
        numFailed = 0
      else:
        printQueue.add line
        release(printLock)

proc notFoundPrint() =
  {.gcsafe.}:
    if printQueue.len > 0:
      inc numFailed
      if numFailed > 16384:
        withLock(printLock):
          stdout.write printQueue
          printQueue.setLen 0
        stdout.flushFile()
        numFailed = 0

template incFound: untyped =
  if behavior.maxFound != 0:
    if numFound.fetchAdd(1, moRelaxed) >= behavior.maxFound:
      return
  else: inc numMatches

template runFound(m: MasterHandle; behavior: RunOption; path: Path, found: Found, patterns: openArray[string]) =
  incFound()
  case behavior.action
  of plainPrint:
    print(path, behavior)
  of coloredPrint: ({.gcsafe.}:
    print(path, behavior, color(found, patterns)))
  of collect:
    findings.add(found)
  of exec:
    run(m, behavior.cmds, found)

{.pop inline.}

proc findDirRec(m: MasterHandle; dir, cwd: Path; patterns: openArray[string]; sensitive: bool; behavior: RunOption; depth: Positive) {.gcsafe.} =
  if behavior.maxFound != 0:
    if numFound.load(moRelaxed) >= behavior.maxFound:
      return

  template loop: untyped =
    template relPath(path: string): Path =
      (if isAbsolute(path) or dir.string in [".", "./"]: Path(path)
       else: dir / Path(path))

    template format(path: string): Path =
      if descendent.kind == pcLinkToDir: relPath(path) & '/'
      else: relPath(path)

    template wasFound(path: Path; found: seq[(int, int)]) =
      m.runFound(behavior, path, descendent.toFound(path, matches = found), patterns)

    template matchesExt(path: Path): bool =
      behavior.types.extensions.len == 0 or anyIt(behavior.types.extensions, path.string.endsWith(it))

    template match(path: Path) =
      if m.cancelled: return
      if matchesExt(path) and (
        let found = path.findPath(patterns, sensitive)
        found.len > 0):
          wasFound(path, found)
      elif behavior.action in {plainPrint, coloredPrint}:
        notFoundPrint()

    if behavior.exclude.len != 0:
      (var found = false; for x in behavior.exclude:
         if x.fullmatch:
           if pathMatches(absolutePath(Path descendent.path, cwd), x.pattern): (found = true; break)
         elif pathMatches(filename(descendent.path), x.pattern): (found = true; break)
       if found: continue)

    if descendent.kind == pcDir:
      if not behavior.searchAll and ignoreDir(descendent.path): continue
      let path = relPath(descendent.path) & '/'
      if behavior.followSymlinks:
        let absPath = absolutePath(path, cwd)
        if findings.seenOrIncl absPath: continue
      if behavior.maxDepth == 0 or depth + 1 <= behavior.maxDepth:
        m.spawn findDirRec(m, path, cwd, patterns, sensitive, behavior, depth + 1)
      if pcDir in behavior.types.kinds:
        match(path)

    elif behavior.followSymlinks and descendent.kind == pcLinkToDir:
      if not behavior.searchAll and ignoreDir(descendent.path): continue
      let path = relPath(descendent.path)
      var resolved = try: dir / Path(expandSymlink(path.string)) except: continue
      if resolved == Path("/"): continue # Special case this
      if resolved.string[^1] != '/': resolved &= '/'
      let absResolved = absolutePath(resolved, cwd)
      if (behavior.maxDepth == 0 or depth + 1 <= behavior.maxDepth) and not findings.seenOrIncl absResolved:
        m.spawn findDirRec(m, resolved, cwd, patterns, sensitive, behavior, depth + 1)

      if pcLinkToDir in behavior.types.kinds:
        match(path & '/')

    elif descendent.kind in behavior.types.kinds:
      let path = format(descendent.path)
      match(path)

  if behavior.action == coloredPrint:
    for descendent in dir.string.walkDirStat(relative = not isAbsolute(dir)):
      loop()
  else:
    for descendent in dir.string.walkDir(relative = not isAbsolute(dir)):
      loop()

var findMaster* = createMaster()
proc traverseFind*(paths: openArray[Path]; patterns: seq[string]; behavior: RunOption): seq[Found] =
  let sensitive = patterns.containsAny({'A'..'Z'})
  let cwd = getCurrentDir()
  findMaster.awaitAll:
    for i, path in paths:
      let info = getFileInfo(path.string)
      if info.kind == pcDir:
        findMaster.spawn findDirRec(getHandle findMaster, path, cwd, patterns, sensitive, behavior, 1)

      elif info.kind in behavior.types.kinds:
        let found = path.findPath(patterns, sensitive)
        if found.len > 0:
          incFound()
          template getFound: Found =
            if behavior.action == coloredPrint and info.kind == pcLinkToFile:
                var s: Stat; let broken = stat(cstring path.string, s) < 0'i32
                Found(path: path, kind: pcLinkToFile, matches: found, broken: broken)
            else: Found(path: path, kind: info.kind, matches: found)
          getHandle(findMaster).runFound(behavior, path, getFound(), patterns)
        elif behavior.action in {plainPrint, coloredPrint}:
          notFoundPrint()

  if not findMaster.cancelled:
    case behavior.action
    of plainPrint, coloredPrint:
      if printQueue.len > 0: stdout.write printQueue; stdout.flushFile()
    of collect: result &= findings.found.value
    else: discard
