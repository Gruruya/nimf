# nimf --- Text finder
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
#
# This file is part of nimf.
#
# nimf is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, version 3 of the License.
#
# nimf is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with nimf.  If not, see <http://www.gnu.org/licenses/>.

## File path finding

import ./find, std/[os, paths, locks, posix], pkg/malebolgia, pkg/adix/[lptabz, althash]
from std/strutils import split
from std/sequtils import filterIt

proc `&`(p: Path; c: char): Path {.inline, borrow.}
proc `&=`(x: var Path; y: char) {.inline.} = x = Path(x.string & y)
proc hash(x: Path): Hash {.inline, borrow.}

type
  Found* = object
    path*: Path
    matches*: seq[(int, int)]
    case kind*: PathComponent
    of pcFile:
      stat*: Stat
    of pcLinkToFile:
      broken*: bool
    else: discard
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

proc findPath*(path: sink Path; patterns: openArray[string]): seq[(int, int)] =
  ## Variant of `find` which searches the filename for patterns following the last pattern with a directory separator
  ## Also has `*` globbing
  if patterns.len == 0: return @[]

  var filenameSep = -1
  for i in countdown(patterns.high, patterns.low):
    if '/' in patterns[i]:
      filenameSep = i
      break
  var lastSep = path.string.rfind("/", last = path.string.high - 1)

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
      let glob = '*' in pattern
      if glob:
        let patterns = pattern.split('*').filterIt(it.len > 0)
        var j = patterns.high
        while true:
          if j < 0: break
          elif patterns[j].len == 0: dec j; continue

          let found = smartrfind(path.string, patterns[j], start = if i > filenameSep: lastSep else: 0, last)
          if found == -1: return @[]

          result[i][0] = found - patterns[j].high
          last = result[i][0] - 1

          if result[i][1] == 0:
            if pattern[^1] in {'*', '/'} or path.string[found + 1] == '/' or found == path.string.high:
              dec j
              if result[i][1] == 0: result[i][1] = found
          elif j == patterns.low:
            if pattern[0] in {'*', '/'} or result[i][0] == 0 or path.string[last] == '/':
              break
          else:
            dec j
      else:
        result[i][1] = smartrfind(path.string, pattern, start = if i > filenameSep: lastSep else: 0, last)
        if result[i][1] == -1: return @[]
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
          if stat(path.string, s) == 0'i32:
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


proc findDirRec(m: MasterHandle; dir: Path; patterns: openArray[string]; kinds: set[PathComponent]; followSymlinks: bool) {.gcsafe.} =
  let absolute = isAbsolute(dir)
  for descendent in dir.string.walkDirStat(relative = not absolute):
    template format(path: Path): Path =
      if absolute or dir.string in [".", "./"]: path
      else: dir / path

    template absolute(path: Path): Path =
      if absolute: path
      else: absolutePath(path)

    if descendent.kind == pcDir:
      var path = format(descendent.path) & '/'
      if followSymlinks:
        let absPath = path.absolute
        if findings.seenOrIncl absPath: continue
      m.spawn findDirRec(m, path, patterns, kinds, followSymlinks)
      if pcDir in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          findings.add descendent.toFound(path, matches = found)

    elif followSymlinks and descendent.kind == pcLinkToDir:
      let path = format(descendent.path)
      var resolved = Path(expandSymlink(path.string))
      if resolved == Path("/"): continue # Special case this
      var absResolved = absolute(resolved)
      if absResolved.string[^1] != '/': absResolved &= '/'
      if resolved.string[^1] != '/': resolved &= '/'
      if not findings.seenOrIncl absResolved:
        m.spawn findDirRec(m, resolved, patterns, kinds, followSymlinks)

      if pcLinkToDir in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          findings.add descendent.toFound(path, matches = found)

    elif descendent.kind in kinds:
      let path = format(descendent.path)
      let found = path.findPath(patterns)
      if found.len > 0:
        findings.add descendent.toFound(path, matches = found)

proc stripDot(p: Path): Path {.inline.} =
  if p.string.len > 2 and p.string[0..1] == "./": Path(p.string[2..^1])
  else: p

proc traverseFind*(paths: openArray[Path]; patterns: seq[string]; kinds = {pcFile, pcDir, pcLinkToFile, pcLinkToDir}; followSymlinks = false): seq[Found] =
  var m = createMaster()
  m.awaitAll:
    for i, path in paths:
      let info = getFileInfo(path.string)
      if info.kind == pcDir:
        m.spawn findDirRec(getHandle m, path, patterns, kinds, followSymlinks)
      elif info.kind in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          case info.kind
          of pcFile:
            var s: Stat
            if lstat(cstring path.string, s) < 0'i32: continue
            result.add Found(path: path.stripDot, kind: pcFile, matches: found, stat: s)
          of pcLinkToFile:
            var s: Stat
            let broken = stat(cstring path.string, s) < 0'i32
            result.add Found(path: path.stripDot, kind: pcLinkToFile, matches: found, broken: broken)
          else: result.add Found(path: path.stripDot, kind: info.kind, matches: found)
  result &= findings.found.paths
