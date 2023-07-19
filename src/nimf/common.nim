# Workaround for recursive dependencies --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

import std/[os, paths, posix, options], ./find

type
  Found* = object
    path*: Path
    matches*: seq[(int, int)]
    case kind*: PathComponent
    of pcFile:
      stat*: Option[Stat]
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

template getIt*[T, R](self: Option[T], callback: untyped; otherwise: R): R =
  let tmp = self
  if tmp.isSome:
    template it: untyped {.inject.} = tmp.unsafeGet
    callback
  else:
    otherwise

template filename*(path: string): string =
  ## For `walkDir` `descendent.path`, `path` is either a filename or an absolute path.
  if likely path.len > 1 and path.isAbsolute: # Doesn't strip `./`
    let lastSlash = path.rfind(['/'], start = 1, last = path.high)
    if likely lastSlash.isSome: path[lastSlash.unsafeGet + 1..path.high]
    else: path[1 .. ^1]
  else: path
