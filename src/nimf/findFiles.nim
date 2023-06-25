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

import ./find, std/[os, paths, locks, sugar], pkg/malebolgia
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

proc `&`(p: Path, c: char): Path {.inline, borrow.}

proc contains(strings: openArray[string], c: char): bool {.inline.} =
  for s in strings:
    if c in s: return true
  result = false

func findBefore(text, pattern: openArray[char], start = 0.Natural, last: Natural, blacklist: set[char]): int {.inline.} =
  ## Finds text in a path before any character in `blacklist`
  for i in start..last:
    if text.continuesWith(pattern, i):
      return i
    if text[i] in blacklist: break
  result = -1

func findBefore(text, pattern: openArray[char], start = 0.Natural, blacklist: set[char]): int {.inline.} =
  text.findBefore(pattern, start, text.len - pattern.len, blacklist)

proc findPath*(path: sink Path, patterns: openArray[string]): seq[int] =
  ## Variant of `find` which only searches the filename with your pattern that follows any patterns containing '/'
  if patterns.len == 0: return @[]
  if patterns.len == 1 and patterns[0].len == 0: return @[0]

  var lastPatternSlash =
    block body:
      var result = -1
      for i in countdown(patterns.high, patterns.low):
        if '/' in patterns[i].string: result = i; break
      result
  var lastPathSlash = path.string.rfind("/")
  if lastPathSlash == path.string.high and path.string.len > 1: # Skip trailing '/'
    lastPathSlash = path.string.rfind("/", path.string.high - 1)

  result = newSeqUninitialized[int](patterns.len)
  var start = 0
  var lastPathPart = false
  var betweenDirMatch = false
  for i in 0..patterns.high:
    if patterns[i].len == 0:
      result[i] = start
    else:
      if not lastPathPart:
        if i > lastPatternSlash:
          start = lastPathSlash + 1
          lastPathPart = true
      if start > path.string.high: return @[]
      result[i] = if not betweenDirMatch: path.string.find(patterns[i], start)
                  else: path.string.findBefore(patterns[i], start, blacklist = {'/'})
      if result[i] == -1: return @[]
      betweenDirMatch = not lastPathPart and not (patterns[i][^1] == '/')
      start = result[i] + patterns[i].len
  if not lastPathPart and (lastPatternSlash != patterns.high or path.string.find("/", start) != -1): result = @[]

proc traverseFindDir(m: MasterHandle, dir: Path, patterns: openArray[string], kinds: set[PathComponent]) {.gcsafe.} =
  let absolute = isAbsolute(dir)
  for descendent in dir.string.walkDir(relative = not absolute):

    template formatPath(): Path =
      if absolute or dir.string in [".", "./"]: Path(descendent.path)
      else: dir / Path(descendent.path)

    template addFound() =
      {.gcsafe.}:
        acquire(findings.lock)
        findings.found.add Found(path: path, kind: descendent.kind, matches: found)
        release(findings.lock)

    if descendent.kind == pcDir:
      let path = formatPath() & '/'
      if pcDir in kinds:
        let found = path.findPath(patterns)
        if found.len > 0:
          addFound()
      m.spawn traverseFindDir(m, path, patterns, kinds)

    elif descendent.kind in kinds:
      let path = formatPath()
      let found = path.findPath(patterns)
      if found.len > 0:
        addFound()

proc stripDot(p: Path): Path {.inline.} =
  if p.string.len > 2 and p.string[0..1] == "./": Path(p.string[2..^1])
  else: p

func containsAny(strings: openArray[string], chars: set[char]): bool {.inline.} =
  for s in strings:
    for c in s:
      if c in chars: return true
  result = false

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
          result.add Found(path: path.stripDot, kind: pcFile, matches: found)
  result &= findings.found

proc traverseFind*(paths: openArray[Path], patterns: seq[string]): seq[Found] {.inline.} =
  ## Decides to match directories based on if the pattern
  traverseFind(paths, patterns, {pcFile, pcDir, pcLinkToFile, pcLinkToDir})
