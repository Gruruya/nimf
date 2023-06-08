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

import ./[find, findFiles], pkg/[cligen, cligen/argcvt, malebolgia], std/[terminal, paths, macros]
import std/os except getCurrentDir
from std/strutils import startsWith, endsWith, multiReplace, rfind, toLowerAscii
from std/sequtils import anyIt, mapIt
from std/typetraits import enumLen
export cligen

proc display(found: Found, patterns: seq[string]) =
  let path = found.path.string
  var line = ""
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

type Target = enum
  toPaths = "{}",
  toFilenames = "{/}",
  toParentDirs = "{//}",
  toNoExtPaths = "{.}",
  toNoExtFilenames = "{/.}"

proc run(cmds: seq[string], findings: seq[Found]) =
  var replacementsStored: array[Target, seq[string]]
  var replacementsJoinedStored: array[Target, string]
  template needs[T](variable: var T, constructor: T): untyped =
    if variable.len == 0: variable = constructor
    variable
  template getReplacement(t: Target; findings: seq[Found]): seq[string] =
    needs(replacementsStored[t],
      case t
      of toPaths: mapIt(findings, it.path.string.quoteShell)
      of toFilenames: mapIt(findings, it.path.lastPathPart.string.quoteShell)
      of toParentDirs: mapIt(findings, it.path.parentDir.string.quoteShell)
      of toNoExtPaths: mapIt(findings, it.path.stripExtension.string.quoteShell)
      of toNoExtFilenames: mapEnumeratedIt(findings, if it.kind == pcDir: needs(replacementsStored[toFilenames], mapIt(findings, it.path.lastPathPart.string.quoteShell))[i] else: it.path.splitFile[1].string.quoteShell))
  template getReplacementJoined(t: Target; findings: seq[Found]): string =
    needs(replacementsJoinedStored[t], getReplacement(t, findings).join(" "))

  proc run(cmd: string) = discard execShellCmd(cmd)
  var m = createMaster()
  m.awaitAll:
    for cmd in cmds:
      let allIndexes = cmd.findAll(Target.mapIt($it))
      if cmd.endsWith '+':
        let cmd = cmd[0..^2]
        var replacements = newSeq[(string, string)]()
        for t in Target:
          if allIndexes[ord(t)].len > 0:
            replacements.add ($t, getReplacementJoined(t, findings))
        if replacements.len == 0:
              m.spawn run cmd & ' ' & getReplacementJoined(toPaths, findings)
        else: m.spawn run cmd.multiReplace(replacements) #TODO: Use indexes from `findAll` instead of searching again
      else:
        for i in findings.low..findings.high:
          var replacements = newSeqOfCap[(string, string)](Target.enumLen)
          for t in Target:
            if allIndexes[ord(t)].len > 0:
              replacements.add ($t, getReplacement(t, findings)[i])
          if replacements.len == 0:
                m.spawn run cmd & ' ' & getReplacement(toPaths, findings)[i]
          else: m.spawn run cmd.multiReplace(replacements)

# `options.Option` but also stores the input so we can negate flags without values like `-c`
type Flag[T] = object
  val: T
  has: bool
  input*: string
proc some[T](val: sink T): Flag[T] {.inline.} =
  result.has = true
  result.val = val
proc none[T](val: sink T): Flag[T] {.inline.} =
  result.has = false
  result.val = val
proc none(T: typedesc): Flag[T] {.inline.} = Flag[T]()
proc none[T]: Flag[T] {.inline.} = none(T)
proc isSome[T](self: Flag[T]): bool {.inline.} = self.has
proc isNone[T](self: Flag[T]): bool {.inline.} = not self.has
proc unsafeGet[T](self: Flag[T]): lent T {.inline.} =
  assert self.isSome
  result = self.val

proc isChildOf(path, potParent: string): bool =
  let aPotParent = absolutePath(Path(potParent))
  let aPath = absolutePath(Path(path))
  if aPath == aPotParent:
    return true
  for parent in aPath.parentDirs:
    if aPotParent == parent: return true
  result = false

proc cliFind*(color = none bool, exec = newSeq[string](), input: seq[string]): int =
  var patterns: seq[string]
  var paths: seq[Path]
  proc alreadyAdded(paths: seq[Path]; arg: string): bool {.inline.} =
    anyIt(cast[seq[string]](paths), arg.isChildOf(it))

  if input.len > 0:
    for i in input.low..input.high:
      let arg = input[i]
      block asPath:
        if dirExists(arg) or (fileExists(arg) and (absolutePath(Path(arg)).parentDir != getCurrentDir() or '/' in arg)):
          if not paths.alreadyAdded(arg):
            paths.add Path(arg)
          else:
            break asPath
        elif '/' in arg:
          let g =
            if '*' in arg: arg
            else:
              let sepPos = arg.rfind('/', last = arg.high - 1)
              if sepPos == -1 and i == input.high:
                break asPath # Trailing / at the end of all input means it's a directory pattern
              if arg[^1] == '/':
                    arg[0..sepPos] & '*' & arg[sepPos + 1..^2] & "*/"
              else: arg[0..sepPos] & '*' & arg[sepPos + 1..^1] & '*'
          var matched = false
          for path in walkPattern(g):
            matched = true
            if not paths.alreadyAdded(path):
              paths.add Path(path)
          if not matched: return
        else: break asPath
        continue
      if '*' in arg:
        for pattern in arg.split('*'):
          if pattern.len > 0: patterns.add pattern
      else:
        patterns.add arg
  if patterns.len == 0: patterns = @[""]
  if paths.len == 0: paths = @[Path(".")]

  let kinds =
    if patterns[^1][^1] == '/':
       patterns[^1].setLen patterns[^1].len - 1
       {pcDir, pcLinkToDir}
    else: {pcFile, pcLinkToFile}
  let findings = findFiles(paths, patterns, kinds = kinds)

  if exec.len == 0:
    let envColorEnabled = stdout.isatty and getEnv("NO_COLOR").len == 0
    let displayColor = color.isNone and envColorEnabled or
    color.isSome and (if color.input.len == 0: not envColorEnabled else: color.unsafeGet)
    for found in findings:
      if displayColor:
         display(found, patterns)
      else: echo found.path.string
  else:
    run(exec, findings)

# Special argument parsing
proc argParse[T](dst: var Flag[T], dfl: Flag[T], a: var ArgcvtParams): bool =
  var uw: T # An unwrapped value
  if argParse(uw, (if dfl.isSome: dfl.unsafeGet else: uw), a):
    dst = some uw; dst.input = a.val; true
  else: false

proc argHelp[T](dfl: Flag[T]; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, $T, (if dfl.isSome: $dfl.unsafeGet else: "?")]

proc f*() =
  dispatch(cliFind, cmdName = "f",
                    usage = (try: getAppFilename().lastPathPart except: "f") & " $args\n\n" &
                            "Entered `input` may be a pattern OR a path/path glob to search.\n" &
                            "Append `/` to the end of your pattern to search for directories.\n" &
                            "\nOptions:\n$options",
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
