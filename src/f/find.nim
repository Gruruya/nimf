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

{.push checks: off.}

proc findOA*(text, pattern: openArray[char], start = 0): int {.inline.} =
  for i in start..text.len - pattern.len:
    if text[i] == pattern[0]:
      var matches = true
      for i2 in 1 ..< pattern.len:
        if text[i + i2] != pattern[i2]:
          matches = false
          break
      if matches: return i
  result = -1

template find*(text, pattern: string, start = 0): int =
  findOA(text, pattern, start)

proc find*(text: openArray[char], patterns: seq[string]): seq[int] =
  result = newSeqOfCap[int](patterns.len)
  var start = 0
  for pattern in patterns:
    if start > text.high: return @[]
    let where = text.findOA(pattern, start)
    if where == -1: return @[]
    result.add where
    start = where + pattern.len
