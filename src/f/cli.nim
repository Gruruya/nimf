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

import sugar

import ./find, pkg/[cligen, malebolgia], std/[terminal, exitprocs, os, paths]
from std/strutils import endsWith, removePrefix
from std/sugar import dup
export cligen

type CliParams = object
  input: seq[string]
  color = true

proc display(p: CliParams, path: string, patterns: seq[string], found: seq[int], kind: PathComponent) =
  if p.color:
    let parent = path[0 ..< path.len - path.lastPathPart.len]
    if kind == pcDir or parent != "./":
      stdout.setForegroundColor(fgBlue)
      stdout.setStyle({styleBright})
      stdout.write parent.dup(removePrefix("./"))
      if kind != pcDir:
        stdout.resetAttributes()
    var start = parent.len
    for i in 0..found.high:
      let colorStart = found[i] + parent.len
      let colorEnd = colorStart + patterns[i].high
      stdout.write path[start ..< colorStart]
      stdout.styledWrite styleBright, fgRed, path[colorStart..colorEnd]
      if kind == pcDir:
        stdout.setForegroundColor(fgBlue)
        stdout.setStyle({styleBright})
      start = colorEnd + 1
    if start != path.len:
      stdout.write path[start..path.high]
    if kind == pcDir:
      stdout.write "/"
    stdout.write '\n'
  else:
    echo path

proc findDirRec(p: CliParams, m: MasterHandle, dir: string, patterns: seq[string]) {.gcsafe.} =
  ## Modified from ./paths to write directly to stdout rather than using state
  for descendent in dir.string.walkDir(relative = not isAbsolute(dir)):
    case descendent.kind
    of pcFile:
      let found = descendent.path.lastPathPart.find(patterns)
      if found.len > 0:
        p.display(dir / descendent.path, patterns, found, pcFile)
    of pcDir:
      let found = descendent.path.lastPathPart.find(patterns)
      if found.len > 0:
        p.display(dir / descendent.path, patterns, found, pcDir)
      if isAbsolute(dir):
        m.spawn p.findDirRec(m, descendent.path, patterns)
      else:
        m.spawn p.findDirRec(m, dir / descendent.path, patterns)
    else:
      discard

proc find(paths: seq[Path], patterns: seq[string], p: CliParams) =
  ## Modified from ./paths to write directly to stdout rather than using state
  var m = createMaster()
  m.awaitAll:
    for i, path in paths:
      let info = getFileInfo(cast[string](path))
      case info.kind
      of pcFile:
        let found = path.string.lastPathPart.find(patterns)
        if found.len > 0:
          p.display(path.string, patterns, found, pcFile)
      of pcDir:
        m.spawn p.findDirRec(getHandle m, path.string, patterns)
      of pcLinkToFile:
        discard
      else:
        discard

proc cliFind*() =
  exitprocs.addExitProc(resetAttributes)
  var p = initFromCL(CliParams(), positional = "input")
  var patterns: seq[string]
  var paths: seq[Path]
  if p.input.len >= 1:
    if dirExists(p.input[0]):
      paths.add Path(p.input[0])
    else:
      patterns.add p.input[0].split(' ')
    for i in 1..p.input.high:
      let arg = p.input[i] 
      if (dirExists(arg) or fileExists(arg)) and arg notin cast[seq[string]](paths):
        paths.add Path(arg) # Make it different based on if it's in the current directory?
      else:
        patterns &= arg.split(' ')
  if patterns.len == 0: patterns = @[""]
  if paths.len == 0: paths = @[Path(".")]
  paths.find(patterns, p)

when isMainModule:
  cliFind()
