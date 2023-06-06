# f --- Text finder
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
#
# This file is part of f.
#
# f is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, version 3 of the License.
#
# f is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with f.  If not, see <http://www.gnu.org/licenses/>.

## Finding primitives

{.push inline, checks: off.}

func continuesWith(text, substr: openArray[char], start: Natural): bool =
  ## Checks if `substr` is in `text` starting at `start`
  for i in 0 .. substr.high:
    if text[i + start] != substr[i]: return false
  result = true

func findOA*(text, pattern: openArray[char], start = 0): int =
  for i in start..text.len - pattern.len:
    if text.continuesWith(pattern, i):
      return i
  result = -1

func toLowerAscii(c: char): char =
  if c in {'A'..'Z'}:
    char(uint8(c) xor 0b0010_0000'u8)
  else: c

func cmpInsensitive(a, b: char): bool =
  a.toLowerAscii == b.toLowerAscii

func continuesWith(text, substr: openArray[char], start: Natural, cmp: proc): bool =
  ## Checks if `substr` is in `text` starting at `start`, custom comparison procedure variant
  for i in 0 .. substr.high:
    if not cmp(text[i + start], substr[i]): return false
  result = true

func findI*(text, pattern: openArray[char], start = 0): int =
  for i in start..text.len - pattern.len:
    if text.continuesWith(pattern, i, cmpInsensitive):
      return i
  result = -1

template find*(text, pattern: string, start = 0): int =
  ## Patterns must match in order
  findOA(text, pattern, start)

func find*(text: openArray[char], patterns: seq[string]): seq[int] =
  ## Patterns must match in order
  var sensitive = false
  block smartCase:
    for s in patterns:
      for c in s:
        if c in {'A'..'Z'}:
          sensitive = true
          break smartCase
  result = newSeqOfCap[int](patterns.len)
  var start = 0
  for pattern in patterns:
    if pattern.len == 0:
      result.add 0
      continue
    if start > text.high: return @[]
    let where = if sensitive: text.findOA(pattern, start) else: text.findI(pattern, start)
    if where == -1: return @[]
    result.add where
    start = where + pattern.len

func continuesWithB(text, substr: openArray[char], start: Natural): bool =
  ## Checks if `substr` is in `text` starting at `start`, bounds-checking variant
  if substr.high + start < text.len:
        continuesWith(text, substr, start)
  else: false

func findAll*(text, pattern: openArray[char]): seq[int] =
  ## Find all matches in any order
  if unlikely pattern.len == 0: return @[]
  var i = 0
  while i < text.len:
    if text.continuesWithB(pattern, i):
      result.add i
      inc(i, pattern.len)
    else:
      inc(i)

func findAll*(text: openArray[char], patterns: seq[string]): seq[seq[int]] =
  ## Find all matches in any order for all patterns in a single pass
  result = newSeq[seq[int]](patterns.len)
  for i in 0..text.high:
    for j, pattern in patterns:
      if (result[j].len == 0 or i >= result[j][^1] + pattern.len) and
         text.continuesWithB(pattern, i):
           result[j].add i
