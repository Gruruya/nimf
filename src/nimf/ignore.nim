# Paths to ignore --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Directories that are skipped when recursively searching (by default), feel free to add to this.
## Count your directory sizes with `f -a -td -d1 -e 'echo $(f {} | wc -l) {}' | sort -n` in your home dir to find others to ignore.

import std/[os, sets], ./find
import std/[memfiles, streams]

proc readConfig(path = static getConfigDir() / "nimf" / "ignore.csv"): HashSet[string] {.inline.} =
  type chars = char | set[char]
  iterator readSV(path: string; separate: static[chars] = '\l'; comment: static[chars] = '#'; strip: static[chars] = ' '): string =
    ## CSV/TSV reader, allows comments (The line `elem,elem2 # This is a comment` is valid)
    var ms = newMemMapFileStream(path)
    var afterComment = false
    var stripStart = -1
    var s = newStringOfCap(16)
    while not ms.atEnd:
      var c = ms.readChar()
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
      case c
      of separate:
        checkEscaped()
        stripStart = -1
        if s.len > 0: yield move(s)
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
            yield move(s)
          else:
            yield move(s)
      of strip:
        if stripStart == -1: stripStart = s.len
        s.add c
      else:
        stripStart = -1
        s.add c
    if s.len > 0:
      yield move(s)
    ms.close()

  result = static: initHashSet[string]()
  for s in readSV(path, {',', '\l'}):
    result.incl s

var found {.global.}: HashSet[string]
proc getIgnored(): HashSet[string] {.inline.} =
  const defaultIgnored =
    toHashSet([
      ".git",
      ".cache", "nimcache", "__pycache__",
      "venv", "node_modules",
      ".npm", ".rustup", ".cargo"
    ])

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
