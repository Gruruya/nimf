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

import ./findFiles, pkg/[cligen, malebolgia], std/[terminal, paths]
import std/os except getCurrentDir
from std/strutils import startsWith, endsWith, multiReplace
from std/sequtils import anyIt
export cligen

proc isChildOf(path, potParent: string): bool =
  let aPotParent = absolutePath(Path(potParent))
  for parent in Path(path).absolutePath.parentDirs:
    if aPotParent == parent: return true
  result = false

proc stripExtension(path: Path): Path =
  let (dir, name, _) = path.splitFile
  dir / name

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
    echo repr paths

  let findings = find(paths, patterns)
  if exec.len > 0:
    var outputs = newSeq[int](exec.len)
    var m = createMaster()
    proc run(cmd: string) = discard execShellCmd(cmd)
    m.awaitAll:
      for i, inCmd in exec:
        for found in findings:
          let path = found.path
          var cmd = inCmd.multiReplace(("{}", path.string.quoteShell),
                                       ("{/}", path.lastPathPart.string),
                                       ("{//}", path.parentDir.string),
                                       ("{/.}", if found.kind == pcDir: path.lastPathPart.string else: path.splitFile[1].string),
                                       ("{.}", path.stripExtension.string))
          if cmd == inCmd: cmd = inCmd & ' ' & path.string.quoteShell()
          m.spawn run cmd
  else:
    for found in findings:
      let path = found.path.string
      if color:
        let parent = path[0 ..< path.len - path.lastPathPart.len - (if found.kind == pcDir: 1 else: 0)]
        stdout.setForegroundColor(fgBlue)
        stdout.setStyle({styleBright})
        stdout.write parent
        if found.kind != pcDir:
          stdout.resetAttributes()
        var start = parent.len
        for i in 0..found.matches.high:
          let colorStart = found.matches[i] + parent.len
          let colorEnd = colorStart + patterns[i].high
          stdout.write path[start ..< colorStart]
          stdout.styledWrite styleBright, fgRed, path[colorStart..colorEnd]
          if found.kind == pcDir:
            stdout.setForegroundColor(fgBlue)
            stdout.setStyle({styleBright})
          start = colorEnd + 1
        if start != path.len:
          stdout.write path[start..path.high]
        stdout.write '\n'
      else:
        echo path

when isMainModule:
  dispatch(cliFind, short = {"exec": 'x'})
