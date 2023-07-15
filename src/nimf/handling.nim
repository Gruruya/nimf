# Handling matching paths --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Procedures used once a file has matched.

import ./[common, find, color], std/[os, paths, options, tables], pkg/malebolgia
from   std/strutils import join
from   std/sequtils import mapIt, anyIt
from   std/typetraits import enumLen
from   std/nativesockets import getHostname
export LSColors, parseLSColorsEnv

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

  runOptionKind* = enum
    plainPrint, coloredPrint, collect, exec

  runOption* = object
    case kind*: runOptionKind
    of plainPrint, coloredPrint:
      null*: bool
      case hyperlink*: bool
      of true:
        hyperlinkPrefix*: string
        cwd*: string
      else: discard
    of exec:
      cmds*: seq[Command]
    else: discard

proc init*(T: type runOption; kind: runOptionKind; null: bool; hyperlink: bool): T =
  assert kind in {plainPrint, coloredPrint}
  {.cast(uncheckedAssign).}:
    if hyperlink:
      runOption(kind: kind, null: null, hyperlink: true,
                hyperlinkPrefix: "\e]8;;file://" & encodeHyperlink(getHostname()),
                cwd: encodeHyperlink(os.getCurrentDir()) & '/')
    else: runOption(kind: kind, null: null, hyperlink: false)

const Targets = (proc(): array[Target.enumLen, string] =
                   for t in Target: result[ord(t)] = $t)()

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

func init*(T: type Command; line: string): T =
  result = T(line: line, allIndexes: line.findAll(Targets))
  result.placements = result.allIndexes.kwayMerge

template add(x: var string, j: varargs[string]) =
  for y in j: system.add(x, y)

proc color*(found: Found, patterns: openArray[string]): string =
  template path: untyped = found.path.string
  let parentSep = block:
    let lastSlash = path.rfind("/", last = path.high - 1)
    if lastSlash.isNone: -1
    else: lastSlash.unsafeGet

  let dirColor = getOrDefault(lscolors.types, etDirectory, defaultStyle()).toAnsiCode
  let fileColor =
    if found.kind == pcDir: dirColor # optimization
    else: lscolors.styleForPath(found).toAnsiCode
  let highlightColor =
    if likely "\e[1;31m" notin [dirColor, fileColor]: "\e[1;31m" # Bright red
    elif "\e[1;33m" notin [dirColor, fileColor]: "\e[1;33m" # Bright yellow
    else: "\e[1;36m" # Bright cyan (they have red/yellow as their other colors)

  if patterns == @[""]:
    result = dirColor & path[0..parentSep]
    result.add fileColor, path[parentSep + 1..^1]
  else:
    var start = 0
    for i in 0..found.matches.high:
      let matchStart = found.matches[i][0]
      let matchEnd = found.matches[i][1]

      if start > parentSep:
        result.add fileColor, path[start ..< matchStart]
      elif dirColor != fileColor and matchStart >= parentSep:
        result.add dirColor, path[start .. parentSep - (if parentSep == matchStart: 1 else: 0)]
        result.add fileColor, path[parentSep + 1 ..< matchStart]
      else:
        result.add dirColor, path[start ..< matchStart]

      result.add highlightColor, path[matchStart..matchEnd]
      start = matchEnd + 1

    if start != path.len:
      if start > parentSep or dirColor == fileColor:
        result.add fileColor, path[start..path.high]
      else:
        result.add dirColor, path[start .. parentSep]
        result.add fileColor, path[parentSep + 1 .. path.high]

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

proc execShell(cmd: string) = discard execShellCmd(cmd)

proc run*(cmds: sink seq[string], findings: seq[Found]) =
  ## Run the commands on the findings, used for after-the-fact/batched --exec
  #TODO: Stream those which don't end in +
  template needs(t: Target) =
    if replacements[t].len == 0: replacements[t] =
      case t
      of toPaths: mapIt(findings, it.path.string.quoteShell)
      of toFilenames: mapIt(findings, it.path.lastPathPart.string.quoteShell)
      of toParentDirs: mapIt(findings, it.path.parentDir.string.quoteShell)
      of toNoExtPaths: mapIt(findings, it.path.stripExtension.string.quoteShell)
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
      of toPaths: found.path.string.quoteShell
      of toFilenames: found.path.lastPathPart.string.quoteShell
      of toParentDirs: found.path.parentDir.string.quoteShell
      of toNoExtPaths: found.path.stripExtension.string.quoteShell
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
