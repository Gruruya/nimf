# Handling matching paths --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Procedures used once a file has matched.

import ./[common, text, color], std/[os, paths, options, sets, tables, times], pkg/malebolgia
from   std/strutils import join
from   std/sequtils import mapIt, anyIt
from   std/typetraits import enumLen
from   std/nativesockets import getHostname
export LSColors, parseLSColorsEnv, times

var lscolors*: LSColors

type
  Target = enum
    toPaths = "{}",
    toFilenames = "{/}",
    toParentDirs = "{//}",
    toNoExtPaths = "{.}",
    toNoExtFilenames = "{/.}"

  Command* = object
    line*: string
    allIndexes*: seq[seq[Natural]]
    placements*: seq[(Natural, Natural)]

  FileTypes* = object
    kinds*: set[PathComponent]
    extensions*: HashSet[string]

  RunOptionAction* = enum
    plainPrint, coloredPrint, collect, exec

  RunOption* = object
    searchAll*: bool
    exclude*: seq[tuple[pattern: string, fullmatch: bool]]
    types*: FileTypes
    maxDepth* = 0
    maxFound* = 0
    timeLimit* = 0.milliseconds
    followSymlinks*: bool

    case action*: RunOptionAction
    of plainPrint, coloredPrint:
      null*: bool
      case hyperlink*: bool
      of true:
        hyperlinkPrefix*: string
        hyperlinkCwd*: string
      else: discard
    of exec:
      cmds*: seq[Command]
    else: discard

proc init*(T: type RunOption; action: RunOptionAction; followSymlinks = false; searchAll = false; exclude = newSeq[string](); types = FileTypes(); maxDepth = 0; maxFound = 0; timeLimit = 0.milliseconds): T {.inline.} =
  result = RunOption(action: action, followSymlinks: followSymlinks, searchAll: searchAll, types: types, maxDepth: maxDepth, maxFound: maxFound, timeLimit: timeLimit)
  if result.types.kinds == {}:
    result.types.kinds = {pcFile, pcDir, pcLinkToFile, pcLinkToDir}
  for x in exclude:
    if x.len > 0: result.exclude.add (x, x.len > 1 and x.find(['/'], 1, x.high - 1).isSome)

proc init*(T: type RunOption; action: RunOptionAction; followSymlinks = false; searchAll = false; exclude = newSeq[string](); types = FileTypes(); maxDepth = 0; maxFound = 0; timeLimit = 0.milliseconds; cmds: seq[Command]): T {.inline.} =
  assert action == exec
  result = RunOption.init(action, followSymlinks, searchAll, exclude, types, maxDepth, maxFound, timeLimit)
  result.cmds = cmds

proc init*(T: type RunOption; action: RunOptionAction; followSymlinks = false; searchAll = false; exclude = newSeq[string](); types = FileTypes(); maxDepth = 0; maxFound = 0; timeLimit = 0.milliseconds; null, hyperlink: bool): T =
  assert action in {plainPrint, coloredPrint}
  result = RunOption.init(action, followSymlinks, searchAll, exclude, types, maxDepth, maxFound, timeLimit)
  result.null = null
  {.cast(uncheckedAssign).}:
    result.hyperlink = hyperlink
  if hyperlink:
    result.hyperlinkPrefix = "\e]8;;file://" & encodeHyperlink(getHostname())
    result.hyperlinkCwd = encodeHyperlink(os.getCurrentDir()) & '/'

const Targets = (proc(): array[Target.enumLen, string] =
                   for t in Target: result[ord(t)] = $t)()

func kwayMerge[T: Ordinal](sortedSeqs: openArray[seq[T]]): seq[(T, Natural)] =
  ## k-way merge, flattens and sorts (ascending) `sortedSeqs`. Assumes each `seq[T]` is sorted.
  if likely sortedSeqs.len >= 0:
    var indices = newSeq[int](sortedSeqs.len)
    while true:
      var minIdx: Natural
      var minFound = false
      for i in 0.Natural..sortedSeqs.high:
        if indices[i] <= sortedSeqs[i].high and (not minFound or sortedSeqs[i][indices[i]] < sortedSeqs[minIdx][indices[minIdx]]):
          minIdx = i
          minFound = true
      if not minFound: break
      result.add (sortedSeqs[minIdx][indices[minIdx]], minIdx)
      inc indices[minIdx]

func init*(T: type Command; line: string): T =
  result = T(line: line, allIndexes: line.findAll(Targets))
  result.placements = result.allIndexes.kwayMerge

template add(x: var string, y: varargs[string]) =
  for j in y: system.add(x, j)

proc color*(found: Found, patterns: openArray[string]): string =
  template path: untyped = found.path.string
  let parentSep =
    if path.len == 1: -1
    else: path.rfind("/", last = path.high - 1).getIt(it.int, -1)

  let dirColor = lscolors.types.getOrDefault(etDirectory, ansiResetCode)
  let fileColor =
    if found.kind == pcDir: dirColor # optimization
    else: lscolors.styleForPath(found)
  let highlightColor =
    if likely ansiCode("01;31") notin [dirColor, fileColor]: ansiCode("01;31") # Bright red
    elif ansiCode("01;33") notin [dirColor, fileColor]: ansiCode("01;33") # Bright yellow
    else: ansiCode("01;36") # Bright cyan (other colors are red and yellow)

  if patterns == @[""]:
    if parentSep != -1: result = dirColor & path[0..parentSep]
    result.add fileColor & path[parentSep + 1..^1] & ansiResetCode
  else:
    var start = 0
    # TODO: Unroll first loop and check for ansiresetcode
    for i in 0..found.matches.high:
      let matchStart = found.matches[i][0]
      let matchEnd = found.matches[i][1]

      if parentSep < start:
        result.add fileColor, path[start ..< matchStart]
      elif dirColor == fileColor or parentSep >= matchStart:
        result.add dirColor, path[start ..< matchStart]
      else:
        result.add dirColor, path[start .. parentSep]
        result.add fileColor, path[parentSep + 1 ..< matchStart]

      result.add highlightColor, path[matchStart..matchEnd]
      start = matchEnd + 1

    if start != path.len:
      if start > parentSep or dirColor == fileColor:
        result.add fileColor, path[start..path.high]
      else:
        result.add dirColor, path[start .. parentSep]
        result.add fileColor, path[parentSep + 1 .. path.high]

    result.add ansiResetCode

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

template replaceAtImpl(indexing: static bool): untyped =
  var start = text.low
  for target in placements:
    result &= text[start ..< target.where]
    result &= (when indexing: replacements[T(target.which)][index] else: replacements[T(target.which)])
    start = target.where + len($T(target.which))
  if start <= text.high:
    result &= text[start .. text.high]

func replaceAt[T: enum](text: string; placements: openArray[tuple[where, which: Natural]]; replacements: array[T, string]): string =
  ## Replaces at each `placements.where` index the `enum` text with `replacements[enum]`
  replaceAtImpl(indexing = false)

func replaceAt[T: enum](text: string; placements: openArray[tuple[where, which: Natural]]; replacements: array[T, seq[string]]; index: Natural): string =
  ## Replaces at each `placements.where` index the `enum` text with `replacements[enum][index]`
  replaceAtImpl(indexing = true)

func rstripSlash(s: sink string): string {.inline.} =
  if s[^1] == '/': s.setLen(s.len - 1)
  result = s

proc execShell(cmd: string) = discard execShellCmd(cmd)

proc run*(cmds: sink seq[string], findings: seq[Found]) =
  ## Run the commands on the findings, used for after-the-fact/batched --exec
  #TODO: Stream those which don't end in +
  template needs(t: Target) =
    if replacements[t].len == 0: replacements[t] =
      case t
      of toPaths: mapIt(findings, it.path.string.rstripSlash.quoteShell)
      of toFilenames: mapIt(findings, it.path.lastPathPart.string.quoteShell)
      of toParentDirs: mapIt(findings, it.path.parentDir.string.quoteShell)
      of toNoExtPaths: mapIt(findings, it.path.stripExtension.string.rstripSlash.quoteShell)
      of toNoExtFilenames: mapEnumeratedIt(findings, if it.kind == pcDir:
                                                       if replacements[toFilenames].len > 0: replacements[toFilenames][i]
                                                       else: it.path.lastPathPart.string.quoteShell
                                                     else: it.path.splitFile[1].string.quoteShell)

  template needsJoined(t: Target) =
    if replacementsJoined[t].len == 0:
      needs(t)
      replacementsJoined[t] = replacements[t].join(" ")

  var replacements: array[Target, seq[string]]
  var replacementsJoined: array[Target, string]

  var m = createMaster()
  m.awaitAll:
    for cmd in cmds.mitems:
      let allIndexes = cmd.findAll(Targets)
      let placements = allIndexes.kwayMerge
      if cmd.endsWith "+":
        cmd.setLen(cmd.len - 1)
        var anyPlaceholders = false
        for t in Target:
          if allIndexes[ord(t)].len > 0:
            needsJoined(t)
            anyPlaceholders = true
        if not anyPlaceholders:
              m.spawn execShell cmd & ' ' & (needsJoined(toPaths); replacementsJoined[toPaths])
        else: m.spawn execShell cmd.replaceAt(placements, replacementsJoined)
      else:
        let anyPlaceholders = anyIt(allIndexes, it.len > 0)
        for i in findings.low..findings.high:
          for t in Target:
            if allIndexes[ord(t)].len > 0:
              needs(t)
          if not anyPlaceholders:
                m.spawn execShell cmd & ' ' & (needs(toPaths); replacements[toPaths][i])
          else: m.spawn execShell cmd.replaceAt(placements, replacements, i)

proc run*(m: MasterHandle; cmds: seq[Command], found: Found) =
  ## Run the commands on the findings, used for streaming --exec
  template needs(t: Target) =
    replacements[t] =
      case t
      of toPaths: found.path.string.rstripSlash.quoteShell
      of toFilenames: found.path.lastPathPart.string.quoteShell
      of toParentDirs: found.path.parentDir.string.quoteShell
      of toNoExtPaths: found.path.stripExtension.string.rstripSlash.quoteShell
      of toNoExtFilenames: (if found.kind == pcDir: found.path.lastPathPart.string.quoteShell
                            else: found.path.splitFile[1].string.quoteShell)

  var replacements: array[Target, string]
  for cmd in cmds.items:
    var anyPlaceholders = false
    for t in Target:
      if cmd.allIndexes[ord(t)].len > 0:
        needs(t)
        anyPlaceholders = true
    if not anyPlaceholders:
          m.spawn execShell cmd.line & ' ' & (needs(toPaths); replacements[toPaths])
    else: m.spawn execShell cmd.line.replaceAt(cmd.placements, replacements)

when isMainModule:
  lscolors = parseLSColorsEnv()
  let plain = Found(path: Path "handling.nim", matches: @[(0, 0)])
  echo color(plain, @[""])

  let andl = Found(path: Path "handling.nim", matches: @[(1, 4)])
  echo color(andl, @["andl"])
