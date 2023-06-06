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

import ./[find, findFiles], pkg/[cligen, malebolgia], std/[terminal, paths]
import std/os except getCurrentDir
from std/strutils import startsWith, endsWith, multiReplace
from std/sequtils import anyIt
from std/posix import sysconf, SC_ARG_MAX # Could make Windows compatible, according to ChatGPT the general limit on there is 32767
from std/envvars import envPairs
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
          parentDirsString = parentDirs.join(" ") # need findAll and then get count that way
          noExtFilenamesString = noExtFilenames.join(" ")
          noExtPathsString = noExtPaths.join(" ")
          argMax = sysconf(SC_ARG_MAX) # Maximum (byte) length for a command, includes the command and environment variables
          cmdLen = getAppFilename().len + 1
          envLen = countEnvLen()
          batchMax = argMax - cmdLen - envLen - 1 # cmd array null terminator, also need to consider null terminator/space per item
          # unicode chars could be an issue?
        for inCmd in exec:
          if inCmd.endsWith '+':
            var replaceLocations = inCmd.findAll(@["{}", "{/}", "{//}", "{/.}", "{.}"])
            var replacements = @[0]
            var batchStart = 0
            var batchEnd = min(inCmd.len, batchMax)
            # while true # iterate over batchSize
            let inCmd = inCmd[0..^2]
            # var cmd = inCmd.multiFindAll(("{}", pathsString),
            #                              ("{/}", filenamesString),
            #                              ("{//}", parentDirsString),
            #                              ("{/.}", noExtFilenamesString),
            #                              ("{.}", noExtPathsString))
#            if cmd == inCmd: cmd = inCmd & ' ' & pathsString
#            m.spawn run cmd # Seem to be hitting a command-line limit, should look into that
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
