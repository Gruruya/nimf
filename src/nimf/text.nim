# Text matching --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Text matching like find("string with pattern", "pattern")

import std/options
export options

{.push inline, checks: off.}

func continuesWith*(text, substr: openArray[char]; start: Natural): bool =
  ## Checks if `substr` is in `text` starting at `start`
  for i in substr.low..substr.high:
    if text[i + start] != substr[i]: return false
  result = true

func find*(text, pattern: openArray[char]; start = 0.Natural, last: Natural): Option[Natural] =
  for i in start..last:
    if text.continuesWith(pattern, i):
      return some i
  result = none Natural

func find*(text, pattern: openArray[char]; start = 0.Natural): Option[Natural] =
  find(text, pattern, start, text.len - pattern.len)

func toLowerAscii*(c: char): char =
  if c in {'A'..'Z'}:
    char(uint8(c) xor 0b0010_0000'u8)
  else: c

func cmpInsensitive*(a, b: char): bool =
  a.toLowerAscii == b.toLowerAscii

func continuesWith*(text, substr: openArray[char]; start: Natural; cmp: proc): bool =
  ## Checks if `substr` is in `text` starting at `start`, custom comparison procedure variant
  for i in substr.low..substr.high:
    if not cmp(text[i + start], substr[i]): return false
  result = true

func findI*(text, pattern: openArray[char]; start = 0.Natural, last: Natural): Option[Natural] =
  for i in start..last:
    if text.continuesWith(pattern, i, cmpInsensitive):
      return some i
  result = none Natural

func findI*(text, pattern: openArray[char], start = 0.Natural): Option[Natural] =
  findI(text, pattern, start, text.len - pattern.len)

func preceedsWith*(text, substr: openArray[char]; last: Natural): bool =
  ## Checks if `substr` is in `text` ending at `last`, custom comparison procedure variant
  for i in substr.low..substr.high:
    if text[last - i] != substr[^(i + 1)]: return false
  result = true

func rfind*(text, pattern: openArray[char]; start, last: Natural): Option[Natural] =
  for i in countdown(last, start):
    if text.preceedsWith(pattern, i):
      return some i
  result = none Natural

func rfind*(text, pattern: openArray[char]; start: Natural): Option[Natural] =
  rfind(text, pattern, start, text.high)
func rfind*(text, pattern: openArray[char]; last: Natural): Option[Natural] =
  rfind(text, pattern, pattern.high, last)
func rfind*(text, pattern: openArray[char]): Option[Natural] =
  rfind(text, pattern, pattern.high, text.high)

func preceedsWith*(text, substr: openArray[char]; last: Natural; cmp: proc): bool =
  ## Checks if `substr` is in `text` ending at `last`, custom comparison procedure variant
  for i in substr.low..substr.high:
    if not cmp(text[last - i], substr[^(i + 1)]): return false
  result = true

func rfindI*(text, pattern: openArray[char], start, last: Natural): Option[Natural] =
  for i in countdown(last, start):
    if text.preceedsWith(pattern, i, cmpInsensitive):
      return some i
  result = none Natural

func rfindI*(text, pattern: openArray[char], start: Natural): Option[Natural] =
  rfindI(text, pattern, start, text.high)
func rfindI*(text, pattern: openArray[char], last: Natural): Option[Natural] =
  rfindI(text, pattern, pattern.high, last)
func rfindI*(text, pattern: openArray[char]): Option[Natural] =
  rfindI(text, pattern, pattern.high, text.high)

func containsAny*(string: openArray[char], chars: set[char]): bool {.inline.} =
  for c in string:
    if c in chars: return true
  result = false

func containsAny*(strings: openArray[string], chars: set[char]): bool {.inline.} =
  for string in strings:
    if string.containsAny(chars): return true
  result = false

func find*(text: openArray[char], patterns: openArray[string], start: sink Natural = 0, last: sink int = -1): seq[Natural] =
  ## Patterns must match in order
  result = newSeqOfCap[Natural](patterns.len)
  let sensitive = patterns.containsAny({'A'..'Z'})
  for pattern in patterns:
    if pattern.len == 0:
      result.add 0
      continue
    if start > text.high: return @[]

    if last == -1: last = text.len - pattern.len
    let where = if sensitive: text.find(pattern, start, last)
                        else: text.findI(pattern, start, last)

    if where.isNone: return @[]
    result.add where.unsafeGet
    start = where.unsafeGet + pattern.len

func findAll*(text, pattern: openArray[char]): seq[Natural] =
  ## Find all matches in any order
  if unlikely pattern.len == 0: return @[]
  var i = text.low
  while i <= text.high and pattern.len + i <= text.len:
    if text.continuesWith(pattern, i):
      result.add i
      inc(i, pattern.len)
    else:
      inc(i)

func findAll*(text: openArray[char], patterns: openArray[string]): seq[seq[Natural]] =
  ## Find all matches in any order for all patterns in a single pass
  result = newSeq[seq[Natural]](patterns.len)
  for i in text.low..text.high:
    for j, pattern in patterns:
      if pattern.len + i <= text.len and
         (result[j].len == 0 or result[j][^1] + pattern.len <= i) and
         text.continuesWith(pattern, i):
           result[j].add i

func endsWith*(text, suffix: openArray[char]): bool {.inline.} =
  suffix.high <= text.high and text.preceedsWith(suffix, text.high)

# Workaround for `system.find`
template find*(text: openArray[char], pattern: string): Option[Natural] = find(text, pattern, 0)
template find*(text: string, patterns: openArray[string]): seq[Natural] = find(text, patterns, 0)
