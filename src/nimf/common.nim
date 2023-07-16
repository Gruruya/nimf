# Workaround for recursive dependencies --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

import std/[paths, os, posix]

type
  Found* = object
    path*: Path
    matches*: seq[(int, int)]
    case kind*: PathComponent
    of pcFile:
      stat*: Stat
    of pcLinkToFile:
      broken*: bool
    else: discard

{.push inline.}

func toHex(x: char): array[2, char] =
  const HexChars = "0123456789ABCDEF"
  [HexChars[(ord(x) shr 4 and 0xf)], HexChars[(ord(x) and 0xF)]]

template add(x: var string, y: varargs[char]) =
  for j in y: system.add(x, j)

func encodeHyperlink*(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    if c in {'\32'..'\126'}:
      result.add c
    else:
      result.add '%'
      result.add toHex(c)

