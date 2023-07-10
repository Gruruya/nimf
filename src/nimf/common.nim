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
