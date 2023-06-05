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

import ./paths, pkg/cligen, std/terminal
from std/os import isAbsolute, fileExists, dirExists
from std/strutils import startsWith, endsWith
export cligen

proc cliFind*(color = true, input: seq[string]): int =
  var patterns: seq[string]
  var paths: seq[Path]
  if input.len >= 1:
    if dirExists(input[0]):
      paths.add Path(input[0])
    else:
      patterns.add input[0].split(' ')
    for i in 1..input.high:
      let arg = input[i] 
      if (dirExists(arg) or fileExists(arg)) and arg notin cast[seq[string]](paths):
        paths.add Path(arg) # Make it different based on if it's in the current directory?
      else:
        patterns &= arg.split(' ')
  if patterns.len == 0: patterns = @[""]
  if paths.len == 0: paths = @[Path(".")]

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
