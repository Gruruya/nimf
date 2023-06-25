# nimf --- Text finder
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
#
# This file is part of nimf.
#
# nimf is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, version 3 of the License.
#
# nimf is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with nimf.  If not, see <http://www.gnu.org/licenses/>.

## Finding primitives

{.push inline, checks: off.}

func continuesWith*(text, substr: openArray[char], start: Natural): bool =
  ## Checks if `substr` is in `text` starting at `start`
  for i in substr.low..substr.high:
    if text[i + start] != substr[i]: return false
  result = true

func find*(text, pattern: openArray[char], start = 0.Natural, last: Natural): int =
  for i in start..last:
    if text.continuesWith(pattern, i):
      return i
  result = -1

func find*(text, pattern: openArray[char], start = 0.Natural): int =
  text.find(pattern, start, text.len - pattern.len)

func preceedsWith(text, substr: openArray[char], last: Natural): bool =
  ## Checks if `substr` is in `text` backwards, ending at `last`
  for i in countdown(substr.high, substr.low):
    if text[i + last] != substr[i]: return false
  result = true

func rfind*(text, pattern: openArray[char], start = 0.Natural, last: Natural): int =
  for i in countdown(last, start):
    if text.preceedsWith(pattern, i):
      return i
  result = -1

func rfind*(text, pattern: openArray[char], start = 0.Natural): int =
  text.rfind(pattern, start, text.len - pattern.len)

func toLowerAscii(c: char): char =
  if c in {'A'..'Z'}:
    char(uint8(c) xor 0b0010_0000'u8)
  else: c

func cmpInsensitive(a, b: char): bool =
  a.toLowerAscii == b.toLowerAscii

func continuesWith(text, substr: openArray[char], start: Natural, cmp: proc): bool =
  ## Checks if `substr` is in `text` starting at `start`, custom comparison procedure variant
  for i in substr.low..substr.high:
    if not cmp(text[i + start], substr[i]): return false
  result = true

func findI*(text, pattern: openArray[char], start = 0.Natural, last: Natural): int =
  for i in start..last:
    if text.continuesWith(pattern, i, cmpInsensitive):
      return i
  result = -1

func findI*(text, pattern: openArray[char], start = 0.Natural): int =
  text.findI(pattern, start, text.len - pattern.len)

func containsAny(strings: openArray[string], chars: set[char]): bool {.inline.} =
  for string in strings:
    for c in string:
      if c in chars: return true
  result = false

func find*(text: openArray[char], patterns: openArray[string], start: sink Natural = 0, last: sink int = -1): seq[int] =
  ## Patterns must match in order
  result = newSeqOfCap[int](patterns.len)
  let sensitive = patterns.containsAny({'A'..'Z'})
  for pattern in patterns:
    if pattern.len == 0:
      result.add 0
      continue
    if start > text.high: return @[]

    if last == -1: last = text.len - pattern.len
    let where = if sensitive: text.find(pattern, start, last)
                        else: text.findI(pattern, start, last)

    if where == -1: return @[]
    result.add where
    start = where + pattern.len

func continuesWithB(text, substr: openArray[char], start: Natural): bool =
  ## Checks if `substr` is in `text` starting at `start`, bounds-checking variant
  if substr.len + start <= text.len:
    continuesWith(text, substr, start)
  else: false

func findAll*(text, pattern: openArray[char]): seq[int] =
  ## Find all matches in any order
  if unlikely pattern.len == 0: return @[]
  var i = text.low
  while i <= text.high:
    if text.continuesWithB(pattern, i):
      result.add i
      inc(i, pattern.len)
    else:
      inc(i)

func findAll*(text: openArray[char], patterns: openArray[string]): seq[seq[int]] =
  ## Find all matches in any order for all patterns in a single pass
  result = newSeq[seq[int]](patterns.len)
  for i in text.low..text.high:
    for j, pattern in patterns:
      if (result[j].len == 0 or i >= result[j][^1] + pattern.len) and
         text.continuesWithB(pattern, i):
           result[j].add i

# Workaround for `system.find`
template find*(text: openArray[char], pattern: string): int = find(text, pattern, 0)
template find*(text: string, patterns: openArray[string]): seq[int] = find(text, patterns, 0)
