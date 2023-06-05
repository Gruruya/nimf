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

import ./paths, pkg/[cligen, malebolgia], std/[terminal, paths, osproc]
from std/os import fileExists, dirExists, quoteShell, execShellCmd
from std/strutils import startsWith, endsWith, replace
from std/sequtils import anyIt
export cligen

proc isChildOf(path, potParent: string): bool =
  let aPotParent = absolutePath(Path(potParent))
  for parent in Path(path).absolutePath.parentDirs:
    if aPotParent == parent: return true
  result = false

proc cliFind*(color = true, exec: seq[string] = @[], input: seq[string]): int =
  var patterns: seq[string]
  var paths: seq[Path]
  if input.len >= 1:
    for i in 0..input.high:
      let arg = input[i]
      if (dirExists(arg) and (arg.endsWith('/') or not anyIt(cast[seq[string]](paths), arg.isChildOf(it)))) or ((arg.startsWith("./") or absolutePath(Path(arg.parentDir)) != getCurrentDir()) and fileExists(arg)):
        paths.add Path(arg) # Glob all directories/allow shorthand like ./m for ./man
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
    if exec.len > 0:
      var outputs = newSeq[int](exec.len)
      var m = createMaster()
      m.awaitAll:
        for i, cmd in exec:
          var cmd = cmd
          var curlyFound = false
          block replaceCurly:
            var i = 0
            while true:
              if cmd[i] == '{' and cmd[i + 1] == '}':
                if cmd.len > i + 1:
                  cmd = cmd[0..<i] & path & cmd[i + 2..^1]
                else: cmd = cmd[0..<i] & path
                curlyFound = true
                inc i, 2
              else:
                inc i
              if i > cmd.len - "{}".len: break
          if not curlyFound: cmd = cmd & ' ' & path.quoteShell
          m.spawn execShellCmd(cmd) -> outputs[i]

    elif color:
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
  dispatch(cliFind, short = {"exec": 'x'})
