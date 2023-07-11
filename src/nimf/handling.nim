# Handling matching paths --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Procedures used once a file has matched.

import ./[common, find, color], std/[os, terminal, paths, options, tables], pkg/malebolgia
from   std/strutils import join
from   std/sequtils import mapIt, anyIt
from   std/typetraits import enumLen
export LSColors, parseLSColorsEnv

var lscolors*: LSColors

type runOption* = enum
  plainPrint, coloredPrint, collect

template add(x: var string, j: varargs[string]) =
  for y in j:
    system.add(x, y)

proc color*(found: Found, patterns: openArray[string]): string =
  template path: untyped = found.path.string
  let parentLen = block:
    let lastSlash = path.rfind("/", last = path.high - 1)
    if lastSlash.isNone: -1
    else: lastSlash.unsafeGet

  let dirColor = getOrDefault(lscolors.types, etDirectory, defaultStyle()).toAnsiCode
  let fileColor =
    if found.kind == pcDir: dirColor # optimization
    else: lscolors.styleForPath(found).toAnsiCode

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

proc run*(cmds: sink seq[string], findings: seq[Found]) =
  ## Run the commands on the findings
  type Target = enum
    toPaths = "{}",
    toFilenames = "{/}",
    toParentDirs = "{//}",
    toNoExtPaths = "{.}",
    toNoExtFilenames = "{/.}"

  const Targets = (proc(): array[Target.enumLen, string] =
                     for t in Target: result[ord(t)] = $t)()

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
    for cmd in cmds.mitems:
      let allIndexes = cmd.findAll(Targets)
      let placements = allIndexes.kwayMerge
      if cmd.endsWith "+":
        cmd.setLen(cmd.len - 1)
        var anyPlaceholders = false
        var replacementPairs = static:
          (proc: array[Target.enumLen, (string, string)] =
            for i in 0..Targets.high: result[i][0] = Targets[i])()
        for t in Target:
          if allIndexes[ord(t)].len > 0:
            replacementPairs[ord(t)][1] = getReplacementJoined(t, findings)
            anyPlaceholders = true
        if not anyPlaceholders:
              m.spawn run cmd & ' ' & getReplacementJoined(toPaths, findings)
        else: m.spawn run cmd.replaceAt(placements, replacementPairs)
      else:
        let anyPlaceholders = anyIt(allIndexes, it.len > 0)
        for i in findings.low..findings.high:
          var replacementPairs = static:
            (proc: array[Target.enumLen, (string, string)] =
              for i in 0..Targets.high: result[i][0] = Targets[i])()
          for t in Target:
            if allIndexes[ord(t)].len > 0:
              replacementPairs[ord(t)][1] = getReplacement(t, findings)[i]
          if not anyPlaceholders:
                m.spawn run cmd & ' ' & getReplacement(toPaths, findings)[i]
          else: m.spawn run cmd.replaceAt(placements, replacementPairs)
