# Main file/CLI --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## The CLI interface for nimf
import ./nimf/[common, find, findFiles, color, handling],
       pkg/[cligen, cligen/argcvt, malebolgia],
       std/[paths, tables, terminal, exitprocs]
import std/os except getCurrentDir
from   std/strutils import startsWith
from   std/sequtils import anyIt, mapIt
from   std/typetraits import enumLen

template add(x: var string, y: varargs[string]) =
  for j in y:
    system.add(x, j)

proc color(found: Found, patterns: seq[string], colors: LSColors): string =
  #TODO: Improve performance
  template path: untyped = found.path.string
  let parentLen = cast[Option[int]](path.rfind("/", last = path.high - 1)).get(-1)

  let dirColor = getOrDefault(colors.types, etDirectory, defaultStyle()).toAnsiCode
  let fileColor =
    if found.kind == pcDir: dirColor # optimization
    else: colors.styleForPath(found).toAnsiCode

  if patterns == @[""]:
    result = dirColor & path[0..parentLen]
    result.add fileColor, path[parentLen + 1..^1]
  else:
    var start = 0
    for i in 0..found.matches.high:
      let matchStart = found.matches[i][0]
      let matchEnd = found.matches[i][1]

      if start > parentLen:
        result.add fileColor, path[start ..< matchStart]
      elif dirColor != fileColor and matchStart >= parentLen:
        result.add dirColor, path[start .. parentLen - (if parentLen == matchStart: 1 else: 0)]
        result.add fileColor, path[parentLen + 1 ..< matchStart]
      else:
        result.add dirColor, path[start ..< matchStart]

      result.add "\e[1;" & $ord(fgRed) & 'm', path[matchStart..matchEnd]
      start = matchEnd + 1

    if start != path.len:
      if start > parentLen or dirColor == fileColor:
        result.add fileColor, path[start..path.high]
      else:
        result.add dirColor, path[start .. parentLen]
        result.add fileColor, path[parentLen + 1 .. path.high]

template mapEnumeratedIt[T](collection: openArray[T], op: untyped): seq =
  type OutType = typeof((block:
    var i {.inject.}: int;
    var it {.inject.}: typeof(items(collection), typeOfIter);
    op), typeOfProc)
  var result = newSeqOfCap[OutType](collection.len)
  for i {.inject.}, it {.inject.} in collection:
    result.add op
  result

proc stripExtension(path: Path): Path =
  let dotPos = searchExtPos(path.string)
  if dotPos == -1: path
  else: Path(path.string[0 ..< dotPos])

func kwayMerge[T: Ordinal](seqOfSeqs: openArray[seq[T]]): seq[(T, Natural)] =
  ## k-way merge, flattens and sorts (ascending) `seqOfSeqs`. Assumes each `seq[T]` is sorted.
  if likely seqOfSeqs.len >= 0:
    var indices = newSeq[int](seqOfSeqs.len)
    while true:
      var minIdx: Natural
      var first = true
      for i in 0.Natural..seqOfSeqs.high:
        if indices[i] <= seqOfSeqs[i].high and (first or seqOfSeqs[i][indices[i]] < seqOfSeqs[minIdx][indices[minIdx]]):
          minIdx = i
          first = false
      if first: break
      result.add (seqOfSeqs[minIdx][indices[minIdx]], minIdx)
      inc indices[minIdx]

func replaceAt(text: string; placements: openArray[tuple[where, which: Natural]]; replacements: openArray[tuple[sub, by: string]]): string =
  ## Replaces at each `placements.where` index the `replacements[placements.which].sub` text with `by`
  var start = text.low
  for target in placements:
    result &= text[start ..< target.where]
    result &= replacements[target.which].by
    start = target.where + replacements[target.which].sub.len
  if start <= text.high:
    result &= text[start .. text.high]

proc run(cmds: seq[string], findings: seq[Found]) =
  ## Run the commands on the findings
  type Target = enum
    toPaths = "{}",
    toFilenames = "{/}",
    toParentDirs = "{//}",
    toNoExtPaths = "{.}",
    toNoExtFilenames = "{/.}"

  var replacementsStored: array[Target, seq[string]]
  var replacementsJoinedStored: array[Target, string]

  template needs[T](variable: var T, constructor: T): T =
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
      let placements = allIndexes.kwayMerge
      if cmd.endsWith "+":
        let cmd = cmd[0..^2]
        var replacements: array[Target, string]
        for t in Target:
          if allIndexes[ord(t)].len > 0:
            replacements[t] = getReplacementJoined(t, findings)
        if replacements == default(typeof replacements):
              m.spawn run cmd & ' ' & getReplacementJoined(toPaths, findings)
        else: m.spawn run cmd.replaceAt(placements, Target.mapIt(($it, replacements[it])))
      else:
        for i in findings.low..findings.high:
          var replacements: array[Target, string]
          for t in Target:
            if allIndexes[ord(t)].len > 0:
              replacements[t] = getReplacement(t, findings)[i]
          if replacements == default(typeof replacements):
                m.spawn run cmd & ' ' & getReplacement(toPaths, findings)[i]
          else: m.spawn run cmd.replaceAt(placements, Target.mapIt(($it, replacements[it])))

# `options.Option` but also stores the input so we can negate flags without values like `-c`
type Flag[T] = object
  val*: T
  has*: bool
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

proc cliFind*(color = none bool, execute = newSeq[string](), followSymlinks = false, input: seq[string]): int =
  var patterns = newSeq[string]()
  var paths = newSeq[Path]()

  proc isChildOf(path, potParent: string): bool =
    let aPotParent = absolutePath(Path(potParent))
    let aPath = absolutePath(Path(path))
    if aPath == aPotParent:
      true
    else:
      for parent in aPath.parentDirs:
        if aPotParent == parent:
          return true
      false

  proc alreadyAdded(paths: seq[Path]; arg: string): bool {.inline.} =
    anyIt(paths, arg.isChildOf(it.string))

  if input.len > 0:
    for i in input.low..input.high:
      let arg = input[i]
      if arg != "/" and (dirExists(arg) or fileExists(arg) and (arg.startsWith("./") or absolutePath(Path(arg)).parentDir != getCurrentDir())) and not paths.alreadyAdded(arg):
        paths.add Path(arg)
      else:
        patterns.add arg
  if patterns.len == 0: patterns = @[""]
  if paths.len == 0: paths = @[Path(".")]

  template traverse(andDo: runOption): untyped =
    traverseFind(paths, patterns, {pcFile, pcDir, pcLinkToFile, pcLinkToDir}, followSymlinks, andDo)

  if execute.len == 0:
    let envColorEnabled = stdout.isatty and getEnv("NO_COLOR").len == 0
    let displayColor = color.isNone and envColorEnabled or
                       color.isSome and (if color.input.len == 0: not envColorEnabled else: color.unsafeGet)
    if displayColor:
      lscolors = parseLSColorsEnv()
      exitprocs.addExitProc(resetAttributes)
      discard traverse(coloredPrint)
      stdout.flushFile()
    else:
      discard traverse(plainPrint)
  else:
    run(execute, traverse(collect))

# Special argument parsing
proc argParse[T](dst: var Flag[T], dfl: Flag[T], a: var ArgcvtParams): bool =
  var uw: T # An unwrapped value
  result = argParse(uw, (if dfl.isSome: dfl.unsafeGet else: uw), a)
  if result: dst = some uw; dst.input = a.val
proc argHelp[T](dfl: Flag[T]; a: var ArgcvtParams): seq[string] =
  @[a.argKeys, $T, (if dfl.isSome: $dfl.unsafeGet else: "?")]

proc f*() =
  dispatch(cliFind, cmdName = "f",
                    usage = (try: getAppFilename().lastPathPart except: "f") & " $args\n\n" &
                            "Entered `input` may be a pattern OR a path to search.\n" &
                            "Append `/` to the end of your pattern to search for directories.\n" &
                            "\nOptions:\n$options",
                    short = {"followSymlinks": 'L'},
                    help = {"execute": "Execute a command for each matching search result in parallel.\n" &
                                    "Alternatively, end this argument with \"+\" to execute the command once with all results as arguments.\n" & 
                                    "Example: f .nim -e \"$EDITOR\"+\n" &
                                    "The following placeholders are substituted before the command is executed:\n" &
                                    "\"{}\":   path (of the current search result)\n" &
                                    "\"{/}\":  basename\n" &
                                    "\"{//}\": parent directory\n" &
                                    "\"{.}\":  path without file extension\n" &
                                    "\"{/.}\": basename without file extension\n" &
                                    "Example: f .jpg -e 'convert {} {.}.png'\n" &
                                    "If no placeholder is present, an implicit \"{}\" at the end is assumed."})

when isMainModule:
  f()
