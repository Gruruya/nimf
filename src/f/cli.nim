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
from std/strutils import startsWith, endsWith, replace
from std/sequtils import anyIt
from std/posix import sysconf, SC_ARG_MAX # Could make Windows compatible, according to ChatGPT the general limit on there is 32767
from std/envvars import envPairs
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
    var i{.inject.}: int;
    var it{.inject.}: typeof(items(collection), typeOfIter);
    op), typeOfProc)
  var result = newSeqOfCap[OutType](collection.len)
  for i {.inject.}, it {.inject.} in collection:
    result.add op
  result

proc countEnvLen(): int =
  for key, value in envPairs():
    result += key.len   # VARIABLE
    result += 2         # \0=
    result += value.len # value
    result += 1         # \0

proc cliFind*(color = true, exec: seq[string] = @[], input: seq[string]): int =
  var patterns: seq[string]
  var paths: seq[Path]
  if input.len >= 1:
    for i in 0..input.high:
      let arg = input[i]
      proc alreadyAdded(arg: string): bool =
        anyIt(cast[seq[string]](paths), arg.isChildOf(it))
      proc isDir(arg: string): bool =
        dirExists(arg) and (arg.endsWith('/') or not arg.alreadyAdded)
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
      template needsIt[T](variable: var T, constructor: untyped) =
        if variable.len == 0: variable = constructor
      template makeFindExeReplacements() =
        for t in targets.low..targets.high:
          if allIndexes[t].len > 0:
            case t
            of 0: replaceIt(targets[t], paths, mapIt(findings, it.path.string.quoteShell))
            of 1: replaceIt(targets[t], filenames, mapIt(findings, it.path.lastPathPart.string))
            of 2: replaceIt(targets[t], parentDirs, mapIt(findings, it.path.parentDir.string))
            of 3: replaceIt(targets[t], noExtFilenames, mapIt(findings, if it.kind == pcDir: needsIt(filenames, mapIt(findings, it.path.lastPathPart.string)); filenames[i] else: it.path.splitFile[1].string))
            of 4: replaceIt(targets[t], noExtPaths, mapIt(findings, it.path.stripExtension.string))
      for inCmd in exec:
        let allIndexes = inCmd.findAll(targets)
        var combined = inCmd.endsWith '+'
        if combined:
          var cmd = inCmd[0..^2]
          macro replaceIt[T](toReplace: untyped, variable: var T, constructor: untyped) =
            let variableString = ident($variable & "String")
            quote do:
              needsIt(`variable`, `constructor`)
              needsIt(`variableString`, `variable`.join(" "))
              cmd = cmd.replace(`toReplace`, `variableString`)
          makeFindExeReplacements()
          if cmd == inCmd[0..^2]:
            needsIt(paths, mapIt(findings, it.path.string.quoteShell))
            needsIt(pathsString, paths.join(" "))
            cmd = inCmd[0..^2] & ' ' & pathsString
          m.spawn run cmd
        else:
          for i in findings.low..findings.high:
            var cmd = inCmd
            template replaceIt[T](toReplace: untyped, variable: var T, constructor: untyped) =
              needsIt(variable, constructor)
              cmd = cmd.replace(toReplace, variable[i])
            makeFindExeReplacements()
            if cmd == inCmd:
              needsIt(paths, mapIt(findings, it.path.string.quoteShell))
              cmd = inCmd & ' ' & paths[i]
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
