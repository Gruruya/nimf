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

import ./find, std/[os, paths, locks], pkg/malebolgia, pkg/adix/[lptabz, althash]
export Path

proc `&`(p: Path; c: char): Path {.inline, borrow.}
proc `&=`(x: var Path; y: char) {.inline.} = x = Path(x.string & y)
proc hash(x: Path): Hash {.inline, borrow.}

type
  Found* = object
    path*: Path
    kind*: PathComponent
    matches*: seq[int]
  Findings = object
    found*: tuple[paths: seq[Found], lock: Lock]
    dirs*: tuple[paths: LpSetz[Path, int8, 6], lock: Lock]

proc init(_: typedesc[Findings]): Findings =
  result.dirs.paths = initLpSetz[Path, int8, 6]()
  initLock(result.found.lock)
  initLock(result.dirs.lock)

template withLock(lock: Lock; body: untyped): untyped =
  acquire(lock)
  {.gcsafe.}:
    try:
      body
    finally:
      release(lock)

proc addImpl(findings: var Findings; found: Found) {.inline.} =
  withLock(findings.found.lock):
    findings.found.paths.add found

proc seenOrInclImpl(findings: var Findings; dir: Path): bool {.inline.} =
  withLock(findings.dirs.lock):
    result = findings.dirs.paths.containsOrIncl dir

template add(findings: var Findings; found: Found) = {.gcsafe.}: addImpl(findings, found)
template seenOrIncl(findings: var Findings; dir: Path): bool = {.gcsafe.}: seenOrInclImpl(findings, dir)

var findings = Findings.init()

proc findPath*(path: sink Path; patterns: openArray[string]): seq[int] =
  ## Variant of `find` which only searches the filename with your pattern that follows any patterns containing '/'
  if patterns.len == 0: return @[]

  var separator = -1
  for i in countdown(patterns.high, patterns.low):
    if '/' in patterns[i]:
      separator = i
      break
  var lastSep = path.string.rfind("/", last = path.string.high - 1)

  result = newSeqUninitialized[int](patterns.len)
  var last = path.string.high
  let sensitive = patterns.containsAny({'A'..'Z'})
  template smartrfind(args: varargs[untyped]): untyped =
    if sensitive: rfind(args) else: rfindI(args)

  for i in countdown(patterns.high, patterns.low):
    if patterns[i].len == 0:
      result[i] = 0
    else:
      result[i] = smartrfind(path.string, patterns[i], start = if i > separator: lastSep else: 0, last)
      if result[i] == -1: return @[]
      last = result[i] - patterns[i].len

proc traverseFindDir(m: MasterHandle; dir: Path; patterns: openArray[string]; kinds: set[PathComponent]; followSymlinks: bool) {.gcsafe.} =
  let absolute = isAbsolute(dir)
  for descendent in dir.string.walkDir(relative = not absolute):
    template format(path: string): Path =
      if absolute or dir.string in [".", "./"]: Path(path)
      else: dir / Path(path)

    template absolute(path: Path): Path =
      if absolute: path
      else: absolutePath(path)

    if descendent.kind == pcDir:
      var path = format(descendent.path) & '/'
      if followSymlinks:
        let absPath = path.absolute
        if findings.seenOrIncl absPath: continue
      m.spawn traverseFindDir(m, path, patterns, kinds, followSymlinks)
      if pcDir in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          findings.add Found(path: path, kind: descendent.kind, matches: found)

    elif followSymlinks and descendent.kind == pcLinkToDir:
      let path = format(descendent.path)
      var resolved = Path(expandSymlink(path.string))
      if resolved == Path("/"): continue # Special case this
      var absResolved = absolute(resolved)
      if absResolved.string[^1] != '/': absResolved &= '/'
      if resolved.string[^1] != '/': resolved &= '/'
      if not findings.seenOrIncl absResolved:
        m.spawn traverseFindDir(m, resolved, patterns, kinds, followSymlinks)

      if pcLinkToDir in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          findings.add Found(path: path, kind: descendent.kind, matches: found)

    elif descendent.kind in kinds:
      let path = format(descendent.path)
      let found = path.findPath(patterns)
      if found.len > 0:
        findings.add Found(path: path, kind: descendent.kind, matches: found)

proc stripDot(p: Path): Path {.inline.} =
  if p.string.len > 2 and p.string[0..1] == "./": Path(p.string[2..^1])
  else: p

proc traverseFind*(paths: openArray[Path]; patterns: seq[string]; kinds = {pcFile, pcDir, pcLinkToFile, pcLinkToDir}; followSymlinks = false): seq[Found] =
  var m = createMaster()
  m.awaitAll:
    for i, path in paths:
      let info = getFileInfo(path.string)
      if info.kind == pcDir:
        m.spawn traverseFindDir(getHandle m, path, patterns, kinds, followSymlinks)
      elif info.kind in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          result.add Found(path: path.stripDot, kind: info.kind, matches: found)
  result &= findings.found.paths
