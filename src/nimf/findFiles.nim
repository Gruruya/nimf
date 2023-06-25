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

import ./find, std/[os, paths, locks], pkg/malebolgia
export Path

type
  Found* = object
    path*: Path
    kind*: PathComponent
    matches*: seq[int]
  Findings = object
    found: seq[Found]
    lock: Lock

var findings = Findings()
initLock(findings.lock)

proc addImpl(findings: var Findings, found: Found) {.inline.} =
  acquire(findings.lock)
  findings.found.add found
  release(findings.lock)

template add(findings: var Findings, found: Found) =
  {.gcsafe.}: addImpl(findings, found)

proc `&`(p: Path, c: char): Path {.inline, borrow.}

proc contains(strings: openArray[string], c: char): bool {.inline.} =
  for s in strings:
    if c in s: return true
  result = false

proc findPath*(path: sink Path, patterns: openArray[string]): seq[int] =
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

proc traverseFindDir(m: MasterHandle, dir: Path, patterns: openArray[string], kinds: set[PathComponent]) {.gcsafe.} =
  let absolute = isAbsolute(dir)
  for descendent in dir.string.walkDir(relative = not absolute):

    template formatPath(): Path =
      if absolute or dir.string in [".", "./"]: Path(descendent.path)
      else: dir / Path(descendent.path)

    if descendent.kind == pcDir:
      let path = formatPath() & '/'
      m.spawn traverseFindDir(m, path, patterns, kinds)
      if pcDir in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          findings.add Found(path: path, kind: descendent.kind, matches: found)

    elif descendent.kind in kinds:
      let path = formatPath()
      let found = path.findPath(patterns)
      if found.len > 0:
        findings.add Found(path: path, kind: descendent.kind, matches: found)

proc stripDot(p: Path): Path {.inline.} =
  if p.string.len > 2 and p.string[0..1] == "./": Path(p.string[2..^1])
  else: p

proc traverseFind*(paths: openArray[Path], patterns: seq[string], kinds: set[PathComponent]): seq[Found] =
  var m = createMaster()
  m.awaitAll:
    for i, path in paths:
      let info = getFileInfo(cast[string](path))
      if info.kind == pcDir:
        m.spawn traverseFindDir(getHandle m, path, patterns, kinds)
      elif info.kind in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          result.add Found(path: path.stripDot, kind: info.kind, matches: found)
  result &= findings.found

proc traverseFind*(paths: openArray[Path], patterns: seq[string]): seq[Found] {.inline.} =
  ## Decides to match directories based on if the pattern
  traverseFind(paths, patterns, {pcFile, pcDir, pcLinkToFile, pcLinkToDir})
