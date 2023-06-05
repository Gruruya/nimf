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

template mapIt[T](collection: openArray[T], op: untyped): seq =
  type OutType = typeof((block:
    var i{.inject.}: int;
    var it{.inject.}: typeof(items(collection), typeOfIter);
    op), typeOfProc)
  var result = newSeqOfCap[OutType](collection.len)
  for i {.inject.}, it {.inject.} in collection:
    result.add op
  result

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
      let
        paths = mapIt(findings, it.path.string.quoteShell)
        filenames = mapIt(findings, it.path.lastPathPart.string)
        parentDirs = mapIt(findings, it.path.parentDir.string)
        noExtFilenames = mapIt(findings, if it.kind == pcDir: filenames[i] else: it.path.splitFile[1].string)
        noExtPaths = mapIt(findings, it.path.stripExtension.string)
      template runCmd(): untyped =
        for inCmd in exec:
          for i in findings.low..findings.high:
            var cmd = inCmd.multiReplace(("{}", paths[i]),
                                         ("{/}", filenames[i]),
                                         ("{//}", parentDirs[i]),
                                         ("{/.}", noExtFilenames[i]),
                                         ("{.}", noExtPaths[i]))
            if cmd == inCmd: cmd = inCmd & ' ' & paths[i]
            m.spawn run cmd
      if not anyIt(exec, it.endsWith '+'):
        runCmd()
      else:
        let
          pathsString = paths.join(" ")
          filenamesString = filenames.join(" ")
          parentDirsString = parentDirs.join(" ")
          noExtFilenamesString = noExtFilenames.join(" ")
          noExtPathsString = noExtPaths.join(" ")
        for inCmd in exec:
          if inCmd.endsWith '+': 
            let inCmd = inCmd[0..^2]
            var cmd = inCmd.multiReplace(("{}", pathsString),
                                         ("{/}", filenamesString),
                                         ("{//}", parentDirsString),
                                         ("{/.}", noExtFilenamesString),
                                         ("{.}", noExtPathsString))
            if cmd == inCmd: cmd = inCmd & ' ' & pathsString
            m.spawn run cmd
          else:
            runCmd()
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
