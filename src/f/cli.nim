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

import ./[find, findFiles], pkg/[cligen, malebolgia], std/[terminal, paths, macros]
import std/os except getCurrentDir
from std/strutils import startsWith, endsWith, multiReplace
from std/sequtils import anyIt
export cligen

proc isChildOf(path, potParent: string): bool =
  let aPotParent = absolutePath(Path(potParent))
  let aPath = absolutePath(Path(path))
  if aPath == aPotParent:
    return true
  for parent in aPath.parentDirs:
    if aPotParent == parent: return true
  result = false

proc stripExtension(path: Path): Path =
  let (dir, name, _) = path.splitFile
  dir / name

template mapIt[T](collection: openArray[T], op: untyped): seq =
  type OutType = typeof((block:
    var i{.inject, used.}: int;
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
      proc alreadyAdded(arg: string): bool =
        anyIt(cast[seq[string]](paths), arg.isChildOf(it))
      if arg.startsWith("./"):
        if (arg.endsWith('/') and dirExists(arg)) or (not arg.alreadyAdded and (dirExists(arg) or fileExists(arg))):
          paths.add Path(arg)
        else:
          for path in walkPattern(if '*' in arg: arg else: arg & '*'):
            if not path.alreadyAdded:
              paths.add Path(path)
      elif (arg.endsWith('/') and dirExists(arg)) or (not arg.alreadyAdded and (absolutePath(Path(arg.parentDir)) != getCurrentDir() and (dirExists(arg) or fileExists(arg)))):
        paths.add Path(arg)
      else:
        patterns &= arg.split(' ')
  if patterns.len == 0: patterns = @[""]
  if paths.len == 0: paths = @[Path(".")]
  when defined(debug):
    echo patterns
    echo repr paths

  let findings = find(paths, patterns)
  if exec.len > 0:
    var m = createMaster()
    proc run(cmd: string) = discard execShellCmd(cmd)
    m.awaitAll:
      const targets = ["{}", "{/}", "{//}", "{/.}", "{.}"]
      var paths, filenames, parentDirs, noExtFilenames, noExtPaths = newSeq[string]()
      var pathsString, filenamesString, parentDirsString, noExtFilenamesString, noExtPathsString = ""
      template needs[T](variable: var T, constructor: T) =
        if variable.len == 0: variable = constructor
      template addFindExeReplacements() =
        for t in targets.low..targets.high:
          if allIndexes[t].len > 0:
            case t
            of 0: addReplacement(targets[t], paths, mapIt(findings, it.path.string.quoteShell))
            of 1: addReplacement(targets[t], filenames, mapIt(findings, it.path.lastPathPart.string))
            of 2: addReplacement(targets[t], parentDirs, mapIt(findings, it.path.parentDir.string))
            of 3: addReplacement(targets[t], noExtFilenames, mapIt(findings, if it.kind == pcDir: needs(filenames, mapIt(findings, it.path.lastPathPart.string)); filenames[i] else: it.path.splitFile[1].string))
            of 4: addReplacement(targets[t], noExtPaths, mapIt(findings, it.path.stripExtension.string))
      for cmd in exec:
        let allIndexes = cmd.findAll(targets)
        var combined = cmd.endsWith '+'
        if combined:
          let cmd = cmd[0..^2]
          var replacements = newSeqOfCap[(string, string)](targets.len)
          macro addReplacement[T](toReplace: T, variable: var openArray[T], constructor: openArray[T]) =
            let variableString = ident($variable & "String")
            quote do:
              needs(`variable`, `constructor`)
              needs(`variableString`, `variable`.join(" "))
              replacements.add (`toReplace`, `variableString`)
          addFindExeReplacements()
          if replacements.len == 0:
            needs(paths, mapIt(findings, it.path.string.quoteShell))
            needs(pathsString, paths.join(" "))
            m.spawn run cmd & ' ' & pathsString
          else:
            m.spawn run cmd.multiReplace(replacements)
        else:
          for i in findings.low..findings.high:
            var replacements = newSeqOfCap[(string, string)](targets.len)
            template addReplacement[T](toReplace: T, variable: var openArray[T], constructor: openArray[T]) =
              needs(variable, constructor)
              replacements.add (toReplace, variable[i])
            addFindExeReplacements()
            if replacements.len == 0:
              needs(paths, mapIt(findings, it.path.string.quoteShell))
              m.spawn run cmd & ' ' & paths[i]
            else:
              m.spawn run cmd.multiReplace(replacements)
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
