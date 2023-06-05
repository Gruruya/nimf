# f --- Text finder
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
#
# This file is part of f.
#
# f is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, version 3 of the License.
#
# f is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with f.  If not, see <http://www.gnu.org/licenses/>.

## File path finding

import ./find, std/[os, paths, locks], pkg/malebolgia
export Path, parentDir, lastPathPart, PathComponent, paths.getCurrentDir

type
  Findings = object
    found: seq[(Path, seq[int], PathComponent)]
    lock: Lock

var findings = Findings()
initLock(findings.lock)

proc findDirRec(m: MasterHandle, dir: Path, patterns: seq[string]) {.gcsafe.} =
  for descendent in dir.string.walkDir(relative = not isAbsolute(dir)):
    case descendent.kind
    of pcFile:
      let found = descendent.path.lastPathPart.find(patterns)
      if found.len > 0:
       {.gcsafe.}:
         acquire(findings.lock)
         findings.found.add (dir / Path(descendent.path), found, pcFile)
         release(findings.lock)
    of pcDir:
      let found = descendent.path.lastPathPart.find(patterns)
      if found.len > 0:
       {.gcsafe.}:
         acquire(findings.lock)
         findings.found.add (dir / Path(descendent.path), found, pcDir)
         release(findings.lock)
      if isAbsolute(dir):
        m.spawn findDirRec(m, Path(descendent.path), patterns)
      else:
        m.spawn findDirRec(m, dir / Path(descendent.path), patterns)
    else:
      discard

proc find*(paths: seq[Path], patterns: seq[string]): seq[(Path, seq[int], PathComponent)] =
  var m = createMaster()
  m.awaitAll:
    for i, path in paths:
      let info = getFileInfo(cast[string](path))
      case info.kind
      of pcFile:
        let found = path.string.lastPathPart.find(patterns)
        if found.len > 0:
          result.add @[(path, found, pcFile)]
      of pcDir:
        m.spawn findDirRec(getHandle m, path, patterns)
      of pcLinkToFile:
        discard
      of pcLinkToDir:
        discard
  result &= findings.found
