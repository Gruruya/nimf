# Paths to ignore --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Directories that are skipped when recursively searching (by default), feel free to add to this.
## Count your directory sizes with `f -a -td -d1 -e 'echo $(f {} | wc -l) {}' | sort -n` in your home dir to find others to ignore.

import std/[os, sets], ./find
import std/[memfiles, streams]

proc readConfig(path = static getConfigDir() / "nimf" / "ignore.csv"): HashSet[string] {.inline.} =
  iterator readSV(path: string; separators: char | set[char], eat: char | set[char] = {'\l'}): string =
    template contains(x: char; y: char): bool = x == y
    var ms = newMemMapFileStream(path)
    var s = newStringOfCap(16)
    while not ms.atEnd:
      var c = ms.readChar()
      if c in separators:
        yield s
        s.setLen 0
      elif c notin eat:
        s.add move(c)
    if s.len != 0:
      yield s
    ms.close()
  template readCSV(path: string): string =
    readSV(path, ',')

  result = static: initHashSet[string]()
  for s in readCSV(path):
    result.incl s

proc getIgnored(): HashSet[string] {.inline.} =
  const defaultIgnored =
    toHashSet([
      ".git",
      ".cache", "nimcache", "__pycache__",
      "venv", "node_modules",
      ".npm", ".rustup", ".cargo"
    ])

  var tried {.global.} = false
  var found {.global.}: HashSet[string]
  if unlikely (not tried):
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
