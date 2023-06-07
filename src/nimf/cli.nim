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

## CLI for finding files

import ./[find, findFiles], pkg/[cligen, malebolgia], std/[terminal, paths, macros]
import std/os except getCurrentDir
from std/strutils import startsWith, endsWith, multiReplace
from std/sequtils import anyIt, mapIt
from std/typetraits import enumLen
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

template mapEnumeratedIt[T](collection: openArray[T], op: untyped): seq =
  type OutType = typeof((block:
    var i{.inject, used.}: int;
    var it{.inject.}: typeof(items(collection), typeOfIter);
    op), typeOfProc)
  var result = newSeqOfCap[OutType](collection.len)
  for i {.inject.}, it {.inject.} in collection:
    result.add op
  result

proc cliFind*(color = true, exec = newSeq[string](), input: seq[string]): int =
  var patterns: seq[string]
  var paths: seq[Path]
  if input.len > 0:
    for i in input.low..input.high:
      let arg = input[i]
      proc alreadyAdded(arg: string): bool =
        anyIt(cast[seq[string]](paths), arg.isChildOf(it))
      if '/' in arg:
        if dirExists(arg) or fileExists(arg):
          if not arg.alreadyAdded:
            paths.add Path(arg)
        else:
          let g =
            if '*' in arg: arg
            elif arg[^1] == '/': '*' & arg
            else: arg & '*'
          for path in walkPattern(g):
            if not path.alreadyAdded:
              paths.add Path(path)
      elif '*' in arg:
        for pattern in arg.split('*'):
          if pattern.len > 0: patterns.add pattern
      elif not arg.alreadyAdded and (dirExists(arg) or fileExists(arg) and absolutePath(Path(arg)).parentDir != getCurrentDir()):
        paths.add Path(arg)
      else:
        patterns.add arg
  if patterns.len == 0: patterns = @[""]
  if paths.len == 0: paths = @[Path(".")]
  when defined(debug):
    echo patterns
    echo repr paths

  let findings = find(paths, patterns)
  if exec.len == 0:
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
  else:
    var m = createMaster()
    proc run(cmd: string) = discard execShellCmd(cmd)
    m.awaitAll:
      type Targets = enum
        toPaths = "{}",
        toFilenames = "{/}",
        toParentDirs = "{//}",
        toNoExtPaths = "{.}",
        toNoExtFilenames = "{/.}"
      var paths, filenames, parentDirs, noExtFilenames, noExtPaths = newSeq[string]()
      var pathsString, filenamesString, parentDirsString, noExtFilenamesString, noExtPathsString = ""
      template needs[T](variable: var T, constructor: T) =
        if variable.len == 0: variable = constructor
      template addFindExeReplacements() =
        for t in Targets:
          if allIndexes[ord(t)].len > 0:
            case t
            of toPaths: addReplacement($t, paths, mapIt(findings, it.path.string.quoteShell))
            of toFilenames: addReplacement($t, filenames, mapIt(findings, it.path.lastPathPart.string))
            of toParentDirs: addReplacement($t, parentDirs, mapIt(findings, it.path.parentDir.string))
            of toNoExtPaths: addReplacement($t, noExtPaths, mapIt(findings, it.path.stripExtension.string))
            of toNoExtFilenames: addReplacement($t, noExtFilenames, mapEnumeratedIt(findings, if it.kind == pcDir: needs(filenames, mapIt(findings, it.path.lastPathPart.string)); filenames[i] else: it.path.splitFile[1].string))
      for cmd in exec:
        let allIndexes = cmd.findAll(Targets.mapIt($it))
        if cmd.endsWith '+':
          let cmd = cmd[0..^2]
          var replacements = newSeqOfCap[(string, string)](Targets.enumLen)
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
            m.spawn run cmd.multiReplace(replacements) #TODO: Use indexes from `findAll` instead of searching again
        else:
          for i in findings.low..findings.high:
            var replacements = newSeqOfCap[(string, string)](Targets.enumLen)
            template addReplacement[T](toReplace: T, variable: var openArray[T], constructor: openArray[T]) =
              needs(variable, constructor)
              replacements.add (toReplace, variable[i])
            addFindExeReplacements()
            if replacements.len == 0:
              needs(paths, mapIt(findings, it.path.string.quoteShell))
              m.spawn run cmd & ' ' & paths[i]
            else:
              m.spawn run cmd.multiReplace(replacements)

proc f*() =
  dispatch(cliFind, cmdName = "f",
                    short = {"exec": 'x'},
                    help = {"exec": "Execute a command for each matching search result in parallel.\n" &
                                    "Alternatively, end this argument with \"+\" to execute the command once with all results as arguments.\n" & 
                                    "Example: f .nim -x \"$EDITOR\"+\n" &
                                    "The following placeholders are substituted before the command is executed:\n" &
                                    "\"{}\":   path (of the current search result)\n" &
                                    "\"{/}\":  basename\n" &
                                    "\"{//}\": parent directory\n" &
                                    "\"{.}\":  path without file extension\n" &
                                    "\"{/.}\": basename without file extension\n" &
                                    "Example: f .jpg -x 'convert {} {.}.png'\n" &
                                    "If no placeholder is present, an implicit \"{}\" at the end is assumed."})

when isMainModule:
  f()
