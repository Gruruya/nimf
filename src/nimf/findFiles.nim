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

proc stripDot(p: Path): Path {.inline.} =
  if p.string.len > 2 and p.string[0..1] == "./": Path(p.string[2..^1])
  else: p

proc findDirRec(m: MasterHandle, dir: Path, patterns: openArray[string], kinds: set[PathComponent]) {.inline, gcsafe.} =
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
      let path = Path(formatPath().string & '/')
      if pcDir in kinds:
        let found = descendent.path.lastPathPart.find(patterns)
        if found.len > 0:
          addFound()
      m.spawn findDirRec(m, path, patterns, kinds)

    elif descendent.kind in kinds:
      let found = descendent.path.lastPathPart.find(patterns)
      if found.len > 0:
        let path = formatPath()
        addFound()

proc findFiles*(paths: openArray[Path], patterns: openArray[string], kinds = {pcFile, pcDir, pcLinkToFile, pcLinkToDir}): seq[Found] =
  var m = createMaster()
  m.awaitAll:
    for i, path in paths:
      let info = getFileInfo(cast[string](path))
      if info.kind == pcDir:
        m.spawn findDirRec(getHandle m, path, patterns, kinds)
      elif info.kind in kinds:
        let found = path.string.lastPathPart.find(patterns)
        if found.len > 0:
          result.add Found(path: path.stripDot, kind: pcFile, matches: found)
  result &= findings.found
