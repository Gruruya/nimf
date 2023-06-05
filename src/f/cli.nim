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

## CLI for finding files

import ./paths, pkg/cligen, std/[terminal, paths]
from std/os import isAbsolute, fileExists, dirExists
from std/strutils import startsWith, endsWith
from std/sequtils import anyIt
export cligen

proc isChildOf(path, potParent: string): bool =
  let aPotParent = absolutePath(Path(potParent))
  for parent in Path(path).absolutePath.parentDirs:
    if aPotParent == parent: return true
  result = false

proc cliFind*(color = true, input: seq[string]): int =
  var patterns: seq[string]
  var paths: seq[Path]
  if input.len >= 1:
    for i in 0..input.high:
      let arg = input[i]
      if (dirExists(arg) and (arg.endsWith('/') or not anyIt(cast[seq[string]](paths), arg.isChildOf(it)))) or ((arg.startsWith("./") or absolutePath(Path(arg.parentDir)) != getCurrentDir()) and fileExists(arg)):
        paths.add Path(arg) # Allow duplicate directories if input ends with /
      else:
        patterns &= arg.split(' ')
  if patterns.len == 0: patterns = @[""]
  if paths.len == 0: paths = @[Path(".")]
  when defined(debug):
    echo patterns
    echo paths

  let findings = find(paths, patterns)
  for found in findings:
    let path = found[0].string
    if color:
      let parent = path[0 ..< path.len - path.lastPathPart.len]
      if found[2] == pcDir or parent != "./":
        stdout.setForegroundColor(fgBlue)
        stdout.setStyle({styleBright})
        stdout.write if parent.startsWith("./"): parent[2..^1] else: parent
        if found[2] != pcDir:
          stdout.resetAttributes()
      var start = parent.len
      for i in 0..found[1].high:
        let colorStart = found[1][i] + parent.len
        let colorEnd = colorStart + patterns[i].high
        stdout.write path[start ..< colorStart]
        stdout.styledWrite styleBright, fgRed, path[colorStart..colorEnd]
        start = colorEnd + 1
      if start != path.len:
        if found[2] == pcDir:
          stdout.styledWrite styleBright, fgBlue, path[start..path.high]
        else:
          stdout.write path[start..path.high]
      if found[2] == pcDir:
        stdout.styledWrite styleBright, fgBlue, "/"
      stdout.write '\n'
    else:
      echo path

when isMainModule:
  dispatch(cliFind)
