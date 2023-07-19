# Paths to ignore --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Directories that are skipped when recursively searching (by default), feel free to add to this.

import std/[os, sets, memfiles, streams], ./find

template readSVImpl(condition: bool, getChar: char): untyped =
  var afterComment = false
  var stripStart = -1
  var s = newStringOfCap(16)
  while condition:
    var c = getChar
    if afterComment:
      if c in separate:
        afterComment = false
      continue
    template checkEscaped: untyped =
      if s.len > 0:
        if s[^1] == '\\':
          if s.len == 1:
            s[0] = c
            continue
          else:
            s.setLen(s.len - 1) # Cut off one "\" from "\\#" or "\#"
            if s[^1] != '\\':
              stripStart = -1
              s.add c
              continue
    template ymove(s: var string): untyped =
      when nimvm:
        yield s
        s.setLen 0
      else:
        yield move(s)
    case c
    of separate:
      checkEscaped()
      stripStart = -1
      if s.len > 0:
        ymove s
    of comment:
      checkEscaped()
      afterComment = true
      if s.len > 0:
        if stripStart == 0:
          s.setLen 0
          stripStart = -1
        elif stripStart != -1:
          s.setLen stripStart
          stripStart = -1
          ymove s
        else:
          ymove s
    of strip:
      if stripStart == -1: stripStart = s.len
      s.add c
    else:
      stripStart = -1
      s.add c
  if s.len > 0:
    yield move(s)

type chars = char | set[char]

iterator readSV(path: string; separate: static[chars] = '\l'; comment: static[chars] = '#'; strip: static[chars] = ' '): string =
  ## CSV/TSV reader, allows comments (The line `elem,elem2 # This is a comment` is valid)
  var ms = newMemMapFileStream(path)
  readSVImpl(not ms.atEnd, ms.readChar())
  ms.close()

iterator staticReadSV(path: string; separate: static[chars] = '\l'; comment: static[chars] = '#'; strip: static[chars] = ' '): string =
  ## CSV/TSV reader, allows comments (The line `elem,elem2 # This is a comment` is valid)
  var file = staticRead(path)
  var i = -1
  readSVImpl((inc i; i <= file.high), file[i])

proc readConfig(path = static joinPath(getConfigDir(), "nimf", "ignore.csv")): HashSet[string] =
  result = static: initHashSet[string]()
  for s in readSV(path, {',', '\l'}):
    result.incl s

proc staticReadConfig(path: string): HashSet[string] {.compileTime.} =
  result = initHashSet[string]()
  for s in staticReadSV(path, {',', '\l'}):
    result.incl s

var found {.global.}: HashSet[string]
proc getIgnored(): HashSet[string] {.inline.} =
  const defaultIgnored = staticReadConfig(currentSourcePath() /../ "ignore.csv")
  var tried {.global.} = false
  if not tried:
    tried = true
    try: result = readConfig(); found = result
    except: result = defaultIgnored
  else: result = if found.len > 0: found else: defaultIgnored

func filename(path: string): string {.inline.} =
  if likely path.len > 1 and path.isAbsolute: # Doesn't strip `./`
    let lastSlash = path.rfind(['/'], start = 1, last = path.high)
    if likely lastSlash.isSome: path[lastSlash.unsafeGet + 1..path.high]
    else: path[1 .. ^1]
  else: path

proc ignoreDir*(dir: string): bool {.inline.} =
  {.gcsafe.}: dir.filename in getIgnored()
